import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../../desktop/desktop_integration.dart';
import '../actions.dart';
import '../widgets/cover_art.dart';

/// Barra de progresso com arrasto (só aplica o seek ao soltar) e buffer.
class SeekBar extends ConsumerStatefulWidget {
  const SeekBar({super.key, this.showTimes = true});
  final bool showTimes;

  @override
  ConsumerState<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(playerProvider.select((s) => (s.position, s.duration, s.buffered)));
    final (pos, dur, buffered) = s;
    final max = dur.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max);
    final theme = Theme.of(context);
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        secondaryActiveTrackColor: theme.colorScheme.onSurface.withValues(alpha: 0.3),
      ),
      child: Slider(
        value: value,
        max: max,
        secondaryTrackValue: (buffered.clamp(0.0, 1.0)) * max,
        onChanged: dur == Duration.zero ? null : (v) => setState(() => _drag = v),
        onChangeEnd: (v) {
          ref.read(playerProvider.notifier).seek(Duration(milliseconds: v.round()));
          setState(() => _drag = null);
        },
      ),
    );
    if (!widget.showTimes) return slider;
    final style = theme.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Row(
      children: [
        SizedBox(width: 44, child: Text(formatDuration(Duration(milliseconds: value.round())), style: style, textAlign: TextAlign.right)),
        Expanded(child: slider),
        SizedBox(width: 44, child: Text(formatDuration(dur), style: style)),
      ],
    );
  }
}

class TransportControls extends ConsumerWidget {
  const TransportControls({super.key, this.big = false});
  final bool big;


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(playerProvider.select((s) => (s.playing, s.buffering, s.shuffle, s.repeat, s.current != null)));
    final (playing, buffering, shuffle, repeat, hasTrack) = s;
    final p = ref.read(playerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final iconSize = big ? 32.0 : 22.0;
    final buttons = ref.watch(uiPrefsProvider.select((p) => p.playerButtons));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (big || buttons.contains('shuffle'))
        IconButton(
          tooltip: l10n.shuffle,
          iconSize: iconSize * 0.8,
          color: shuffle ? scheme.primary : null,
          icon: const Icon(Icons.shuffle),
          onPressed: hasTrack ? p.toggleShuffle : null,
        ),
        IconButton(
          tooltip: l10n.previous,
          iconSize: iconSize,
          icon: const Icon(Icons.skip_previous),
          onPressed: hasTrack ? p.previous : null,
        ),
        SizedBox(
          width: big ? 64 : 44,
          height: big ? 64 : 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton.filled(
                tooltip: playing ? l10n.pause : l10n.play,
                iconSize: iconSize,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: hasTrack ? p.toggle : null,
              ),
              if (buffering)
                IgnorePointer(
                  child: SizedBox(
                    width: big ? 60 : 40,
                    height: big ? 60 : 40,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: l10n.next,
          iconSize: iconSize,
          icon: const Icon(Icons.skip_next),
          onPressed: hasTrack ? p.next : null,
        ),
        if (big || buttons.contains('repeat'))
        IconButton(
          tooltip: l10n.repeat,
          iconSize: iconSize * 0.8,
          color: repeat != LoopMode.off ? scheme.primary : null,
          icon: Icon(repeat == LoopMode.one ? Icons.repeat_one : Icons.repeat),
          onPressed: p.cycleRepeat,
        ),
      ],
    );
  }
}

class VolumeControl extends ConsumerWidget {
  const VolumeControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(playerProvider.select((s) => s.volume));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(volume == 0 ? Icons.volume_off : (volume < 0.5 ? Icons.volume_down : Icons.volume_up), size: 20),
        SizedBox(
          width: 110,
          child: Slider(value: volume, onChanged: (v) => ref.read(playerProvider.notifier).setVolume(v)),
        ),
      ],
    );
  }
}

