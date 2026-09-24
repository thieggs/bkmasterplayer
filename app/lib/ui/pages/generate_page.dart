import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/playlist_gen.dart';
import '../../data/recommend.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../recommend_style_ui.dart';
import '../widgets/song_tile.dart';

/// Aba "Gerar playlist": a pessoa escolhe os critérios e o app monta.
///
/// Quem escolhe as músicas é a análise do AudioMuse (a mesma do rádio), e
/// não o AutoMix — o AutoMix só costura uma na outra depois.
class GeneratePage extends ConsumerWidget {
  const GeneratePage({super.key});

  static const _minutos = [15, 30, 45, 60, 90, 120];
  static const _quantidades = [10, 15, 25, 40, 60, 100];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final estado = ref.watch(generateProvider);
    final c = estado.criteria;
    final gen = ref.read(generateProvider.notifier);
    final generos = ref.watch(genresProvider).value ?? const [];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(l10n.generatePlaylist, style: theme.textTheme.headlineMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(l10n.generateHint, style: theme.textTheme.bodyMedium),
        ),

        // ---- Música de partida ----
        ListTile(
          leading: const Icon(Icons.music_note_outlined),
          title: Text(l10n.genSeed),
          subtitle: Text(c.seed == null ? l10n.genSeedNone : '${c.seed!.title} — ${c.seed!.displayArtist}'),
          trailing: c.seed == null
              ? null
              : IconButton(
                  tooltip: l10n.remove,
                  icon: const Icon(Icons.close),
                  onPressed: () => gen.set((x) => x.copyWith(clearSeed: true)),
                ),
          onTap: () async {
            final s = await LibraryActions.pickSong(context, ref, title: l10n.genSeed);
            if (s != null) gen.set((x) => x.copyWith(seed: s));
          },
        ),

