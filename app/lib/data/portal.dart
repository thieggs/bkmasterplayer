import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../src/rust/api/portal.dart' as rust;

export '../src/rust/api/portal.dart' show PortalNotice;

/// Portal: um endereço fixo que diz onde o servidor de música está agora.
///
/// Servidor de casa atrás de túnel grátis ganha um endereço novo a cada
/// reinício. Em vez de a pessoa ter que reconfigurar o app toda vez, ela
/// guarda o endereço do portal — que nunca muda — e o app pergunta a ele
/// qual é o endereço de hoje.
///
/// O anúncio vem assinado. Na primeira vez o app fixa a chave que assinou
/// (como o SSH faz com a impressão digital do servidor) e daí em diante
/// recusa qualquer anúncio de outra chave. Sem isso, quem conseguisse
/// escrever no anúncio mandaria o app — e a senha de quem o usa — para o
/// servidor que quisesse. A conferência mora no Rust (`crate::portal`).
class Portal {
  /// Tempo curto: o portal é um arquivinho, e o app está esperando por ele
  /// para poder tocar música.
  static const _timeout = Duration(seconds: 8);

  /// De quanto em quanto tempo, no máximo, vale perguntar de novo.
  static const minBetweenLookups = Duration(seconds: 20);

  /// Baixa e confere o anúncio de [portalUrl].
  ///
  /// [pinnedKey] é a chave fixada na primeira vez (`null` quando ainda não
  /// há nenhuma). Lança [PortalException] quando não dá certo.
  static Future<rust.PortalNotice> fetch(String portalUrl, {String? pinnedKey, Dio? dio}) async {
    final url = '${normalize(portalUrl)}${rust.portalNoticePath()}';
    final client = dio ??
        Dio(BaseOptions(
          connectTimeout: _timeout,
          receiveTimeout: _timeout,
          responseType: ResponseType.bytes,
          // O anúncio é pequeno; nada de baixar um arquivo enorme de um
          // endereço que ainda não provou ser um portal.
          maxRedirects: 2,
        ));
    Response<dynamic> res;
    try {
      res = await client.get<List<int>>(url, options: Options(validateStatus: (_) => true, responseType: ResponseType.bytes));
    } on DioException catch (e) {
      throw PortalException(PortalProblem.unreachable, _network(e));
    }
    if (res.statusCode != 200) {
      throw PortalException(PortalProblem.notAPortal, 'esse endereço não respondeu com um anúncio (HTTP ${res.statusCode})');
    }
    final body = res.data;
    if (body is! List<int>) {
      throw PortalException(PortalProblem.notAPortal, 'esse endereço não é um portal do BKmasterplayer');
    }
    if (body.length > rust.portalMaxBytes()) {
      throw PortalException(PortalProblem.notAPortal, 'o anúncio veio grande demais');
    }
    try {
      return rust.portalRead(raw: Uint8List.fromList(body), pinnedKey: pinnedKey ?? '');
    } catch (e) {
      final msg = _reason(e);
      // A chave trocar é diferente de o anúncio estar torto: pode ser o dono
      // tendo criado outra chave, ou alguém no meio do caminho. Nos dois
      // casos a pessoa precisa decidir, então nunca passa batido.
      final problem = msg.contains('outra chave') ? PortalProblem.keyChanged : PortalProblem.badNotice;
      throw PortalException(problem, msg);
    }
  }

  /// Procura um portal em [url] sem reclamar se não houver um.
  ///
  /// É o que a tela de entrar usa: a pessoa cola um endereço e o app
  /// descobre sozinho se é um portal ou um Navidrome comum. Só a troca de
  /// chave escapa, porque essa a pessoa precisa ver.
  static Future<rust.PortalNotice?> probe(String url, {String? pinnedKey, Dio? dio}) async {
    try {
      return await fetch(url, pinnedKey: pinnedKey, dio: dio);
    } on PortalException catch (e) {
      if (e.problem == PortalProblem.keyChanged) rethrow;
      debugPrint('portal: $url não é um portal (${e.message})');
      return null;
    }
  }

  /// Deixa o endereço do portal no formato guardado na conta.
  static String normalize(String url) => _trim(url);

  static String _trim(String url) {
    var u = url.trim();
    if (!u.contains('://')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  static String _reason(Object e) {
    final s = e is PortalException ? e.message : '$e';
    // O erro do Rust chega embrulhado; o recado em português está dentro.
    final m = RegExp(r'[:(]\s*([^():]*(?:chave|assinatura|anúncio|endereço|portal)[^()]*)').firstMatch(s);
    return (m?.group(1) ?? s).trim();
  }

  static String _network(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout =>
          'o portal demorou demais para responder',
        DioExceptionType.connectionError => 'não deu para falar com o portal',
        _ => 'não deu para falar com o portal',
      };
}

enum PortalProblem {
  /// Não deu para chegar no endereço do portal.
  unreachable,

  /// Respondeu, mas não é um portal (provavelmente é um Navidrome comum).
  notAPortal,

  /// É um anúncio, mas está vencido, torto ou mal assinado.
  badNotice,

  /// Está bem assinado, mas por uma chave diferente da que o app fixou.
  /// O app nunca segue esse anúncio sozinho.
  keyChanged,
}

class PortalException implements Exception {
  PortalException(this.problem, this.message);

  final PortalProblem problem;
  final String message;

  @override
  String toString() => message;
}
