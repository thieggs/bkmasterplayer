import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../core/diagnostics.dart';
import '../core/providers.dart';
import '../src/rust/api/engine.dart' as engine;
import 'network.dart';

/// Atualização pelo GitHub: ao abrir, compara a versão instalada com o último
/// release; se saiu outra, baixa o arquivo deste sistema, confere o SHA-256
/// que o GitHub publica de cada arquivo e instala do jeito que o sistema deixa.

const updateRepo = 'thieggs/bkmasterplayer';

/// Como este app foi instalado — decide qual arquivo do release serve e como
/// trocar a versão. `userFolder`: o `dev/install_linux.sh` (pasta do usuário,
/// sem sudo), que se atualiza com o conteúdo do .deb. `none`: build de
/// desenvolvimento ou iPhone, que só avisa.
enum InstallKind { apk, appImage, deb, userFolder, windowsSetup, none }

class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, required this.size, this.sha256});

  final String name;
  final String url;
  final int size;

  /// Hex; null em release antigo, de antes do GitHub publicar o resumo.
  final String? sha256;
}

class AppRelease {
  const AppRelease({required this.version, required this.notes, required this.page, required this.assets});

  /// Sem o "v" da tag (ex.: 1.3.0).
  final String version;
  final String notes;
  final String page;
  final List<ReleaseAsset> assets;

  factory AppRelease.fromGitHub(Map<String, dynamic> j) {
    final tag = (j['tag_name'] as String? ?? '').trim();
    return AppRelease(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      notes: j['body'] as String? ?? '',
      page: j['html_url'] as String? ?? 'https://github.com/$updateRepo/releases/latest',
      assets: [
        for (final a in (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>())
          ReleaseAsset(
            name: a['name'] as String,
            url: a['browser_download_url'] as String,
            size: (a['size'] as num?)?.toInt() ?? 0,
            sha256: switch (a['digest']) {
              final String d when d.startsWith('sha256:') => d.substring(7).toLowerCase(),
              _ => null,
            },
          ),
      ],
    );
  }
}

/// Compara versões "1.10.0" e "v1.9.2" número a número (ignora "+build" e
/// "-beta"). Negativo: `a` é mais velha.
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    v = v.trim();
    if (v.startsWith('v')) v = v.substring(1);
    v = v.split('+').first.split('-').first;
    return v.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  }

  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// O arquivo do release que serve para este jeito de instalar.
ReleaseAsset? assetFor(InstallKind kind, List<ReleaseAsset> assets) {
  bool Function(String) match = switch (kind) {
    InstallKind.apk => (n) => n.endsWith('_arm64.apk'),
    InstallKind.appImage => (n) => n.endsWith('-x86_64.AppImage'),
    InstallKind.deb || InstallKind.userFolder => (n) => n.endsWith('_amd64.deb'),
    InstallKind.windowsSetup => (n) => n.endsWith('-instalador.exe'),
    InstallKind.none => (_) => false,
  };
  for (final a in assets) {
    if (match(a.name)) return a;
  }
  return null;
}

/// Pasta onde o .deb instala (ver dev/build_deb.sh).
const _debDir = '/opt/bkmasterplayer';

/// Pasta do `dev/install_linux.sh`.
String get _userDir => '${Platform.environment['HOME']}/.local/share/player-musica';

InstallKind detectInstallKind() {
  if (Platform.isAndroid) return InstallKind.apk;
  if (Platform.isLinux) {
    if (Platform.environment['APPIMAGE']?.isNotEmpty ?? false) return InstallKind.appImage;
    if (Platform.resolvedExecutable.startsWith('$_debDir/')) return InstallKind.deb;
    if (Platform.resolvedExecutable.startsWith('$_userDir/') && File('/usr/bin/dpkg-deb').existsSync()) {
      return InstallKind.userFolder;
    }
  }
  if (Platform.isWindows) {
    // Instalado pelo Inno Setup: o desinstalador mora junto do programa.
    final dir = File(Platform.resolvedExecutable).parent.path;
    if (File(p.join(dir, 'unins000.exe')).existsSync()) return InstallKind.windowsSetup;
  }
  return InstallKind.none;
}

enum UpdateStatus { idle, checking, upToDate, available, downloading, ready, installing, failed }

