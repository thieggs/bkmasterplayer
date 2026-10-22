import 'dart:math';

import '../domain/models.dart';

/// Busca "parecidas" com [seed]: [count] músicas, da melhor para a pior, com
/// a nota de quanto combinam com ela (0 a 1). Quem decide de onde vêm é o
/// método escolhido (ver `data/similar.dart`).
typedef SimilarFetch = Future<List<(Song, double)>> Function(Song seed, int count);

/// O quanto a rádio deixa o artista repetir. A música, nunca.
enum RadioArtists {
  /// Variar: nenhum artista das últimas [RadioSession.artistGap], e no máximo
  /// [RadioSession.artistCap] por artista a cada [RadioSession.artistWindow].
  vary('vary', RadioSession.artistGap, RadioSession.artistCap),

  /// Pode repetir, só não duas seguidas.
  spread('spread', 1, null),

  /// À vontade: só a música não repete.
  free('free', 0, null);

  const RadioArtists(this.id, this.gap, this.cap);
  final String id;

  /// Quantas músicas para trás o artista não pode aparecer (0 = nenhuma).
  final int gap;

  /// Teto por artista a cada [RadioSession.artistWindow] (null = sem teto).
  final int? cap;

  static RadioArtists parse(String? id) => values.firstWhere((v) => v.id == id, orElse: () => vary);
}

/// Rádio infinita a partir de uma música.
///
/// **Como era e por que mudou.** A rádio pedia parecidas com a *última* música
/// da fila e emendava dez. A seguinte partia da última dessas, e assim por
/// diante: cada passo ia um pouco mais longe da música que começou, e em
/// quarenta músicas o som já era outro (medido com os vetores do AudioMuse: a
/// distância média à semente dobrava). O artista era comparado pelo texto
/// inteiro dos créditos, então "Mandragora" e "Mandragora • L3AF" eram
/// artistas diferentes; começando em Racionais, 50 de 61 músicas eram de
/// Racionais. E um mix de uma hora entrava como música qualquer.
///
/// **Como é.** A semente fica fixa e ganha uma vizinhança: as músicas mais
/// parecidas com ela que já entraram viram âncoras também, e cada leva pede a
/// uma delas, em rodízio, sempre um pouco mais fundo na lista. O som fica
/// perto da semente e ainda assim não se repete. Medido em 22/10/2026 contra o
/// Navidrome real, dez sementes de estilos diferentes, sessenta músicas cada,
/// com os vetores de som do AudioMuse como régua: a distância média à semente
/// nas últimas vinte caiu de 0,29 para 0,16; artista repetido entre as cinco
/// anteriores, de 15 para 0 por rádio.
///
/// Regras de cada música que entra:
/// - nunca a mesma (nem a mesma gravação noutro álbum: título + artistas);
/// - artista repetido, do jeito escolhido ([artists], ver [RadioArtists]):
///   no padrão, nenhum dos créditos que tocou nas últimas [artistGap] e no
///   máximo [artistCap] por artista a cada [artistWindow] músicas;
/// - nada acima de [longTrack] (mixes de uma hora), a não ser que a semente
///   também seja longa.
///
/// Quem esbarra nas regras de artista não é descartado: espera e volta quando
/// pode. Se só sobrar quem espera, ele entra assim mesmo — rádio parada é pior
/// que artista repetido.
class RadioSession {
  RadioSession(this.seed, {this.artists = RadioArtists.vary});

  final Song seed;

  /// Quanto o artista pode repetir. Muda na hora se a pessoa trocar nos ajustes.
  RadioArtists artists;

  /// Padrão do "variar" (ver [RadioArtists.vary]).
  static const artistGap = 5;

  /// Quatro, não três: em estilo de muita parceria (corrido mexicano, em que
  /// Peso Pluma e Fuerza Regida aparecem em metade das músicas) três cortava
  /// o estilo — a rádio de "SABOR FRESA" tinha 14 mexicanas nas 20 primeiras
  /// com três, e 16 com quatro.
  static const artistCap = 4;
  static const artistWindow = 30;
  static const longTrack = Duration(minutes: 12);

  /// Quantas parecidas pedir a cada âncora por vez (e quanto mais fundo a
  /// cada nova vez).
  static const pageStep = 20;

  /// Fundo máximo da lista de uma âncora.
  static const maxDepth = 200;

  /// Quantas músicas da vizinhança da semente viram âncora.
  static const neighbours = 4;

  /// Âncoras que responderam, e até onde já se pediu a cada uma.
  final _depth = <String, int>{};

  /// Âncoras que não deram nada (o servidor não conhece a música).
  final _dead = <String>{};

  /// Vizinhança da semente: (nota, música), das que já entraram.
  final _near = <(double, Song)>[];

  /// Quem esbarrou nas regras de artista e espera a vez.
  final _waiting = <Song>[];

  /// Âncora substituta quando a própria semente é desconhecida (ex.: música
  /// recém-trocada que o AudioMuse ainda não analisou).
  Song? _stand;

  int _turn = 0;

