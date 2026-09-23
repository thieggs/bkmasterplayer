import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../data/portal.dart' show PortalException;
import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../../src/rust/api/engine.dart' as engine;
import '../actions.dart';
import 'settings/common.dart' show askText;

final deviceProfileProvider = FutureProvider.autoDispose<engine.DeviceProfile>((ref) => engine.playerDeviceProfile());

/// Seção "AutoMix" das configurações: tudo ajustável, padrões no melhor jeito.
class AutomixSettingsSection extends ConsumerWidget {
  const AutomixSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;
    final on = s.automixEnabled;

    Widget slider({
      required String title,
      required String value,
      required double current,
      required double min,
      required double max,
      int? divisions,
      required ValueChanged<double> onChanged,
      String? hint,
    }) =>
        ListTile(
          enabled: on,
          leading: const SizedBox(),
          title: Row(children: [Expanded(child: Text(title)), Text(value, style: theme.textTheme.labelLarge)]),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Slider(value: current.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: on ? onChanged : null),
              if (hint != null) Text(hint, style: theme.textTheme.bodySmall),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome),
          title: Text(l10n.automixEnable),
          subtitle: Text(l10n.automixEnableHint),
          value: on,
          onChanged: (v) => set((x) => x.copyWith(automixEnabled: v)),
        ),
        ListTile(
          enabled: on,
          leading: const SizedBox(),
          title: Text(l10n.automixStyle),
          trailing: DropdownButton<MixStyleSetting>(
            value: s.automixStyle,
            underline: const SizedBox(),
            onChanged: on ? (v) => v == null ? null : set((x) => x.copyWith(automixStyle: v)) : null,
            items: [
              DropdownMenuItem(value: MixStyleSetting.auto, child: Text(l10n.mixAuto)),
              DropdownMenuItem(value: MixStyleSetting.bassSwap, child: Text(l10n.mixBassSwap)),
              DropdownMenuItem(value: MixStyleSetting.blend, child: Text(l10n.mixBlend)),
              DropdownMenuItem(value: MixStyleSetting.filter, child: Text(l10n.mixFilter)),
              DropdownMenuItem(value: MixStyleSetting.echo, child: Text(l10n.mixEcho)),
              DropdownMenuItem(value: MixStyleSetting.cut, child: Text(l10n.mixCut)),
            ],
          ),
        ),
        Builder(builder: (context) {
          final picker = SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4')),
              ButtonSegment(value: 8, label: Text('8')),
              ButtonSegment(value: 16, label: Text('16')),
              ButtonSegment(value: 32, label: Text('32')),
            ],
            selected: {s.automixBars},
            onSelectionChanged: on ? (v) => set((x) => x.copyWith(automixBars: v.first)) : null,
          );
          // No celular não cabe ao lado do título: vai para baixo.
          final narrow = MediaQuery.sizeOf(context).width < 600;
          return ListTile(
            enabled: on,
            leading: const SizedBox(),
            title: Text(l10n.automixBars),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.automixBarsHint, style: theme.textTheme.bodySmall),
                if (narrow) Padding(padding: const EdgeInsets.only(top: 8), child: picker),
              ],
            ),
            trailing: narrow ? null : picker,
          );
        }),
        slider(
          title: l10n.automixMaxSeconds,
          value: l10n.seconds(s.automixMaxSeconds.round()),
          current: s.automixMaxSeconds,
          min: 5,
          max: 90,
          divisions: 17,
          onChanged: (v) => set((x) => x.copyWith(automixMaxSeconds: v.roundToDouble())),
        ),
        slider(
          title: l10n.automixUnclear,
          value: l10n.seconds(s.automixUnclearSeconds.round()),
          current: s.automixUnclearSeconds,
          min: 1,
          max: 30,
          divisions: 29,
          hint: l10n.automixUnclearHint,
          onChanged: (v) => set((x) => x.copyWith(automixUnclearSeconds: v.roundToDouble())),
        ),
        slider(
          title: l10n.automixMaxTempo,
          value: '±${s.automixMaxTempo.toStringAsFixed(0)}%',
          current: s.automixMaxTempo,
          min: 0,
          max: 16,
          divisions: 16,
          hint: l10n.automixMaxTempoHint,
          onChanged: (v) => set((x) => x.copyWith(automixMaxTempo: v.roundToDouble())),
        ),
        slider(
          title: l10n.automixRamp,
          value: s.automixRampBars == 0 ? l10n.automixRampKeep : '${s.automixRampBars}',
          current: s.automixRampBars.toDouble(),
          min: 0,
          max: 32,
          divisions: 8,
          hint: l10n.automixRampHint,
          onChanged: (v) => set((x) => x.copyWith(automixRampBars: v.round())),
        ),
        SwitchListTile(
          secondary: const SizedBox(),
          title: Text(l10n.automixHarmonic),
          subtitle: Text(l10n.automixHarmonicHint),
          value: s.automixHarmonic,
          onChanged: on ? (v) => set((x) => x.copyWith(automixHarmonic: v)) : null,
        ),
        SwitchListTile(
          secondary: const SizedBox(),
          title: Text(l10n.automixTrim),
          value: s.automixTrimSilence,
          onChanged: on ? (v) => set((x) => x.copyWith(automixTrimSilence: v)) : null,
        ),
        SwitchListTile(
          secondary: const SizedBox(),
          title: Text(l10n.automixAlbums),
          subtitle: Text(l10n.automixAlbumsHint),
          value: s.automixRespectAlbums,
          onChanged: on ? (v) => set((x) => x.copyWith(automixRespectAlbums: v)) : null,
        ),
        SwitchListTile(
          secondary: const SizedBox(),
          title: Text(l10n.automixPreAnalyze),
          subtitle: Text(l10n.automixPreAnalyzeHint),
          value: s.preAnalyze,
          onChanged: on ? (v) => set((x) => x.copyWith(preAnalyze: v)) : null,
        ),
        const _ServerTile(),
        const _ModelTile(),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(l10n.automixDefaults),
              onPressed: on
                  ? () {
                      const d = AppSettings();
                      set((x) => x.copyWith(
                            automixStyle: d.automixStyle,
                            automixBars: d.automixBars,
                            automixMaxSeconds: d.automixMaxSeconds,
                            automixUnclearSeconds: d.automixUnclearSeconds,
                            automixMaxTempo: d.automixMaxTempo,
                            automixRampBars: d.automixRampBars,
                            automixHarmonic: d.automixHarmonic,
                            automixTrimSilence: d.automixTrimSilence,
                            automixRespectAlbums: d.automixRespectAlbums,
                            preAnalyze: d.preAnalyze,
                            analysisModel: d.analysisModel,
                          ));
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModelTile extends ConsumerStatefulWidget {
  const _ModelTile();

  @override
  ConsumerState<_ModelTile> createState() => _ModelTileState();
}

class _ModelTileState extends ConsumerState<_ModelTile> {
  bool _downloading = false;
  double _progress = 0;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    final l10n = context.l10n;
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    _poll = Timer.periodic(const Duration(milliseconds: 300), (_) {
      setState(() => _progress = engine.playerModelDownloadProgress() / 1000);
    });
    try {
      await engine.playerDownloadFullModel();
      final s = ref.read(settingsProvider);
      if (s.analysisModel == AnalysisModelSetting.small) {
        ref.read(settingsProvider.notifier).update((x) => x.copyWith(analysisModel: AnalysisModelSetting.full));
      }
      if (mounted) showSnack(context, l10n.modelDownloaded);
    } catch (e) {
      if (mounted) showSnack(context, '${l10n.modelDownloadFailed}: $e');
    } finally {
      _poll?.cancel();
      ref.invalidate(deviceProfileProvider);
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final profile = ref.watch(deviceProfileProvider).value;
    final on = s.automixEnabled;
    final recommended = profile?.recommendedModel == 'full' ? l10n.modelFull : l10n.modelSmall;
    return ListTile(
      enabled: on,
      leading: const Icon(Icons.memory),
      title: Text(l10n.analysisModel),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          // Encolhe um pouco se não couber (celular, textos em português).
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SegmentedButton<AnalysisModelSetting>(
            segments: [
              ButtonSegment(value: AnalysisModelSetting.auto, label: Text(l10n.modelAuto)),
              ButtonSegment(value: AnalysisModelSetting.small, label: Text(l10n.modelSmall)),
              ButtonSegment(
                value: AnalysisModelSetting.full,
                label: Text(l10n.modelFull),
                enabled: profile?.fullModelDownloaded ?? false,
              ),
            ],
            selected: {s.analysisModel},
            onSelectionChanged: on ? (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(analysisModel: v.first)) : null,
            ),
          ),
          const SizedBox(height: 6),
          if (profile != null)
            Text(
              l10n.modelDeviceInfo(profile.cores, profile.avx2 ? 'AVX2' : (Platform.isAndroid || Platform.isIOS ? 'ARM' : l10n.noAvx2), recommended,
                  profile.activeModel == 'full' ? l10n.modelFull : l10n.modelSmall),
              style: theme.textTheme.bodySmall,
            ),
          Text(l10n.modelHint, style: theme.textTheme.bodySmall),
          if (profile != null && !profile.fullModelDownloaded) ...[
            const SizedBox(height: 6),
            if (_downloading)
              LinearProgressIndicator(value: _progress > 0 ? _progress : null)
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: Text(l10n.downloadFullModel),
                onPressed: on ? _download : null,
              ),
          ],
        ],
      ),
    );
  }
}