class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.release,
    this.progress = 0,
    this.file,
    this.error,
    this.skipped = false,
    this.quiet = false,
  });

  final UpdateStatus status;
  final AppRelease? release;

  /// 0 a 1, durante o download.
  final double progress;

  /// Arquivo baixado e conferido.
  final String? file;
  final String? error;

  /// A pessoa pediu para pular esta versão: a procura automática não avisa.
  final bool skipped;

  /// Achada ao abrir e já baixando sozinha: o aviso só aparece quando estiver
  /// pronta para instalar.
  final bool quiet;

  UpdateState copyWith({UpdateStatus? status, double? progress, String? file, String? error}) => UpdateState(
    status: status ?? this.status,
    release: release,
    progress: progress ?? this.progress,
    file: file ?? this.file,
    error: error,
    skipped: skipped,
    quiet: quiet,
  );
}

class UpdateNotifier extends Notifier<UpdateState> {
  static const _skipKey = 'update.skip';
  static const _system = MethodChannel('bkplayer/system');

  final InstallKind kind = detectInstallKind();

  @override
  UpdateState build() => const UpdateState();

  /// Dá para trocar a versão daqui de dentro (senão, só o link do GitHub).
  bool get canInstall => kind != InstallKind.none && state.release != null && assetFor(kind, state.release!.assets) != null;

  /// A procura de quando o app abre: quieta se falhar, e já baixa se a
  /// pessoa deixou (fora dos dados móveis — o APK tem uns 25 MB).
  Future<void> checkOnLaunch() async {
    if (!ref.read(settingsProvider).updateCheck) return;
    await check(manual: false);
    if (state.status == UpdateStatus.available && state.quiet) await download();
  }

