import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'ui_prefs.dart';

/// Pasta das imagens de fundo dos temas.
String themeImagesDir(String supportDir) => p.join(supportDir, 'themes', 'images');

/// Imagem de fundo aceita (tamanho máximo, ao escolher ou importar).
const maxThemeImageBytes = 12 * 1024 * 1024;

/// Arquivo de tema/backup aceito (as imagens vão dentro, em base64).
const maxThemeFileBytes = 40 * 1024 * 1024;

/// Copia uma imagem escolhida para a pasta dos temas e devolve o nome (o tema
/// guarda só o nome, nunca um caminho). Mesmo conteúdo = mesmo nome.
Future<String> importThemeImage(String supportDir, List<int> bytes, {String ext = '.jpg'}) async {
  if (bytes.isEmpty || bytes.length > maxThemeImageBytes) throw const FormatException('imagem inválida');
  final clean = ext.toLowerCase().replaceAll(RegExp(r'[^a-z.]'), '');
  final name = '${sha1.convert(bytes).toString().substring(0, 20)}${RegExp(r'^\.[a-z]{2,4}$').hasMatch(clean) ? clean : '.img'}';
  final out = File(p.join(themeImagesDir(supportDir), name));
  await out.parent.create(recursive: true);
  if (!await out.exists()) await out.writeAsBytes(bytes, flush: true);
  return name;
}

/// Um tema da galeria: pronto (fixo, nome traduzido pelo [id]) ou do usuário.
class BkTheme {
  const BkTheme({required this.id, required this.name, required this.theme, this.builtIn = false});

  final String id;
  final String name;

  /// Aparência + estrutura ([UiPrefs.themeJson]).
  final Map<String, dynamic> theme;
  final bool builtIn;

  UiPrefs get prefs => const UiPrefs().withTheme(theme);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'theme': theme};
}

/// Temas prontos. Só o que muda em relação ao original; o resto vem do padrão.
const builtInThemes = <BkTheme>[
  BkTheme(id: 'builtin:original', name: 'BKmasterplayer', builtIn: true, theme: {}),
  BkTheme(id: 'builtin:amoled', name: 'AMOLED', builtIn: true, theme: {'amoled': true}),
  BkTheme(id: 'builtin:vinyl', name: 'Vinil', builtIn: true, theme: {
    'titleFont': 'playfair',
    'bodyFont': 'nunito',
    'colorSource': 'accent',
    'seed': 0xFFB5651D,
    'coverShape': 'circle',
    'nowPlayingLayout': 'vinyl',
    'background': 'cover',
    'backgroundDim': 0.55,
    'radius': 20.0,
  }),
  BkTheme(id: 'builtin:neon', name: 'Neon', builtIn: true, theme: {
    'bodyFont': 'spaceGrotesk',
    'titleFont': 'spaceGrotesk',
    'variant': 'vibrant',
    'colorSource': 'accent',
    'seed': 0xFFFF2E88,
    'radius': 4.0,
    'background': 'gradient',
    'backgroundDim': 0.35,
    'playerStyle': 'floating',
    'navLabels': 'selected',
  }),
  BkTheme(id: 'builtin:paper', name: 'Papel', builtIn: true, theme: {
    'themeMode': 'light',
    'variant': 'neutral',
    'colorSource': 'accent',
    'seed': 0xFF8D6E63,
    'titleFont': 'playfair',
    'coverShape': 'square',
    'radius': 4.0,
    'cardStyle': 'outlined',
    'buttonStyle': 'outlined',
  }),
  BkTheme(id: 'builtin:terminal', name: 'Terminal', builtIn: true, theme: {
    'amoled': true,
    'colorSource': 'accent',
    'variant': 'fidelity',
    'seed': 0xFF00E676,
    'colors': {'primary': 0xFF00E676, 'text': 0xFFB9F6CA},
    'bodyFont': 'jetbrainsMono',
    'titleFont': 'jetbrainsMono',
    'radius': 0.0,
    'coverShape': 'square',
    'density': 'compact',
    'nowPlayingLayout': 'minimal',
    'navLabels': 'none',
    'transitions': 'none',
    'animations': 'off',
  }),
  BkTheme(id: 'builtin:contrast', name: 'Alto contraste', builtIn: true, theme: {
    'colorSource': 'accent',
    'seed': 0xFFFFD600,
    'variant': 'fidelity',
    'contrast': 1.0,
    'uiScale': 1.15,
    'density': 'comfortable',
    'radius': 8.0,
    'nowPlayingBlur': 0.2,
  }),
  BkTheme(id: 'builtin:auto', name: 'Automático', builtIn: true, theme: {'themeMode': 'system', 'variant': 'content'}),
];