  /// Próximas [want] músicas.
  ///
  /// [history] é a fila como está (o que já tocou e o que vem): conta para
  /// não repetir e para as regras de artista. [fallback] é o último recurso
  /// quando nenhuma âncora dá nada (ex.: aleatórias do servidor).
  Future<List<Song>> next({
    required int want,
    required List<Song> history,
    required SimilarFetch fetch,
    Future<List<Song>> Function()? fallback,
  }) async {
    final seen = <String>{for (final s in history) s.id, seed.id};
    final seenKeys = <String>{for (final s in history) _key(s), _key(seed)};
    final out = <Song>[];
    final recent = [...history];

    bool fits(Song s) => !seen.contains(s.id) && !seenKeys.contains(_key(s)) && !_tooLong(s);

    void take(Song s) {
      out.add(s);
      recent.add(s);
      seen.add(s.id);
      seenKeys.add(_key(s));
    }

    bool artistOk(Song s) {
      final a = artistKeys(s);
      if (a.isEmpty) return true;
      final gap = recent.skip(max(0, recent.length - artists.gap));
      if (gap.any((r) => artistKeys(r).any(a.contains))) return false;
      final cap = artists.cap;
      if (cap == null) return true;
      final window = recent.skip(max(0, recent.length - artistWindow)).toList();
      return a.every((x) => window.where((r) => artistKeys(r).contains(x)).length < cap);
    }

    // Primeiro quem esperava e agora pode.
    for (final s in [..._waiting]) {
      if (out.length >= want) break;
      if (!fits(s)) {
        _waiting.remove(s);
      } else if (artistOk(s)) {
        _waiting.remove(s);
        take(s);
      }
    }

    // Cada volta pede a uma âncora; no máximo uma volta por âncora viva a
    // mais do que o necessário, para não ficar pedindo ao servidor sem fim.
    for (var round = 0; out.length < want && round < 12; round++) {
      final anchor = await _pickAnchor(history, fetch);
      if (anchor == null) break;
      final depth = min((_depth[anchor.id] ?? 0) + pageStep, maxDepth);
      final page = await _safe(fetch, anchor, depth);
      _depth[anchor.id] = depth;
      if (page.isEmpty) {
        _dead.add(anchor.id);
        continue;
      }
      final fromSeed = identical(anchor, _anchorSeed);
      for (final (s, score) in page) {
        if (out.length >= want) break;
        if (!fits(s) || _waiting.any((w) => w.id == s.id)) continue;
        if (!artistOk(s)) {
          _waiting.add(s);
          continue;
        }
        take(s);
        if (fromSeed) _near.add((score, s));
      }
      if (_waiting.length > 40) _waiting.removeRange(0, _waiting.length - 40);
    }

    // Só sobrou quem esperava: entra primeiro quem já pode (as regras mudam
    // a cada música que entra) e, se ninguém pode, a primeira da fila —
    // melhor artista repetido que rádio parada.
    _waiting.removeWhere((s) => !fits(s));
    while (out.length < want && _waiting.isNotEmpty) {
      final i = _waiting.indexWhere(artistOk);
      take(_waiting.removeAt(i < 0 ? 0 : i));
    }

    if (out.isEmpty && fallback != null) {
      final ponte = <Song>[];
      for (final s in await fallback()) {
        if (out.length >= want) break;
        if (fits(s)) {
          take(s);
          ponte.add(s);
        }
      }
      // Semente desconhecida e nada antes dela na fila: o que veio do último
      // recurso serve de ponte — a primeira que a fonte boa conhecer faz o
      // papel da semente, e a próxima leva já sai pela análise.
      if (_stand == null && _dead.contains(seed.id)) {
        for (final s in ponte.take(5)) {
          if ((await _safe(fetch, s, 1)).isNotEmpty) {
            _stand = s;
            break;
          }
          _dead.add(s.id);
        }
      }
    }
    return out;
  }

  /// A semente, ou quem responde no lugar dela.
  Song get _anchorSeed => _stand ?? seed;

  Future<Song?> _pickAnchor(List<Song> history, SimilarFetch fetch) async {
    // A semente não responde (desconhecida): a música anterior mais recente
    // que responda faz o papel dela.
    if (_dead.contains(_anchorSeed.id)) {
      _stand = null;
      // Só as últimas: lá atrás na fila já é outra conversa.
      for (final s in history.reversed.take(8)) {
        if (s.id == seed.id || _dead.contains(s.id) || _depth.containsKey(s.id)) continue;
        final probe = await _safe(fetch, s, 1);
        if (probe.isEmpty) {
          _dead.add(s.id);
          continue;
        }
        _stand = s;
        break;
      }
      if (_stand == null) return null;
    }
    _near.sort((a, b) => b.$1.compareTo(a.$1));
    final anchors = [
      _anchorSeed,
      for (final (_, s) in _near.take(neighbours)) s,
    ].where((a) => !_dead.contains(a.id) && (_depth[a.id] ?? 0) < maxDepth).toList();
    if (anchors.isEmpty) return null;
    return anchors[_turn++ % anchors.length];
  }

  bool _tooLong(Song s) {
    final d = s.duration;
    if (d == null || d <= longTrack) return false;
    return (seed.duration ?? Duration.zero) <= longTrack;
  }

  static Future<List<(Song, double)>> _safe(SimilarFetch fetch, Song s, int count) async {
    try {
      return await fetch(s, count);
    } catch (_) {
      return const [];
    }
  }

  /// "Mesma música": título e artistas, sem caixa nem pontuação. Pega a mesma
  /// gravação noutro álbum (single, coletânea) e a versão trocada por outra
  /// melhor.
  static String _key(Song s) =>
      '${_norm(s.title)}|${(artistKeys(s).toList()..sort()).join(',')}';

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  /// Cada artista dos créditos, separado: "Mandragora • L3AF" é Mandragora e
  /// L3AF, e "Mandragora" sozinho bate com o primeiro.
  static Set<String> artistKeys(Song s) {
    if (s.artists.isNotEmpty) {
      return {for (final a in s.artists) _norm(a.name)}..remove('');
    }
    final raw = s.artist ?? '';
    return {
      for (final p in raw.split(RegExp(r'\s*(?:•|,|;|&|/| feat\.? | ft\.? | x | e )\s*', caseSensitive: false))) _norm(p),
    }..remove('');
  }
}