/// Barra inferior do desktop.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key, required this.onToggleQueue, required this.queueOpen});
  final VoidCallback onToggleQueue;
  final bool queueOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final item = ref.watch(playerProvider.select((s) => s.current));
    final song = item?.song;
    final buttons = ref.watch(uiPrefsProvider.select((p) => p.playerButtons));
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SizedBox(
        height: 84,
        child: Row(
          children: [
            // Faixa atual
            Expanded(
              flex: 3,
              child: InkWell(
                onTap: song == null ? null : () => context.push('/now-playing'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Hero(tag: 'now-cover', child: CoverArt(coverArtId: song?.coverArt, size: 56)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song?.title ?? l10n.nothingPlaying,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                            if (song != null)
                              Text(song.displayArtist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (song != null && buttons.contains('favorite'))
                        IconButton(
                          icon: Icon(isSongStarred(ref, song) ? Icons.favorite : Icons.favorite_border, size: 20),
                          color: isSongStarred(ref, song) ? theme.colorScheme.primary : null,
                          onPressed: () => LibraryActions.toggleStar(context, ref, song),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Controles
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const TransportControls(),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: SeekBar()),
                ],
              ),
            ),
            // Extras (configuráveis)
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final b in buttons)
                    switch (b) {
                      'mix' => const _MixChip(),
                      'eq' => IconButton(
                          tooltip: l10n.openEqualizer,
                          icon: const Icon(Icons.tune),
                          onPressed: () => context.go('/equalizer'),
                        ),
                      'lyrics' => IconButton(
                          tooltip: l10n.lyrics,
                          icon: const Icon(Icons.lyrics_outlined),
                          onPressed: song == null ? null : () => context.push('/now-playing?lyrics=1'),
                        ),
                      'queue' => IconButton(
                          tooltip: l10n.queue,
                          isSelected: queueOpen,
                          icon: const Icon(Icons.queue_music),
                          onPressed: onToggleQueue,
                        ),
                      'volume' => const VolumeControl(),
                      'mini' => IconButton(
                          tooltip: l10n.miniPlayer,
                          icon: const Icon(Icons.picture_in_picture_alt_outlined),
                          onPressed: () => ref.read(miniModeProvider.notifier).enter(),
                        ),
                      _ => const SizedBox.shrink(),
                    },
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Indicador de transição de DJ: pulsa enquanto mixa; mostra a próxima quando planejada.
class _MixChip extends ConsumerWidget {
  const _MixChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final (mix, planned, synced) = ref.watch(playerProvider.select((s) => (s.mix, s.plannedMix, s.plannedSynced)));
    if (mix == null && planned == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final active = mix != null;
    final kind = synced ? l10n.mixSynced : l10n.mixSimple;
    return Tooltip(
      message: active ? '${l10n.mixing}: ${mix.summary}' : '${l10n.nextMix} ($kind): $planned',
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Chip(
          visualDensity: VisualDensity.compact,
          // Batidas casadas: ícone de sincronia; transição simples: o de troca.
          avatar: Icon(active || synced ? Icons.auto_awesome : Icons.swap_horiz,
              size: 16, color: active ? scheme.onPrimary : scheme.primary),
          label: Text(active ? l10n.mixing : 'AutoMix'),
          labelStyle: TextStyle(color: active ? scheme.onPrimary : null, fontSize: 12),
          backgroundColor: active ? scheme.primary : null,
          side: BorderSide.none,
        ),
      ),
    );
  }
}

/// Mini player para telas estreitas (celular).
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = ref.watch(playerProvider.select((s) => (s.current, s.playing, s.position, s.duration)));
    final (item, playing, pos, dur) = s;
    if (item == null) return const SizedBox.shrink();
    final progress = dur.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => context.push('/now-playing'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 2),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  CoverArt(coverArtId: item.song.coverArt, size: 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                        Text(item.song.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: ref.read(playerProvider.notifier).toggle,
                  ),
                  IconButton(icon: const Icon(Icons.skip_next), onPressed: ref.read(playerProvider.notifier).next),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
