import 'dart:math';

/// Modo DJ: o AudioMuse (parecença sonora) e o AutoMix (BPM e tom de cada
/// faixa) escolhem juntos a próxima música pelo melhor encaixe.

/// Encaixe de andamento (0–1): BPMs próximos, ou meio/dobro do tempo, casam
/// sem esticar demais a música (o AutoMix estica até ~8%).
double tempoFit(double? a, double? b) {
  if (a == null || b == null || a <= 0 || b <= 0) return 0.5; // desconhecido: neutro
  var best = double.infinity;
  for (final r in [b / a, 2 * b / a, b / (2 * a)]) {
    best = min(best, (log(r) / ln2).abs());
  }
  final pct = (pow(2, best) - 1) * 100;
  if (pct <= 3) return 1.0;
  if (pct <= 6) return 0.85;
  if (pct <= 8) return 0.65;
  if (pct <= 12) return 0.35;
  return 0.1;
}

(int, String)? _camelot(String? c) {
  if (c == null) return null;
  final m = RegExp(r'^(\d{1,2})([ABab])$').firstMatch(c.trim());
  if (m == null) return null;
  final n = int.parse(m.group(1)!);
  return (n >= 1 && n <= 12) ? (n, m.group(2)!.toUpperCase()) : null;
}

/// Encaixe de tom pela roda Camelot (0–1): mesmo tom, vizinhos (±1) e o
/// relativo maior/menor soam bem juntos; o resto, menos.
double keyFit(String? a, String? b) {
  final x = _camelot(a), y = _camelot(b);
  if (x == null || y == null) return 0.5;
  final d = ((x.$1 - y.$1) % 12 + 12) % 12;
  final dist = min(d, 12 - d);
  if (x.$2 == y.$2) {
    return switch (dist) { 0 => 1.0, 1 => 0.85, 2 => 0.5, _ => 0.2 };
  }
  return dist == 0 ? 0.8 : (dist == 1 ? 0.45 : 0.2);
}

/// Nota de uma candidata: parecença sonora (AudioMuse) + andamento + tom,
/// com penalidade para repetir o artista.
double djScore({
  required double similarity,
  required double tempo,
  required double key,
  bool sameArtist = false,
  bool recentArtist = false,
}) =>
    0.45 * similarity.clamp(0, 1) + 0.30 * tempo + 0.25 * key - (sameArtist ? 0.25 : 0) - (recentArtist ? 0.1 : 0);
