import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// Erro retornado pela API Subsonic (`status: failed`) ou de rede.
class SubsonicException implements Exception {
  SubsonicException(this.message, {this.code});
  final String message;
  final int? code;

  bool get isAuthError => code == 40 || code == 41 || code == 44;

  @override
  String toString() => code != null ? 'Erro $code: $message' : message;
}

/// Credenciais já prontas para a API. Nunca guardamos a senha em texto:
/// só o token md5(senha + salt) e o salt (ou a API key, se o servidor suportar).
/// [connectKey] vem da senha no login (ver connect_auth.dart) e nunca vai para
/// a rede: é o que prova aos outros aparelhos que é a mesma conta.
class SubsonicAuth {
  const SubsonicAuth.token({required this.username, required this.token, required this.salt, this.connectKey}) : apiKey = null;
  const SubsonicAuth.apiKey(String key, {this.connectKey})
      : apiKey = key,
        username = null,
        token = null,
        salt = null;

  final String? username;
  final String? token;
  final String? salt;
  final String? apiKey;
  final String? connectKey;

  factory SubsonicAuth.fromPassword(String username, String password, {String? connectKey}) {
    final rnd = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final salt = List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
    // Bytes UTF-8 (não code units UTF-16), senão senhas com acento falham.
    final token = md5.convert(utf8.encode('$password$salt')).toString();
    return SubsonicAuth.token(username: username, token: token, salt: salt, connectKey: connectKey);
  }

  /// A senha digitada é a desta conta? (confere pelo token, sem ir ao servidor)
  bool matchesPassword(String password) =>
      token != null && salt != null && md5.convert(utf8.encode('$password$salt')).toString() == token;

  Map<String, String> get params => apiKey != null
      ? {'apiKey': apiKey!}
      : {'u': username!, 't': token!, 's': salt!};

  Map<String, dynamic> toJson() => {
        ...(apiKey != null ? {'apiKey': apiKey} : {'username': username, 'token': token, 'salt': salt}),
        'connectKey': ?connectKey,
      };

  static SubsonicAuth? fromJson(Map<String, dynamic> j) {
    final ck = j['connectKey'] is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(j['connectKey'] as String) ? j['connectKey'] as String : null;
    if (j['apiKey'] is String) return SubsonicAuth.apiKey(j['apiKey'] as String, connectKey: ck);
    if (j['username'] is String && j['token'] is String && j['salt'] is String) {
      return SubsonicAuth.token(username: j['username'], token: j['token'], salt: j['salt'], connectKey: ck);
    }
    return null;
  }
}

class SubsonicClient {
  SubsonicClient({required String baseUrl, String? localUrl, required this.auth, this.clientName = 'BKmasterplayer'})
      : remoteUrl = normalizeBaseUrl(baseUrl),
        _localUrl = _normalizeOptional(localUrl),
        _dio = Dio(BaseOptions(
          connectTimeout: _remoteConnectTimeout,
          receiveTimeout: const Duration(seconds: 30),
          responseType: ResponseType.json,
        ));

  static const apiVersion = '1.16.1';
  static const _remoteConnectTimeout = Duration(seconds: 10);
  // Na rede de casa o servidor responde na hora; se não, saiu de casa.
  static const _localConnectTimeout = Duration(seconds: 3);

  /// Endereço principal (funciona de qualquer lugar).
  final String remoteUrl;
  String? _localUrl;
  bool _onLocal = false;
  final SubsonicAuth auth;
  final String clientName;
  final Dio _dio;
  final _endpointChanges = StreamController<bool>.broadcast();

  /// Endereço em uso: o da rede de casa quando responde, senão o principal.
  String get baseUrl => _onLocal ? _localUrl! : remoteUrl;

  /// Endereço na rede de casa (opcional).
  String? get localUrl => _localUrl;
  bool get onLocal => _onLocal;

  /// true = passou a usar o endereço de casa; false = voltou para o principal.
  Stream<bool> get endpointChanges => _endpointChanges.stream;

  set localUrl(String? url) {
    _localUrl = _normalizeOptional(url);
    if (_localUrl == null) _setLocal(false);
  }

  static String? _normalizeOptional(String? url) =>
      (url == null || url.trim().isEmpty) ? null : normalizeBaseUrl(url);

  void _setLocal(bool local) {
    if (local == _onLocal) return;
    _onLocal = local;
    _dio.options.connectTimeout = local ? _localConnectTimeout : _remoteConnectTimeout;
    _endpointChanges.add(local);
  }

