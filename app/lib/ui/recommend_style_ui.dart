import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../data/recommend.dart';
import '../l10n/l10n.dart';
import '../player/radio.dart';

/// Nome, explicação e ícone de cada jeito de recomendar.
///
/// Fica num lugar só porque as mesmas opções aparecem no rádio da tela do
/// player e nos ajustes.
extension RecommendStyleUi on RecommendStyle {
  (String, String) names(AppLocalizations l10n) => switch (this) {
        RecommendStyle.sound => (l10n.recommendStyleSound, l10n.recommendStyleSoundHint),
        RecommendStyle.mood => (l10n.recommendStyleMood, l10n.recommendStyleMoodHint),
        RecommendStyle.genre => (l10n.recommendStyleGenre, l10n.recommendStyleGenreHint),
        RecommendStyle.era => (l10n.recommendStyleEra, l10n.recommendStyleEraHint),
        RecommendStyle.lyrics => (l10n.recommendStyleLyrics, l10n.recommendStyleLyricsHint),
        RecommendStyle.mix => (l10n.recommendStyleMix, l10n.recommendStyleMixHint),
        RecommendStyle.server => (l10n.recommendStyleServer, l10n.recommendStyleServerHint),
      };

  String label(AppLocalizations l10n) => names(l10n).$1;

  String hint(AppLocalizations l10n) => names(l10n).$2;

  IconData get icon => switch (this) {
        RecommendStyle.sound => Icons.graphic_eq,
        RecommendStyle.mood => Icons.mood_outlined,
        RecommendStyle.genre => Icons.category_outlined,
        RecommendStyle.era => Icons.calendar_month_outlined,
        RecommendStyle.lyrics => Icons.lyrics_outlined,
        RecommendStyle.mix => Icons.multitrack_audio,
        RecommendStyle.server => Icons.dns_outlined,
      };
}

/// Nome e explicação de cada regra de artista repetido da rádio.
extension RadioArtistsUi on RadioArtists {
  (String, String) names(AppLocalizations l10n) => switch (this) {
        RadioArtists.vary => (l10n.radioArtistsVary, l10n.radioArtistsVaryHint),
        RadioArtists.spread => (l10n.radioArtistsSpread, l10n.radioArtistsSpreadHint),
        RadioArtists.free => (l10n.radioArtistsFree, l10n.radioArtistsFreeHint),
      };
}

/// Escolha do artista repetido na rádio: na folha da rádio e nos ajustes.
/// Vale na hora, também para a rádio que já está tocando.
class RadioArtistsPicker extends ConsumerWidget {
  const RadioArtistsPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final atual = RadioArtists.parse(ref.watch(settingsProvider.select((s) => s.radioArtists)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.radioArtists, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<RadioArtists>(
            showSelectedIcon: false,
            segments: [
              for (final r in RadioArtists.values) ButtonSegment(value: r, label: Text(r.names(l10n).$1)),
            ],
            selected: {atual},
            onSelectionChanged: (v) =>
                ref.read(settingsProvider.notifier).update((s) => s.copyWith(radioArtists: v.first.id)),
          ),
          const SizedBox(height: 6),
          Text(atual.names(l10n).$2, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
