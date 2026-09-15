import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Registro do app para relatório de problemas: erros (do Flutter e das
/// tarefas em segundo plano) e os avisos que o app já escreve (debugPrint).
/// Tudo passa por [redactSecrets] antes de ir para a memória ou o disco:
/// senha, token, salt, chaves e o nome do usuário do sistema nunca ficam.
class AppLog {
  AppLog._();
  static final instance = AppLog._();

  static const maxLines = 600;
  static const maxFileBytes = 512 * 1024;

  final _lines = ListQueue<String>();
  final _pending = <String>[];
  File? _file;
  Timer? _flush;
  bool _handlersInstalled = false;

  /// Erros nesta sessão (do Flutter, de tarefas e avisos com "erro").
  int errors = 0;

  List<String> get lines => List.unmodifiable(_lines);

  /// Pasta do registro: `<suporte>/logs/app.log` (o anterior vira app.log.1).
  Future<void> init(Directory supportDir) async {
    try {
      final dir = Directory('${supportDir.path}/logs');
      await dir.create(recursive: true);
      final f = File('${dir.path}/app.log');
      if (await f.exists()) {
        if (await f.length() > maxFileBytes) {
          await f.rename('${dir.path}/app.log.1');
        } else {
          // O fim da sessão anterior entra no relatório (o problema pode ter sido lá).
          final old = (await f.readAsLines()).where((l) => l.isNotEmpty).toList();
          final tail = old.skip(old.length > 200 ? old.length - 200 : 0).toList();
          if (tail.isNotEmpty) {
            // Antes do que já foi registrado nesta sessão (ordem do relógio).
            final current = _lines.toList();
            _lines
              ..clear()
              ..addAll(['— sessão anterior —', ...tail, '— sessão atual —', ...current]);
            _trim();
          }
        }
      }
      _file = File('${dir.path}/app.log');
      _scheduleFlush();
    } catch (_) {
      // Sem disco: fica só na memória.
    }
  }

  void add(String level, String message) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    final clean = redactSecrets(message).trimRight();
    if (level == 'erro') errors++;
    for (final (i, part) in clean.split('\n').indexed) {
      final line = i == 0 ? '$stamp [$level] $part' : '    $part';
      _lines.add(line);
      _pending.add(line);
    }
    _trim();
    _scheduleFlush();
  }

  void _trim() {
    while (_lines.length > maxLines) {
      _lines.removeFirst();
    }
  }

  void _scheduleFlush() {
    if (_file == null || _pending.isEmpty || _flush != null) return;
    _flush = Timer(const Duration(seconds: 2), () {
      _flush = null;
      final chunk = '${_pending.join('\n')}\n';
      _pending.clear();
      try {
        final f = _file!;
        if (f.existsSync() && f.lengthSync() > maxFileBytes) f.renameSync('${f.path}.1');
        f.writeAsStringSync(chunk, mode: FileMode.append);
      } catch (_) {}
    });
  }

  Future<void> clear() async {
    _lines.clear();
    _pending.clear();
    errors = 0;
    try {
      await _file?.writeAsString('');
      final old = File('${_file?.path}.1');
      if (await old.exists()) await old.delete();
    } catch (_) {}
  }

  /// Liga as capturas: erros do Flutter, erros soltos de tarefas assíncronas e
  /// tudo o que o app manda para o debugPrint. Chame logo no começo do main().
  void installHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) add(message.toLowerCase().contains('erro') ? 'erro' : 'info', message);
      original(message, wrapWidth: wrapWidth);
    };
    final flutter = FlutterError.onError;
    FlutterError.onError = (details) {
      add('erro', '${details.exceptionAsString()}\n${shortStack(details.stack)}');
      flutter?.call(details);
    };
    final platform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      add('erro', '$error\n${shortStack(stack)}');
      return platform?.call(error, stack) ?? true;
    };
  }
}

/// As primeiras linhas da pilha (o bastante para achar o problema).
String shortStack(StackTrace? stack, [int frames = 12]) =>
    (stack?.toString() ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(frames).join('\n');

final _secretParams = RegExp(r'((?:^|[?&;\s])(?:t|s|u|p|k|h|n|apiKey|token|salt|password|passwd|key|jwt|auth)=)[^&\s"<>]+', caseSensitive: false);
final _secretJson = RegExp(r'''(["']?(?:password|passwd|token|salt|apiKey|connectKey|jwt|secret|pass|k|username|user)["']?\s*[:=]\s*)(["'])(?:(?!\2).)*\2''', caseSensitive: false);
final _bearer = RegExp(r'(Bearer|Basic)\s+[A-Za-z0-9+/._=-]+');
final _longHex = RegExp(r'\b[0-9a-fA-F]{24,}\b');
final _home = RegExp(r'/(home|Users)/[^/\s]+');
final _androidUser = RegExp(r'/data/user/\d+/[^/\s]+');

/// Tira senhas, tokens, salts, chaves e o nome do usuário do sistema de um
/// texto de registro.
String redactSecrets(String s) => s
    .replaceAllMapped(_secretParams, (m) => '${m[1]}…')
    .replaceAllMapped(_secretJson, (m) => '${m[1]}${m[2]}…${m[2]}')
    .replaceAllMapped(_bearer, (m) => '${m[1]} …')
    .replaceAll(_longHex, '…')
    .replaceAll(_home, '~')
    .replaceAll(_androidUser, '<app>');

/// Relatório para mandar junto com um bug: aparelho, versão, ajustes (sem nada
/// que identifique a conta ou o servidor) e o registro, já limpo.
String diagnosticReport({required Map<String, String> info, List<String>? log}) {
  final b = StringBuffer()
    ..writeln('BKmasterplayer — relatório de diagnóstico')
    ..writeln('Gerado em: ${DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ')}');
  for (final e in info.entries) {
    b.writeln('${e.key}: ${redactSecrets(e.value)}');
  }
  final lines = log ?? AppLog.instance.lines;
  b
    ..writeln('Erros nesta sessão: ${AppLog.instance.errors}')
    ..writeln()
    ..writeln('--- registro (${lines.length} linhas; senhas, tokens e chaves apagados) ---');
  for (final l in lines) {
    b.writeln(l);
  }
  return b.toString();
}