/// Um backup automático salvo no aparelho.
class AutoBackup {
  const AutoBackup(this.path, this.date);
  final String path;
  final DateTime date;
}

/// Galeria de temas: os prontos e os do usuário (em `themes/themes.json`),
/// arquivos de tema e de backup (com as imagens dentro) e backups
/// automáticos (os 10 últimos, em `themes/backups/`).
class ThemeLibrary {
  ThemeLibrary(this.supportDir);

  final String supportDir;
  List<BkTheme> _user = [];

  static const keepAutoBackups = 10;

  String get _dir => p.join(supportDir, 'themes');
  File get _file => File(p.join(_dir, 'themes.json'));
  Directory get _backups => Directory(p.join(_dir, 'backups'));

  List<BkTheme> get userThemes => List.unmodifiable(_user);
  List<BkTheme> get all => [...builtInThemes, ..._user];

  BkTheme? byId(String? id) => id == null ? null : all.where((t) => t.id == id).firstOrNull;

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString());
      _user = [for (final t in (j is Map ? j['themes'] : null) as List? ?? const []) ?_parse(t, keepId: true)];
    } catch (_) {
      _user = [];
    }
  }

  Future<void> _save() async {
    await Directory(_dir).create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode({'version': 1, 'themes': [for (final t in _user) t.toJson()]}), flush: true);
    await tmp.rename(_file.path);
  }

  /// Tema válido a partir de um JSON qualquer (nome curto, campos validados).
  BkTheme? _parse(Object? t, {bool keepId = false}) {
    if (t is! Map || t['theme'] is! Map) return null;
    final theme = const UiPrefs().withTheme(Map<String, dynamic>.from(t['theme'] as Map)).themeJson();
    final id = keepId && t['id'] is String && (t['id'] as String).startsWith('user:') ? t['id'] as String : _newId();
    return BkTheme(id: id, name: _cleanName(t['name']), theme: theme);
  }

  static String _cleanName(Object? n) {
    final s = (n is String ? n : '').replaceAll(RegExp(r'[\x00-\x1F]'), ' ').trim();
    return s.isEmpty ? 'Tema' : (s.length > 40 ? s.substring(0, 40) : s);
  }

  int _seq = 0;
  String _newId() => 'user:${DateTime.now().microsecondsSinceEpoch}${_seq++}';

  /// Nome livre entre os temas (acrescenta " (2)", " (3)"…).
  String _unique(String name) {
    final names = all.map((t) => t.name).toSet();
    if (!names.contains(name)) return name;
    for (var i = 2;; i++) {
      final n = '$name ($i)';
      if (!names.contains(n)) return n;
    }
  }

  Future<BkTheme> add(String name, Map<String, dynamic> theme) async {
    final t = BkTheme(id: _newId(), name: _unique(_cleanName(name)), theme: const UiPrefs().withTheme(theme).themeJson());
    _user = [..._user, t];
    await _save();
    return t;
  }

  /// Salva por cima um tema do usuário (os prontos não mudam).
  Future<void> overwrite(String id, Map<String, dynamic> theme) async {
    _user = [for (final t in _user) t.id == id ? BkTheme(id: t.id, name: t.name, theme: const UiPrefs().withTheme(theme).themeJson()) : t];
    await _save();
  }

  Future<void> rename(String id, String name) async {
    _user = [for (final t in _user) t.id == id ? BkTheme(id: t.id, name: _cleanName(name), theme: t.theme) : t];
    await _save();
  }

  Future<void> delete(String id) async {
    _user = _user.where((t) => t.id != id).toList();
    await _save();
  }

  Future<BkTheme> duplicate(BkTheme t, String copyName) => add(copyName, t.theme);

  // ---- Arquivos ----

  Future<Map<String, String>> _images(Iterable<Map<String, dynamic>> themes) async {
    final out = <String, String>{};
    for (final t in themes) {
      final name = t['backgroundImage'];
      if (name is! String || out.containsKey(name)) continue;
      final f = File(p.join(themeImagesDir(supportDir), name));
      if (await f.exists()) out[name] = base64Encode(await f.readAsBytes());
    }
    return out;
  }

  /// Arquivo de um tema (`.bktheme.json`), com a imagem de fundo dentro.
  Future<String> exportTheme(BkTheme t) async => const JsonEncoder.withIndent(' ').convert({
        'app': 'bkplayer',
        'type': 'theme',
        'version': 1,
        'name': t.name,
        'theme': t.theme,
        'images': await _images([t.theme]),
      });

  /// Backup completo: a aparência atual e todos os temas do usuário.
  Future<String> exportBackup(UiPrefs current) async {
    final themes = [for (final t in _user) t.toJson()];
    return const JsonEncoder.withIndent(' ').convert({
      'app': 'bkplayer',
      'type': 'backup',
      'version': 1,
      'created': DateTime.now().toIso8601String(),
      'current': current.themeJson(),
      'currentId': current.themeId,
      'themes': themes,
      'images': await _images([current.themeJson(), for (final t in _user) t.theme]),
    });
  }

  /// Lê um arquivo de tema ou de backup: valida, grava as imagens (com nome
  /// pelo conteúdo) e acerta as referências a elas.
  Future<(Map<String, dynamic>, Map<String, String>)> _read(String text) async {
    if (text.length > maxThemeFileBytes) throw const FormatException('arquivo grande demais');
    final j = jsonDecode(text);
    if (j is! Map || j['app'] != 'bkplayer') throw const FormatException('não é um arquivo do BKmasterplayer');
    final renamed = <String, String>{};
    final images = j['images'];
    if (images is Map) {
      for (final e in images.entries) {
        if (e.key is! String || e.value is! String) continue;
        try {
          final bytes = base64Decode(e.value as String);
          renamed[e.key as String] = await importThemeImage(supportDir, bytes, ext: p.extension(e.key as String));
        } catch (_) {}
      }
    }
    return (Map<String, dynamic>.from(j), renamed);
  }

  Map<String, dynamic> _fixImage(Map<String, dynamic> theme, Map<String, String> renamed) {
    final name = theme['backgroundImage'];
    return {...theme, 'backgroundImage': name is String ? renamed[name] : null};
  }

  /// Importa um arquivo de tema; ele entra nos temas do usuário.
  Future<BkTheme> importTheme(String text) async {
    final (j, renamed) = await _read(text);
    if (j['type'] != 'theme' || j['theme'] is! Map) throw const FormatException('não é um tema');
    return add(_cleanName(j['name']), _fixImage(Map<String, dynamic>.from(j['theme'] as Map), renamed));
  }

  /// Restaura um backup: troca os temas do usuário e devolve a aparência que
  /// estava em uso (tema + id) para aplicar.
  Future<(Map<String, dynamic>, String?)> restoreBackup(String text) async {
    final (j, renamed) = await _read(text);
    if (j['type'] != 'backup' || j['current'] is! Map) throw const FormatException('não é um backup');
    final themes = <BkTheme>[];
    for (final t in (j['themes'] as List? ?? const [])) {
      if (t is! Map || t['theme'] is! Map) continue;
      final parsed = _parse({...t, 'theme': _fixImage(Map<String, dynamic>.from(t['theme'] as Map), renamed)}, keepId: true);
      if (parsed != null) themes.add(parsed);
    }
    _user = themes;
    await _save();
    final current = const UiPrefs().withTheme(_fixImage(Map<String, dynamic>.from(j['current'] as Map), renamed)).themeJson();
    final id = j['currentId'] is String && byId(j['currentId'] as String) != null ? j['currentId'] as String : null;
    return (current, id);
  }

  // ---- Backups automáticos ----

  /// Guarda o estado atual antes de uma troca grande (aplicar outro tema por
  /// cima de mudanças não salvas, importar, restaurar, voltar ao original).
  Future<void> autoBackup(UiPrefs current, {DateTime? now}) async {
    await _backups.create(recursive: true);
    final t = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}-${t.millisecond}';
    await File(p.join(_backups.path, 'auto-$stamp.bkbackup.json')).writeAsString(await exportBackup(current), flush: true);
    final all = await autoBackups();
    for (final old in all.skip(keepAutoBackups)) {
      try {
        await File(old.path).delete();
      } catch (_) {}
    }
  }

  /// Backups automáticos, do mais novo para o mais velho.
  Future<List<AutoBackup>> autoBackups() async {
    if (!await _backups.exists()) return const [];
    final out = <AutoBackup>[];
    await for (final f in _backups.list()) {
      if (f is! File || !f.path.endsWith('.bkbackup.json')) continue;
      out.add(AutoBackup(f.path, (await f.stat()).modified));
    }
    out.sort((a, b) => b.path.compareTo(a.path));
    return out;
  }
}
