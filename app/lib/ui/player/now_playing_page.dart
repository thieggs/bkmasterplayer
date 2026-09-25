import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../connect/devices_sheet.dart';
import '../../core/providers.dart';
import '../../domain/models.dart';
import '../../jam/jam_bar.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../widgets/cover_art.dart';
import 'player_bar.dart';
import 'queue_panel.dart';
import 'radio_sheet.dart';
import 'sleep_timer_button.dart';
import 'vinyl_disc.dart';

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key, this.showLyrics = false});
  final bool showLyrics;

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

enum _Side { lyrics, queue }

class _NowPlayingPageState extends ConsumerState<NowPlayingPage> {
  late _Side _side = widget.showLyrics ? _Side.lyrics : _Side.queue;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final item = ref.watch(playerProvider.select((s) => s.current));
    final song = item?.song;
    final bg = coverProvider(ref, song?.coverArt, 300);
    final wide = MediaQuery.sizeOf(context).width > 900;
    final ui = ref.watch(uiPrefsProvider);
    final layout = ui.nowPlayingLayout;
    final vinyl = layout == 'vinyl';

    Widget cover(double size) {
      if (vinyl) return VinylDisc(size: size, song: song, scratch: ui.vinylScratch);
      return Hero(
        tag: 'now-cover',
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(ui.coverRadius(size)),
          clipBehavior: Clip.antiAlias,
          child: CoverArt(coverArtId: song?.coverArt, size: size),
        ),
      );
    }

    // Celular deitado: pouca altura; a capa vai ao lado das informações.
    final short = MediaQuery.sizeOf(context).height < 560;

    final details = <Widget>[
      const RemoteLabel(),
      Text(
        song?.title ?? l10n.nothingPlaying,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 4),
      if (song != null)
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: song.artistId == null ? null : () => goFromPlayer(context, '/artist/${song.artistId}'),
              child: Text(song.displayArtist),
            ),
            if (song.album != null)
              TextButton(
                onPressed: song.albumId == null ? null : () => goFromPlayer(context, '/album/${song.albumId}'),
                child: Text(song.album!),
              ),
          ],
        ),
      if (song != null) _TechInfo(song: song, insight: ref.watch(playerProvider.select((s) => s.insights[item?.uid]))),
      Builder(
        builder: (context) {
          final mix = ref.watch(playerProvider.select((s) => s.mix));
          if (mix == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Chip(
              avatar: const Icon(Icons.auto_awesome, size: 16),
              label: Text('${l10n.mixing}: ${mix.summary}', maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          );
        },
      ),
      const JamBar(),
      const SizedBox(height: 12),
      const SizedBox(width: 520, child: SeekBar()),
      const TransportControls(big: true),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (song != null)
            IconButton(
              tooltip: isSongStarred(ref, song) ? l10n.unfavorite : l10n.favorite,
              icon: Icon(isSongStarred(ref, song) ? Icons.favorite : Icons.favorite_border),
              color: isSongStarred(ref, song) ? theme.colorScheme.primary : null,
              onPressed: () => LibraryActions.toggleStar(context, ref, song),
            ),
          if (song != null)
            IconButton(
              tooltip: l10n.radioSheetTitle,
              icon: const Icon(Icons.radio),
              onPressed: () => showRadioSheet(context, ref, song),
            ),
          const SleepTimerButton(),
          const DevicesButton(),
          const VolumeControl(),
        ],
      ),
    ];

    final info = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(builder: (context, c) => cover((c.maxWidth).clamp(160.0, layout == 'minimal' ? 560.0 : 460.0))),
        const SizedBox(height: 24),
        ...details,
      ],
    );

    // Deitado: capa (pela altura) | informações e controles.
    final landscapeInfo = LayoutBuilder(
      builder: (context, c) {
        final side = (c.maxHeight - 16).clamp(120.0, c.maxWidth * 0.45);
        return Row(
          children: [
            const SizedBox(width: 16),
            cover(side),
            const SizedBox(width: 16),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: details),
                ),
              ),
            ),
          ],
        );
      },
    );

    final side = layout == 'lyrics'
        ? (song == null ? const SizedBox() : LyricsView(song: song))
        : Column(
            children: [
              SegmentedButton<_Side>(
                segments: [
                  ButtonSegment(value: _Side.lyrics, label: Text(l10n.lyrics), icon: const Icon(Icons.lyrics_outlined)),
                  ButtonSegment(value: _Side.queue, label: Text(l10n.queue), icon: const Icon(Icons.queue_music)),
                ],
                selected: {_side},
                onSelectionChanged: (v) => setState(() => _side = v.first),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _side == _Side.lyrics
                    ? (song == null ? const SizedBox() : LyricsView(song: song))
                    : const QueuePanel(),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (bg != null && ui.nowPlayingBlur > 0)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Image(image: bg, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            ),
          Container(color: theme.colorScheme.surface.withValues(alpha: 1.0 - 0.4 * ui.nowPlayingBlur)),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                  ),
                ),
                Expanded(
                  child: short
                      ? PageView(
                          children: [
                            landscapeInfo,
                            Padding(padding: const EdgeInsets.all(12), child: side),
                          ],
                        )
                      : layout == 'minimal'
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: info),
                          ),
                        )
                      : wide
                      ? Row(
                          children: [
                            Expanded(
                              child: Center(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.symmetric(horizontal: 32),
                                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: info),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 440,
                              child: Padding(padding: const EdgeInsets.all(16), child: side),
                            ),
                          ],
                        )
                      : DefaultTabController(
                          length: 2,
                          child: PageView(
                            children: [
                              Center(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: info,
                                ),
                              ),
                              Padding(padding: const EdgeInsets.all(12), child: side),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TechInfo extends StatelessWidget {
  const _TechInfo({required this.song, this.insight});
  final Song song;
  final TrackInsight? insight;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (song.suffix != null) song.suffix!.toUpperCase(),
      if (song.bitDepth != null && song.bitDepth! > 0) '${song.bitDepth} bit',
      if (song.sampleRate != null)
        '${(song.sampleRate! / 1000).toStringAsFixed(song.sampleRate! % 1000 == 0 ? 0 : 1)} kHz',
      if (song.bitRate != null && song.bitRate! > 0) '${song.bitRate} kbps',
      if (insight?.bpm != null && insight!.reliable)
        '${insight!.bpm!.toStringAsFixed(insight!.bpm! % 1 == 0 ? 0 : 1)} BPM'
      else if (song.bpm != null)
        '${song.bpm} BPM',
      if (insight?.key != null) '${insight!.key} (${insight!.camelot})',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join(' • '), style: Theme.of(context).textTheme.labelSmall);
  }
}