  Future<void> check({bool manual = true}) async {
    if (state.status case UpdateStatus.checking || UpdateStatus.downloading || UpdateStatus.installing) return;
    state = const UpdateState(status: UpdateStatus.checking);
    try {
      final res = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Accept': 'application/vnd.github+json'},
        ),
      ).get<Map<String, dynamic>>('https://api.github.com/repos/$updateRepo/releases/latest');
      final rel = AppRelease.fromGitHub(res.data!);
      final current = (await PackageInfo.fromPlatform()).version;
      if (rel.version.isEmpty || compareVersions(rel.version, current) <= 0) {
        state = UpdateState(status: UpdateStatus.upToDate, release: rel);
        return;
      }
      final skipped = !manual && ref.read(prefsProvider).getString(_skipKey) == rel.version;
      final quiet =
          !manual &&
          !skipped &&
          ref.read(settingsProvider).updateAutoDownload &&
          assetFor(kind, rel.assets) != null &&
          !ref.read(meteredProvider);
      state = UpdateState(status: UpdateStatus.available, release: rel, skipped: skipped, quiet: quiet);
    } catch (e) {
      AppLog.instance.add('aviso', 'procura de atualização: $e');
      state = manual ? UpdateState(status: UpdateStatus.failed, error: _short(e)) : const UpdateState();
    }
  }

  Future<void> download() async {
    final rel = state.release;
    final asset = rel == null ? null : assetFor(kind, rel.assets);
    if (asset == null || state.status == UpdateStatus.downloading) return;
    final dir = Directory(p.join(ref.read(supportDirProvider).path, 'updates'));
    final dest = File(p.join(dir.path, asset.name));
    state = state.copyWith(status: UpdateStatus.downloading, progress: 0);
    try {
      await dir.create(recursive: true);
      // Sobras de versões anteriores.
      await for (final f in dir.list()) {
        if (f.path != dest.path) await f.delete(recursive: true);
      }
      if (!await dest.exists() || !await _matches(dest, asset)) {
        final part = File('${dest.path}.part');
        await Dio().download(
          asset.url,
          part.path,
          onReceiveProgress: (got, total) {
            final all = total > 0 ? total : asset.size;
            if (all > 0) state = state.copyWith(progress: got / all);
          },
        );
        if (!await _matches(part, asset)) {
          await part.delete();
          throw const _UpdateError('o arquivo baixado não confere com o publicado no GitHub');
        }
        await part.rename(dest.path);
      }
      state = state.copyWith(status: UpdateStatus.ready, progress: 1, file: dest.path);
    } catch (e) {
      AppLog.instance.add('erro', 'download da atualização: $e');
      state = state.copyWith(status: UpdateStatus.failed, error: _short(e));
    }
  }

  /// Sem o resumo publicado não há como conferir: não instala.
  Future<bool> _matches(File f, ReleaseAsset a) async {
    if (a.sha256 == null) throw const _UpdateError('o release não publica o SHA-256 do arquivo');
    return (await sha256.bind(f.openRead()).first).toString() == a.sha256;
  }

  Future<void> install() async {
    final file = state.file;
    if (file == null) return;
    state = state.copyWith(status: UpdateStatus.installing);
    try {
      switch (kind) {
        case InstallKind.apk:
          // Abre o instalador do Android; a pessoa confirma lá.
          await _system.invokeMethod('installApk', file);
          state = state.copyWith(status: UpdateStatus.ready);
        case InstallKind.appImage:
          final target = Platform.environment['APPIMAGE']!;
          final tmp = '$target.new';
          await File(file).copy(tmp);
          await Process.run('chmod', ['755', tmp]);
          // Trocar o nome é atômico; o app aberto segue no arquivo antigo.
          await File(tmp).rename(target);
          await _relaunchAndQuit(target);
        case InstallKind.deb:
          final r = await Process.run('pkexec', ['apt-get', 'install', '-y', '--allow-downgrades', file]);
          // 126/127: a pessoa fechou a janela da senha.
          if (r.exitCode == 126 || r.exitCode == 127) {
            state = state.copyWith(status: UpdateStatus.ready);
            return;
          }
          if (r.exitCode != 0) throw _UpdateError('apt-get saiu com ${r.exitCode}: ${'${r.stderr}'.trim()}');
          await _relaunchAndQuit('$_debDir/player_musica');
        case InstallKind.userFolder:
          // Tira o programa de dentro do .deb (sem instalar, sem senha) e troca
          // a pasta de uma vez, como o install_linux.sh: o app aberto segue
          // com os arquivos antigos até fechar.
          final dest = _userDir;
          final tmp = Directory('$dest.extrai');
          if (await tmp.exists()) await tmp.delete(recursive: true);
          final r = await Process.run('dpkg-deb', ['-x', file, tmp.path]);
          if (r.exitCode != 0) throw _UpdateError('dpkg-deb saiu com ${r.exitCode}: ${'${r.stderr}'.trim()}');
          final novo = Directory('${tmp.path}$_debDir');
          if (!await File('${novo.path}/player_musica').exists()) throw const _UpdateError('o .deb veio sem o programa');
          for (final d in ['$dest.new', '$dest.old']) {
            if (await Directory(d).exists()) await Directory(d).delete(recursive: true);
          }
          await novo.rename('$dest.new');
          await Directory(dest).rename('$dest.old');
          await Directory('$dest.new').rename(dest);
          await Directory('$dest.old').delete(recursive: true);
          await tmp.delete(recursive: true);
          await _relaunchAndQuit('$dest/player_musica');
        case InstallKind.windowsSetup:
          // Instalado para todos (Arquivos de Programas) continua para todos,
          // senão a versão nova iria para outra pasta e ficariam duas.
          final exe = Platform.resolvedExecutable.toLowerCase();
          final allUsers = exe.contains(r'\program files');
          await Process.start(file, [
            '/VERYSILENT',
            '/SUPPRESSMSGBOXES',
            '/NORESTART',
            allUsers ? '/ALLUSERS' : '/CURRENTUSER',
            '/RELANCAR=1',
          ], mode: ProcessStartMode.detached);
          _quit();
        case InstallKind.none:
          break;
      }
    } catch (e) {
      AppLog.instance.add('erro', 'instalação da atualização: $e');
      state = state.copyWith(status: UpdateStatus.failed, error: _short(e));
    }
  }

  /// Abre a versão nova um instante depois de este processo sair.
  Future<void> _relaunchAndQuit(String exe) async {
    await Process.start('sh', ['-c', r'sleep 1; exec "$0"', exe], mode: ProcessStartMode.detached);
    _quit();
  }

  void _quit() {
    engine.playerStop();
    exit(0);
  }

  Future<void> skip() async {
    final v = state.release?.version;
    if (v != null) await ref.read(prefsProvider).setString(_skipKey, v);
    state = const UpdateState();
  }

  static String _short(Object e) => switch (e) {
    _UpdateError(:final message) => message,
    DioException(:final message, :final type) => message ?? type.name,
    _ => '$e',
  };
}

class _UpdateError implements Exception {
  const _UpdateError(this.message);
  final String message;
  @override
  String toString() => message;
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
