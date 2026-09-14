import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'subsonic/subsonic_client.dart';

/// Uma conta de servidor. As credenciais (token+salt ou API key) ficam no
/// chaveiro do sistema; se ele não existir, caem nas preferências.
class ServerAccount {
  const ServerAccount({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.username,
    this.localUrl,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String username;

  /// Endereço na rede de casa (opcional): usado no lugar de [baseUrl] quando
  /// responde, por ser mais rápido.
  final String? localUrl;

  ServerAccount withLocalUrl(String? url) =>
      ServerAccount(id: id, name: name, baseUrl: baseUrl, username: username, localUrl: url);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'username': username,
        if (localUrl != null) 'localUrl': localUrl,
      };

  factory ServerAccount.fromJson(Map<String, dynamic> j) => ServerAccount(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        baseUrl: j['baseUrl'] as String,
        username: j['username'] as String? ?? '',
        localUrl: j['localUrl'] as String?,
      );
}

class AccountStore {
  AccountStore(this._prefs);

  final SharedPreferences _prefs;
  static const _secure = FlutterSecureStorage();
  static const _kAccounts = 'accounts';
  static const _kActive = 'activeAccount';

  List<ServerAccount> list() {
    final raw = _prefs.getString(_kAccounts);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => ServerAccount.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  String? get activeId => _prefs.getString(_kActive);

  ServerAccount? get active {
    final all = list();
    final id = activeId;
    return all.where((a) => a.id == id).firstOrNull ?? all.firstOrNull;
  }

  Future<void> setActive(String id) => _prefs.setString(_kActive, id);

  Future<void> save(ServerAccount account, SubsonicAuth auth) async {
    final all = list()..removeWhere((a) => a.id == account.id);
    all.add(account);
    await _prefs.setString(_kAccounts, jsonEncode(all.map((a) => a.toJson()).toList()));
    await _writeSecret(account.id, jsonEncode(auth.toJson()));
    await setActive(account.id);
  }

  /// Conta sem servidor (músicas do aparelho): sem credenciais.
  Future<void> saveLocal(ServerAccount account) async {
    final all = list()..removeWhere((a) => a.id == account.id);
    all.add(account);
    await _prefs.setString(_kAccounts, jsonEncode(all.map((a) => a.toJson()).toList()));
    await setActive(account.id);
  }

  /// Atualiza os dados da conta (sem mexer nas credenciais).
  Future<void> update(ServerAccount account) async {
    final all = list().map((a) => a.id == account.id ? account : a).toList();
    await _prefs.setString(_kAccounts, jsonEncode(all.map((a) => a.toJson()).toList()));
  }

  Future<void> remove(String id) async {
    final all = list()..removeWhere((a) => a.id == id);
    await _prefs.setString(_kAccounts, jsonEncode(all.map((a) => a.toJson()).toList()));
    try {
      await _secure.delete(key: 'auth:$id');
    } catch (_) {}
    await _prefs.remove('auth:$id');
    if (activeId == id) await _prefs.remove(_kActive);
  }

  Future<SubsonicAuth?> auth(String id) async {
    String? raw;
    try {
      raw = await _secure.read(key: 'auth:$id');
    } catch (e) {
      debugPrint('chaveiro indisponível: $e');
    }
    raw ??= _prefs.getString('auth:$id');
    if (raw == null) return null;
    return SubsonicAuth.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  Future<void> _writeSecret(String id, String value) async {
    try {
      await _secure.write(key: 'auth:$id', value: value);
      await _prefs.remove('auth:$id');
    } catch (e) {
      // Sem chaveiro (ex.: sessão sem gnome-keyring/kwallet): guarda o token
      // (nunca a senha) nas preferências.
      debugPrint('chaveiro indisponível, usando preferências: $e');
      await _prefs.setString('auth:$id', value);
    }
  }
}