/// Letras: sincronizadas (destaque + rolagem automática + clique para pular) ou texto.
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({super.key, required this.song});
  final Song song;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _lastActive = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _follow(int active) {
    if (active == _lastActive || active < 0) return;
    _lastActive = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[active]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.4,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final lyrics = ref.watch(lyricsProvider(widget.song));
    return lyrics.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l10n.noLyrics)),
      data: (l) {
        if (l == null || l.lines.isEmpty) return Center(child: Text(l10n.noLyrics));
        // Crédito da fonte (e o aviso de direitos que a Musixmatch exige).
        final credit = l.source == null
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                child: Text(
                  [l10n.lyricsSource(l.source!), if (l.copyright != null && l.copyright!.trim().isNotEmpty) l.copyright!.trim()].join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              );
        if (!l.synced) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.lines.map((e) => e.text).join('\n'), style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
                ?credit,
              ],
            ),
          );
        }
        final pos = ref.watch(playerProvider.select((s) => s.position)) + l.offset;
        var active = -1;
        for (var i = 0; i < l.lines.length; i++) {
          if ((l.lines[i].start ?? Duration.zero) <= pos) active = i;
        }
        _follow(active);
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 12),
          itemCount: l.lines.length + (credit == null ? 0 : 1),
          itemBuilder: (context, i) {
            if (i == l.lines.length) return credit!;
            final line = l.lines[i];
            final isActive = i == active;
            return InkWell(
              key: _keys.putIfAbsent(i, GlobalKey.new),
              borderRadius: BorderRadius.circular(8),
              onTap: line.start == null ? null : () => ref.read(playerProvider.notifier).seek(line.start! - l.offset),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  child: Text(line.text.isEmpty ? '♪' : line.text),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
