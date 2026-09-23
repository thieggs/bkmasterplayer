import 'package:flutter/material.dart';

import '../data/recommend.dart';
import '../l10n/l10n.dart';

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