/// Servidor de análise (BK Analyzer): endereço, teste da conexão e o painel.
class _ServerTile extends ConsumerStatefulWidget {
  const _ServerTile();

  @override
  ConsumerState<_ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends ConsumerState<_ServerTile> {
  String? _status;
  bool _error = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final server = ref.read(settingsProvider).analysisServer;
    if (server != null) WidgetsBinding.instance.addPostFrameCallback((_) => _test(server));
  }

  static String _base(String url) {
    var u = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (u.isNotEmpty && !u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    return u;
  }

  Future<void> _test(String server, {bool retried = false}) async {
    final l10n = context.l10n;
    final number = NumberFormat.decimalPattern(Localizations.localeOf(context).toString());
    setState(() {
      _testing = true;
      _status = null;
    });
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 8),
      validateStatus: (_) => true,
    ));
    String msg;
    var error = true;
    var unreachable = false;
    try {
      final hello = await dio.get<dynamic>('${_base(server)}/api/hello');
      final uri = ref.read(musicProvider).analyzerUri(server, '/api/summary');
      if (hello.statusCode != 200) {
        // Túnel caído devolve a página de erro da Cloudflare (530): isso é
        // "sem resposta", não "é outro programa".
        msg = l10n.analysisServerUnreachable;
        unreachable = true;
      } else if (hello.data is! Map || hello.data['app'] != 'bk-analyzer' || uri == null) {
        msg = l10n.analysisServerNotBk;
      } else {
        final r = await dio.getUri<dynamic>(uri);
        if (r.statusCode != 200 || r.data is! Map) {
          msg = l10n.analysisServerLoginFail;
        } else {
          final total = r.data['total'] as int? ?? 0;
          final pending = (r.data['counts'] as Map?)?['pending'] as int? ?? 0;
          msg = l10n.analysisServerOk(number.format(total - pending), number.format(total), r.data['workers_online'] as int? ?? 0);
          error = false;
        }
      }
    } catch (_) {
      msg = l10n.analysisServerUnreachable;
      unreachable = true;
    } finally {
      dio.close();
    }
    // Pelo portal e sem resposta: o túnel pode ter trocado de nome. Pergunta
    // ao portal e testa o endereço novo, uma vez.
    if (unreachable && !retried && _viaPortal(server)) {
      await ref.read(sessionProvider.notifier).refreshPortal(force: true);
      final fresh = ref.read(settingsProvider).analysisServer;
      if (fresh != null && fresh != server && mounted) return _test(fresh, retried: true);
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _status = msg;
      _error = error;
    });
  }

  Future<void> _edit() async {
    final l10n = context.l10n;
    final current = ref.read(settingsProvider).analysisServer;
    final v = await askText(context,
        title: l10n.analysisServerAddress, initial: current ?? 'http://', hint: l10n.analysisServerExample, canRemove: current != null);
    if (v == null) return;
    final url = _base(v);
    final set = ref.read(settingsProvider.notifier).update;
    if (url.isEmpty || url == 'http:' || url == 'http://') {
      set((x) => x.copyWith(clearAnalysisServer: true));
      setState(() => _status = null);
      return;
    }
    // O link do portal (Tailscale) também vale: ele diz onde está a análise
    // hoje, e o endereço continua certo quando o túnel muda.
    setState(() {
      _testing = true;
      _status = null;
    });
    try {
      final analysis = (await ref.read(sessionProvider.notifier).usePortalLink(url))?.analysis;
      if (analysis != null) {
        if (!mounted) return;
        showSnack(context, l10n.analysisServerPortalFound);
        await _test(analysis);
        return;
      }
    } on PortalException catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _status = e.message;
        _error = true;
      });
      return;
    }
    if (!mounted) return;
    set((x) => x.copyWith(analysisServer: url));
    await _test(url);
  }

  /// Endereço de análise que veio de um portal: o painel dele não sai de casa.
  static bool _viaPortal(String server) => Uri.tryParse(server)?.path.startsWith('/bk/analise') ?? false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final server = s.analysisServer;
    final on = s.automixEnabled;
    return ListTile(
      enabled: on,
      leading: const Icon(Icons.dns_outlined),
      title: Text(l10n.analysisServer),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(server ?? l10n.analysisServerOff, style: theme.textTheme.bodyMedium),
          if (_testing)
            const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: LinearProgressIndicator())
          else if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_status!, style: theme.textTheme.bodySmall?.copyWith(color: _error ? theme.colorScheme.error : theme.colorScheme.primary)),
            ),
          if (server != null && _viaPortal(server))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l10n.analysisServerViaPortal, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 4),
          Text(l10n.analysisServerHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton(onPressed: on ? _edit : null, child: Text(server == null ? l10n.analysisServerSet : l10n.analysisServerChange)),
              if (server != null) ...[
                TextButton(onPressed: on && !_testing ? () => _test(server) : null, child: Text(l10n.analysisServerTest)),
                // Pelo portal o painel é recusado de propósito: só abre em casa.
                if (!_viaPortal(server))
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(l10n.analysisServerPanel),
                    onPressed: () => launchUrl(Uri.parse(_base(server)), mode: LaunchMode.externalApplication),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