        // ---- Por onde se guiar (só faz sentido com semente) ----
        if (c.seed != null)
          ListTile(
            leading: Icon(c.style.icon),
            title: Text(l10n.genGuide),
            subtitle: Text(c.style.label(l10n)),
            onTap: () async {
              final escolha = await showModalBottomSheet<RecommendStyle>(
                context: context,
                showDragHandle: true,
                builder: (sheet) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final e in RecommendStyle.values)
                        ListTile(
                          leading: Icon(e.icon),
                          title: Text(e.label(l10n)),
                          subtitle: Text(e.hint(l10n), style: theme.textTheme.bodySmall),
                          trailing: e == c.style ? const Icon(Icons.check) : null,
                          onTap: () => Navigator.of(sheet).pop(e),
                        ),
                    ],
                  ),
                ),
              );
              if (escolha != null) gen.set((x) => x.copyWith(style: escolha));
            },
          ),

        // ---- Gênero ----
        ListTile(
          leading: const Icon(Icons.sell_outlined),
          title: Text(l10n.genGenre),
          subtitle: Text(c.genre ?? l10n.genAny),
          onTap: generos.isEmpty
              ? null
              : () async {
                  final escolha = await showModalBottomSheet<String>(
                    context: context,
                    showDragHandle: true,
                    builder: (sheet) => SafeArea(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          ListTile(
                            title: Text(l10n.genAny),
                            trailing: c.genre == null ? const Icon(Icons.check) : null,
                            onTap: () => Navigator.of(sheet).pop(''),
                          ),
                          for (final g in generos)
                            ListTile(
                              title: Text(g.name),
                              subtitle: Text(l10n.songCount(g.songCount)),
                              trailing: g.name == c.genre ? const Icon(Icons.check) : null,
                              onTap: () => Navigator.of(sheet).pop(g.name),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (escolha != null) {
                    gen.set((x) => escolha.isEmpty ? x.copyWith(clearGenre: true) : x.copyWith(genre: escolha));
                  }
                },
        ),

        // ---- Época ----
        _Era(criteria: c, onChanged: gen.set),

        // ---- Tamanho ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(l10n.genByMinutes), icon: const Icon(Icons.schedule)),
              ButtonSegment(value: false, label: Text(l10n.genByCount), icon: const Icon(Icons.format_list_numbered)),
            ],
            selected: {c.byMinutes},
            onSelectionChanged: (s) => gen.set((x) => x.copyWith(byMinutes: s.first)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            children: [
              for (final v in c.byMinutes ? _minutos : _quantidades)
                ChoiceChip(
                  label: Text(c.byMinutes ? l10n.genMinutes(v) : l10n.genSongs(v)),
                  selected: c.byMinutes ? c.minutes == v : c.count == v,
                  onSelected: (_) =>
                      gen.set((x) => c.byMinutes ? x.copyWith(minutes: v) : x.copyWith(count: v)),
                ),
            ],
          ),
        ),

        SwitchListTile(
          secondary: const Icon(Icons.favorite_border),
          title: Text(l10n.genOnlyStarred),
          value: c.onlyStarred,
          onChanged: (v) => gen.set((x) => x.copyWith(onlyStarred: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.download_done_outlined),
          title: Text(l10n.genOnlyDownloaded),
          subtitle: Text(l10n.genOnlyDownloadedHint, style: theme.textTheme.bodySmall),
          value: c.onlyDownloaded,
          onChanged: (v) => gen.set((x) => x.copyWith(onlyDownloaded: v)),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: FilledButton.icon(
            icon: estado.working
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_motion),
            label: Text(estado.songs.isEmpty ? l10n.genDo : l10n.genAgain),
            onPressed: estado.working ? null : gen.generate,
          ),
        ),

        if (estado.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(estado.error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          )
        else if (!estado.working && estado.songs.isEmpty)
          const SizedBox.shrink(),

        if (estado.songs.isNotEmpty) ...[
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.genResult(estado.songs.length, _tempo(estado.songs)),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: l10n.play,
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () => ref.read(playerProvider.notifier).playSongs(estado.songs),
                ),
                IconButton(
                  tooltip: l10n.genSave,
                  icon: const Icon(Icons.playlist_add),
                  onPressed: () => LibraryActions.addToPlaylist(context, ref, estado.songs),
                ),
              ],
            ),
          ),
          for (final s in estado.songs) SongTile(song: s, onTap: () => ref.read(playerProvider.notifier).playSongs(estado.songs, start: estado.songs.indexOf(s))),
        ],
      ],
    );
  }

  static int _tempo(List songs) {
    var t = Duration.zero;
    for (final s in songs) {
      t += (s.duration as Duration?) ?? const Duration(minutes: 4);
    }
    return t.inMinutes;
  }
}

/// Faixa de anos, com "qualquer época" como padrão.
class _Era extends StatelessWidget {
  const _Era({required this.criteria, required this.onChanged});

  final GenCriteria criteria;
  final void Function(GenCriteria Function(GenCriteria)) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final agora = DateTime.now().year;
    final de = criteria.fromYear ?? 1960;
    final ate = criteria.toYear ?? agora;
    final ligado = criteria.fromYear != null || criteria.toYear != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.calendar_month_outlined),
          title: Text(l10n.genEra),
          subtitle: Text(ligado ? '$de — $ate' : l10n.genAny),
          value: ligado,
          onChanged: (v) => onChanged((x) => v ? x.copyWith(fromYear: 1990, toYear: agora) : x.copyWith(clearYears: true)),
        ),
        if (ligado)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RangeSlider(
              min: 1950,
              max: agora.toDouble(),
              divisions: agora - 1950,
              labels: RangeLabels('$de', '$ate'),
              values: RangeValues(de.toDouble(), ate.toDouble()),
              onChanged: (v) => onChanged((x) => x.copyWith(fromYear: v.start.round(), toYear: v.end.round())),
            ),
          ),
      ],
    );
  }
}
