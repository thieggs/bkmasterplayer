import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../widgets/cover_art.dart';
import 'player_bar.dart';
import 'queue_panel.dart';

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

    final info = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(builder: (context, c) {
          final size = (c.maxWidth).clamp(160.0, 460.0);
          return Hero(
            tag: 'now-cover',
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: CoverArt(coverArtId: song?.coverArt, size: size, radius: 12),
            ),
          );
        }),
        const SizedBox(height: 24),
        Text(song?.title ?? l10n.nothingPlaying,
            textAlign: TextAlign.center, style: theme.textTheme.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        if (song != null)
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: song.artistId == null ? null : () => context.push('/artist/${song.artistId}'),
                child: Text(song.displayArtist),
              ),
              if (song.album != null)
                TextButton(
                  onPressed: song.albumId == null ? null : () => context.push('/album/${song.albumId}'),
                  child: Text(song.album!),
                ),
            ],
          ),
        if (song != null) _TechInfo(song: song),
        const SizedBox(height: 12),
        const SizedBox(width: 520, child: SeekBar()),
        const TransportControls(big: true),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (song != null)
              IconButton(
                icon: Icon(isSongStarred(ref, song) ? Icons.favorite : Icons.favorite_border),
                color: isSongStarred(ref, song) ? theme.colorScheme.primary : null,
                onPressed: () => LibraryActions.toggleStar(context, ref, song),
              ),
            if (song != null)
              IconButton(
                tooltip: l10n.instantMix,
                icon: const Icon(Icons.auto_awesome),
                onPressed: () => LibraryActions.instantMix(context, ref, song),
              ),
            const VolumeControl(),
          ],
        ),
      ],
    );

    final side = Column(
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
          if (bg != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Image(image: bg, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            ),
          Container(color: theme.colorScheme.surface.withValues(alpha: 0.72)),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                  ),
                ),
                Expanded(
                  child: wide
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
                            SizedBox(width: 440, child: Padding(padding: const EdgeInsets.all(16), child: side)),
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
  const _TechInfo({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (song.suffix != null) song.suffix!.toUpperCase(),
      if (song.bitDepth != null && song.bitDepth! > 0) '${song.bitDepth} bit',
      if (song.sampleRate != null) '${(song.sampleRate! / 1000).toStringAsFixed(song.sampleRate! % 1000 == 0 ? 0 : 1)} kHz',
      if (song.bitRate != null && song.bitRate! > 0) '${song.bitRate} kbps',
      if (song.bpm != null) '${song.bpm} BPM',
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
        Scrollable.ensureVisible(ctx, alignment: 0.4, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
        if (!l.synced) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(l.lines.map((e) => e.text).join('\n'), style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
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
          itemCount: l.lines.length,
          itemBuilder: (context, i) {
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