  /// Testa o endereço de casa (ping com as credenciais, tempo curto) e passa a
  /// usá-lo se responder; senão fica no principal. Devolve se está em casa.
  Future<bool> checkLocal() async {
    final local = _localUrl;
    if (local == null) return false;
    final ok = await _ping(local);
    // O endereço pode ter mudado enquanto testava.
    if (local == _localUrl) _setLocal(ok);
    return _onLocal;
  }

  Future<bool> _ping(String base) async {
    try {
      final res = await Dio(BaseOptions(
        connectTimeout: const Duration(milliseconds: 1500),
        receiveTimeout: const Duration(seconds: 3),
        responseType: ResponseType.json,
      )).get('$base/rest/ping', queryParameters: _baseParams, options: Options(validateStatus: (_) => true));
      final data = res.data;
      return data is Map && data['subsonic-response'] is Map && data['subsonic-response']['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  static bool _isUnreachable(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.connectionError ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.unknown =>
          true,
        _ => false,
      };

  static String normalizeBaseUrl(String url) {
    var u = url.trim();
    if (!u.contains('://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.endsWith('/rest')) u = u.substring(0, u.length - 5);
    return u;
  }

  Map<String, String> get _baseParams => {
        ...auth.params,
        'v': apiVersion,
        'c': clientName,
        'f': 'json',
      };

  /// URL completa (com autenticação) — usada para stream e capas.
  Uri uri(String endpoint, [Map<String, dynamic> params = const {}]) {
    final q = <String, dynamic>{..._baseParams};
    params.forEach((k, v) {
      if (v == null) return;
      q[k] = v is List ? v.map((e) => '$e').toList() : '$v';
    });
    q.remove('f');
    return Uri.parse('$baseUrl/rest/$endpoint').replace(queryParameters: q);
  }

  /// Chama um endpoint e devolve o objeto `subsonic-response`.
  Future<Map<String, dynamic>> get(String endpoint, [Map<String, dynamic> params = const {}]) async {
    final q = <String, dynamic>{..._baseParams};
    params.forEach((k, v) {
      if (v == null) return;
      q[k] = v is List ? v.map((e) => '$e').toList() : '$v';
    });
    Response<dynamic> res;
    try {
      res = await _dio.get(
        '$baseUrl/rest/$endpoint',
        queryParameters: q,
        options: Options(listFormat: ListFormat.multi, validateStatus: (_) => true),
      );
    } on DioException catch (e) {
      // Saiu de casa: o endereço local sumiu; tenta de novo pelo principal.
      if (_onLocal && _isUnreachable(e)) {
        _setLocal(false);
        return get(endpoint, params);
      }
      throw SubsonicException(_networkMessage(e));
    }
    if (res.statusCode == 404) {
      throw SubsonicException('Recurso não suportado pelo servidor ($endpoint)', code: 404);
    }
    final data = res.data;
    if (data is! Map || data['subsonic-response'] is! Map) {
      throw SubsonicException('Resposta inválida do servidor (HTTP ${res.statusCode})');
    }
    final body = Map<String, dynamic>.from(data['subsonic-response'] as Map);
    if (body['status'] != 'ok') {
      final err = body['error'] as Map?;
      throw SubsonicException(err?['message']?.toString() ?? 'Falha desconhecida',
          code: (err?['code'] as num?)?.toInt());
    }
    return body;
  }

  /// Extensões OpenSubsonic (endpoint público, sem autenticação).
  Future<Map<String, dynamic>?> openSubsonicExtensions() async {
    try {
      final res = await _dio.get('$baseUrl/rest/getOpenSubsonicExtensions',
          queryParameters: {'v': apiVersion, 'c': clientName, 'f': 'json'},
          options: Options(validateStatus: (_) => true));
      final data = res.data;
      if (data is Map && data['subsonic-response'] is Map) {
        return Map<String, dynamic>.from(data['subsonic-response'] as Map);
      }
    } on DioException {
      // Servidor Subsonic clássico: sem extensões.
    }
    return null;
  }

  static String _networkMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Tempo esgotado ao falar com o servidor';
      case DioExceptionType.connectionError:
        return 'Não foi possível conectar ao servidor';
      case DioExceptionType.badCertificate:
        return 'Certificado HTTPS inválido';
      default:
        return e.message ?? 'Erro de rede';
    }
  }
}
