import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/recommend.dart';
import '../domain/models.dart';
import 'listen_signal.dart';
import 'radio.dart';

/// Como começa o aleatório smart quando ninguém escolheu uma música.
enum SmartStart {
  /// Sorteio, mas cada amostra de um canto diferente da biblioteca: numa
  /// biblioteca com 60% de funk, o sorteio puro dava quatro funks e o modo
  /// não aprendia nada do resto.
  varied('varied'),

  /// Sorteio puro.
  pure('pure');

  const SmartStart(this.id);
  final String id;

  static SmartStart parse(String? id) => values.firstWhere((v) => v.id == id, orElse: () => varied);
}

/// Quanto o aleatório smart arrisca fora do que já sabe que a pessoa gosta.
enum SmartExplore {
  low('low', 8),
  mid('mid', 4),
  high('high', 2);

  const SmartExplore(this.id, this.every);
  final String id;

  /// Uma música de exploração a cada tantas.
  final int every;

  static SmartExplore parse(String? id) => values.firstWhere((v) => v.id == id, orElse: () => mid);
}

/// Quão rápido o aleatório smart esquece.
enum SmartMemory {
  short('short', 8),
  normal('normal', 15),
  long('long', 30);

  const SmartMemory(this.id, this.halfLife);
  final String id;

  /// Em quantas músicas um sinal perde metade do peso.
  final int halfLife;

  static SmartMemory parse(String? id) => values.firstWhere((v) => v.id == id, orElse: () => normal);
}

/// O que cada coisa que a pessoa faz pesa.
abstract final class SmartWeights {
  /// Ouviu inteira (ver [listenSignal]).
  static const liked = 1.0;

  /// Pulou rápido.
  static const disliked = -1.0;

  /// Voltou para ouvir de novo (botão anterior).
  static const replay = 2.0;

  /// Favoritou.
  static const star = 3.0;

  /// Escolheu à mão no meio do modo (tocar a seguir, pôr na fila, pular para
  /// ela na fila). O resto conta como qualquer outra: escolheu e ouviu
  /// inteira dá +2; escolheu e pulou, 0.
  static const picked = 1.0;

  /// A música escolhida para começar: o primeiro ímã.
  static const seed = 2.0;
}

enum SmartKind { listen, seed, picked, replay, star }

/// Uma coisa que a pessoa fez com uma música.
@immutable
class SmartEvent {
  const SmartEvent(this.song, this.weight, this.at, {this.kind = SmartKind.listen});

  final Song song;
  final double weight;

  /// Quantas músicas já tinham saído de cena quando aconteceu: a idade do
  /// sinal sai daí.
  final int at;
  final SmartKind kind;

  Map<String, dynamic> toJson() => {'s': song.toJson(), 'w': weight, 'at': at, 'k': kind.name};

  static SmartEvent? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = j['s'];
    if (s is! Map) return null;
    return SmartEvent(
      Song.fromJson(Map<String, dynamic>.from(s)),
      (j['w'] as num?)?.toDouble() ?? 0,
      (j['at'] as num?)?.toInt() ?? 0,
      kind: SmartKind.values.asNameMap()[j['k']] ?? SmartKind.listen,
    );
  }
}

/// Aleatório smart: rodadas de amostras que aprendem com o que a pessoa faz.
///
/// **A ideia** (do usuário, 24/10/2026): puxar umas poucas músicas por vez
/// ([want] em [next], padrão 4) e pender para o que ela ouve inteiro e para
/// longe do que ela pula logo. A primeira rodada é sorteio, a não ser que ela
/// escolha uma música para começar.
///
/// **Como pende.** Os vetores do AudioMuse ficam no aparelho; nada muda no
/// servidor.
/// - Cada música aprovada vira um **ímã**, com o peso do que a pessoa fez
///   ([SmartWeights]). Os ímãs não se misturam: quem aprovou rock e samba quer
///   os dois, e a média dos dois não é nenhum. Cada vaga de uma rodada sorteia
///   um ímã pelo peso e pega uma das primeiras vizinhas dele — sorteada, com
///   peso pela posição, senão viriam sempre as mesmas "mais centrais".
/// - Cada ímã **responde pelo que trouxe**: vizinha dele aprovada sobe o peso
///   dele, vizinha pulada desce. Sem isso, a música que a pessoa deixou tocar
///   distraída virava ímã e seguia puxando vagas com tudo o que trazia sendo
///   pulado (simulação de 24/10/2026, ver `test/smart_sim_test.dart`).
/// - Cada pulo rápido **empurra**: a música não volta na sessão e leva junto
///   as gêmeas dela; duas ou mais puladas perto uma da outra fecham a região
///   em volta (a conta é do motor, ver `Recommender::smart`). Um pulo só pode
///   ser "essa eu não aguento mais", e não "odeio o estilo".
/// - Tudo **esquece aos poucos**: cada sinal perde metade do peso em
///   [SmartMemory.halfLife] músicas (o humor muda durante a sessão), e um pulo
///   deixa de afastar depois de duas meias-vidas.
/// - **Exploração**: uma vaga a cada [SmartExplore.every] músicas vai para um
///   canto ainda não ouvido, senão em vinte músicas o modo se fechava num
///   estilo só. Três pulos rápidos seguidos do que veio dos ímãs ([searching])
///   mandam metade da rodada seguinte explorar; seis aprovadas seguidas
///   ([confident]) cortam a exploração pela metade — nunca menos de uma a
///   cada oito. Pulo de amostra não conta para
///   a rajada: com gosto estreito quase toda amostra é pulada, e explorar mais
///   por causa disso só trazia mais amostras para pular.
///
/// **Patente.** Nos EUA há uma família de patentes ("Dynamic feedback in a
/// recommendation system", Rcrdclub/Malibu Entertainment, US 10.339.171,
/// 11.386.137, 11.748.397 e 12.118.030, até ~2035) sobre perfil vetorial +
/// sementes + conjunto de candidatas que muda com o retorno. Cada
/// reivindicação exige todos os passos dela, e este modo desvia de cada uma:
/// 1. não mostra várias sementes para a pessoa escolher uma — as amostras
///    tocam direto;
/// 2. a próxima não é "a mais perto da primeira música" de um conjunto fixo:
///    cada rodada é contada de novo sobre a biblioteca toda, com vários ímãs e
///    sorteio;
/// 3. o peso nunca depende de quantas vezes a pessoa já ouviu a música (a
///    contagem de execuções fica fora da conta).
/// Mantenha as três regras. Ver `docs/JURIDICO.md`.
class SmartSession {
  SmartSession({
    this.seed,
    this.style = RecommendStyle.genre,
    this.start = SmartStart.varied,
    this.explore = SmartExplore.mid,
    this.memory = SmartMemory.normal,
    this.artists = RadioArtists.vary,
    Random? random,
  }) : _random = random ?? Random() {
    final s = seed;
    if (s != null) note(s, SmartWeights.seed, kind: SmartKind.seed);
  }

  /// A música escolhida para começar (nula = começou no sorteio).
  final Song? seed;

  /// Régua das parecidas. "Mesmo estilo" (CLAP + som) é a que sabe estilo.
  final RecommendStyle style;

  // Ajustes: mudam na hora se a pessoa trocar.
  SmartStart start;
  SmartExplore explore;
  SmartMemory memory;
  RadioArtists artists;

  final Random _random;

  /// Tudo o que a pessoa fez, do mais antigo para o mais novo.
  final events = <SmartEvent>[];

  /// Quantas músicas já saíram de cena (a idade dos sinais).
  int played = 0;

  /// Os últimos sinais (+1/-1) do que veio dos ímãs: rajada de pulos, ou
  /// acertando.
  final _recent = <int>[];

  /// De qual ímã veio cada música escolhida (o id dele; nulo = amostra).
  final _origin = <String, String?>{};

  /// O que cada ímã trouxe e a pessoa julgou: (aprovadas, puladas).
  final _record = <String, (int, int)>{};

  /// Puladas: não voltam nesta sessão (nem a mesma gravação noutro álbum).
  final _banned = <String>{};
  final _bannedKeys = <String>{};

  static const maxEvents = 200;

  /// Saldo mínimo para uma música continuar puxando. Uma aprovada só cai
  /// abaixo disto em umas três meias-vidas.
  static const minAnchor = 0.15;

  /// Ímãs que contam numa rodada (os mais fortes).
  static const maxAnchors = 10;

  /// Vizinhas pedidas por ímã a cada rodada.
  static const perAnchor = 10;

  /// Dentre as primeiras vizinhas de um ímã, quantas concorrem ao sorteio, e
  /// quanto o peso cai de uma posição para a seguinte.
  static const draw = 6;
  static const rankDecay = 0.75;

  /// Vinheta não serve de amostra: não diz nada do gosto de ninguém.
  static const minLength = Duration(seconds: 60);

  /// A pessoa fez algo com [song] que pesa [weight] (ver [SmartWeights]).
  void note(Song song, double weight, {SmartKind kind = SmartKind.listen}) {
    events.add(SmartEvent(song, weight, played, kind: kind));
    if (weight < 0) {
      _banned.add(song.id);
      _bannedKeys.add(RadioSession.songKey(song));
    }
    if (events.length > maxEvents) events.removeRange(0, events.length - maxEvents);
  }

  /// [song] saiu de cena com o [signal] de [listenSignal].
  void left(Song song, int signal) {
    played++;
    if (signal == 0) return;
    note(song, signal > 0 ? SmartWeights.liked : SmartWeights.disliked);
    final from = _origin[song.id];
    if (from == null) return;
    final (sim, nao) = _record[from] ?? (0, 0);
    _record[from] = signal > 0 ? (sim + 1, nao) : (sim, nao + 1);
    _recent.add(signal.sign);
    if (_recent.length > 8) _recent.removeAt(0);
  }

  /// Quanto vale confiar num ímã pelo que ele trouxe: a taxa de acerto com
  /// uma aprovada e uma pulada de saída (começa em 1; duas puladas, 0,5; duas
  /// aprovadas, 1,5).
  double _trust(String id) {
    final (sim, nao) = _record[id] ?? (0, 0);
    return 2 * (sim + 1) / (sim + nao + 2);
  }

  /// De onde veio [songId]: o id do ímã que a trouxe; nulo = amostra, ou
  /// escolhida pela pessoa. Para os testes e a simulação.
  @visibleForTesting
  String? originOf(String songId) => _origin[songId];

  /// Favoritou [song] (ou desfez).
  void starred(Song song, bool on) {
    if (on) {
      note(song, SmartWeights.star, kind: SmartKind.star);
    } else {
      events.removeWhere((e) => e.kind == SmartKind.star && e.song.id == song.id);
    }
  }

  /// "Desfazer" do aviso de pulo: o último "não gostei" de [songId] não vale.
  void undo(String songId) {
    final i = events.lastIndexWhere((e) => e.song.id == songId && e.weight < 0);
    if (i < 0) return;
    final e = events.removeAt(i);
    _banned.remove(songId);
    _bannedKeys.remove(RadioSession.songKey(e.song));
    final from = _origin[songId];
    if (from == null) return;
    final (sim, nao) = _record[from] ?? (0, 0);
    if (nao > 0) _record[from] = (sim, nao - 1);
    final r = _recent.lastIndexOf(-1);
    if (r >= 0) _recent.removeAt(r);
  }

  /// O ✕ do painel: esquece tudo o que [songId] ensinou.
  void forget(String songId) {
    for (final e in events.where((e) => e.song.id == songId)) {
      _bannedKeys.remove(RadioSession.songKey(e.song));
    }
    events.removeWhere((e) => e.song.id == songId);
    _banned.remove(songId);
  }

  double _decay(SmartEvent e) => pow(0.5, (played - e.at) / memory.halfLife).toDouble();

  /// Os ímãs: músicas com saldo positivo, já descontado o tempo, da mais
  /// forte para a mais fraca.
  List<(Song, double)> anchors() {
    final saldo = <String, double>{};
    final musica = <String, Song>{};
    for (final e in events) {
      saldo[e.song.id] = (saldo[e.song.id] ?? 0) + e.weight * _decay(e);
      musica[e.song.id] = e.song;
    }
    final out = [
      for (final MapEntry(:key, :value) in saldo.entries)
        if (value > 0 && value * _trust(key) >= minAnchor) (musica[key]!, value * _trust(key)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return out.take(maxAnchors).toList();
  }

  /// Puladas que ainda afastam: até duas meias-vidas depois do pulo, e só se
  /// a música não ficou com saldo positivo (voltou atrás, favoritou).
  List<Song> avoided() {
    final out = <String, Song>{};
    for (final e in events) {
      if (e.weight < 0 && played - e.at <= 2 * memory.halfLife) out[e.song.id] = e.song;
    }
    final ima = {for (final (s, _) in anchors()) s.id};
    return [for (final s in out.values) if (!ima.contains(s.id)) s];
  }

  /// Três pulos rápidos seguidos: "não é por aqui".
  bool get searching => _recent.length >= 3 && _recent.reversed.take(3).every((s) => s < 0);

  /// Seis aprovadas seguidas: o gosto está achado.
  bool get confident => _recent.length >= 6 && _recent.reversed.take(6).every((s) => s > 0);

  /// Uma de exploração a cada quantas músicas, agora.
  int get exploreEvery {
    var n = explore.every;
    if (searching) n = max(2, n ~/ 2);
    if (confident) n = min(8, n * 2);
    return n;
  }

  /// A próxima rodada: [want] músicas.
  ///
  /// [history] é a fila como está (o que já tocou e o que vem): nada dela
  /// volta, e ela conta para a regra de artista.
  Future<List<Song>> next({required int want, required List<Song> history, required SmartSource source}) async {
    final seen = <String>{for (final s in history) s.id, ..._banned};
    final seenKeys = <String>{for (final s in history) RadioSession.songKey(s), ..._bannedKeys};
    final recent = [...history];
    final out = <Song>[];
    final imas = anchors();
    final evitar = avoided();

    bool fits(Song s) => !seen.contains(s.id) && !seenKeys.contains(RadioSession.songKey(s)) && _goodLength(s);
    bool artistOk(Song s) => RadioSession.artistAllowed(s, recent, artists);
    void take(Song s) {
      out.add(s);
      recent.add(s);
      seen.add(s.id);
      seenKeys.add(RadioSession.songKey(s));
    }

    // Rajada de pulos do que veio dos ímãs: esta rodada procura noutro canto,
    // e a rajada se gasta aqui. Antes ela ficava valendo até vir um acerto de
    // ímã, e com metade da rodada em amostras esse acerto demorava: com gosto
    // estreito, um terço das rodadas ficava "procurando" (simulação).
    final procurando = searching;
    final every = exploreEvery;
    if (procurando) _recent.clear();

    // Quantas desde a última amostra, na fila como ela está. Contar as vagas
    // geradas não servia: depois de um pulo, o replanejar tira da fila as que
    // caíram perto da pulada — quase sempre vindas de ímãs — e as amostras,
    // longe de tudo, ficam; a fila ia se enchendo de amostras (metade das
    // músicas, na simulação, em vez de uma em quatro).
    var desde = 0;
    for (final s in history.reversed) {
      if (desde >= every || (_origin.containsKey(s.id) && _origin[s.id] == null)) break;
      desde++;
    }

    // Cada vaga: exploração (null) ou o ímã sorteado para ela.
    final slots = <int?>[];
    for (var i = 0; i < want; i++) {
      if (imas.isEmpty) {
        slots.add(null);
        continue;
      }
      desde++;
      if (desde >= every) {
        desde = 0;
        slots.add(null);
      } else {
        slots.add(_weighted([for (final (_, w) in imas) w]));
      }
    }
    if (procurando) {
      for (var i = slots.length - 1; i >= 0 && slots.where((s) => s == null).length < (want + 1) ~/ 2; i--) {
        slots[i] = null;
      }
    }

    final usados = {for (final s in slots) ?s}.toList()..sort();
    final porIma = <int, List<Song>>{};
    // Quem esperou a vez do artista lembra de onde veio.
    final veioDe = <String, String?>{};
    if (usados.isNotEmpty) {
      final hits = await _safe(() => source.smartNeighbors(
            [for (final i in usados) imas[i].$1],
            avoid: evitar,
            style: style,
            perAnchor: perAnchor,
            exclude: seen,
          ));
      for (final (s, a, _) in hits) {
        if (a < 0 || a >= usados.length) continue;
        (porIma[usados[a]] ??= []).add(s);
        veioDe.putIfAbsent(s.id, () => imas[usados[a]].$1.id);
      }
    }
    // Amostras sempre vêm algumas a mais: tapam o buraco quando um ímã não dá
    // nada (servidor sem análise, tudo já tocado).
    final exploracao = slots.where((s) => s == null).length;
    final amostras = await _safe(() => source.smartExplore(
          exploracao * 2 + 3,
          known: [for (final (s, _) in imas) s, ...evitar, ...history.reversed.take(40)],
          avoid: evitar,
          liked: [for (final (s, _) in imas) s],
          exclude: seen,
          // Sorteio puro só na primeira rodada sem nada escolhido; daí em
          // diante a exploração procura o que ainda não foi ouvido.
          spread: start == SmartStart.varied || events.isNotEmpty,
          seed: _random.nextInt(1 << 31),
        ));

    // Quem esbarrou na regra de artista espera a vez, como na rádio.
    final waiting = <Song>[];

    Song? fromSamples() {
      while (amostras.isNotEmpty) {
        final s = amostras.removeAt(0);
        if (!fits(s)) continue;
        if (artistOk(s)) {
          _origin[s.id] = null;
          return s;
        }
        waiting.add(s);
      }
      return null;
    }

    Song? fromAnchor(int i) {
      final lista = porIma[i];
      if (lista == null) return null;
      lista.removeWhere((s) => !fits(s));
      final validas = <int>[];
      for (var j = 0; j < lista.length && validas.length < draw; j++) {
        if (artistOk(lista[j])) validas.add(j);
      }
      if (validas.isEmpty) {
        waiting.addAll(lista);
        lista.clear();
        return null;
      }
      final k = _weighted([for (var r = 0; r < validas.length; r++) pow(rankDecay, r).toDouble()]);
      final s = lista.removeAt(validas[k]);
      _origin[s.id] = imas[i].$1.id;
      return s;
    }

    Song? fromAnyAnchor() {
      for (final i in usados) {
        final s = fromAnchor(i);
        if (s != null) return s;
      }
      return null;
    }

    for (final slot in slots) {
      final s = slot == null
          ? (fromSamples() ?? fromAnyAnchor())
          : (fromAnchor(slot) ?? fromAnyAnchor() ?? fromSamples());
      if (s == null) break;
      take(s);
    }
    // Faltou: entra quem esperava — melhor artista repetido que fila parada.
    while (out.length < want && waiting.isNotEmpty) {
      final s = waiting.removeAt(0);
      if (!fits(s)) continue;
      _origin[s.id] = veioDe[s.id];
      take(s);
    }
    if (_origin.length > 400) {
      _origin.removeWhere((id, _) => !seen.contains(id));
    }
    return out;
  }

  /// Nada de vinheta nem de mix de uma hora (a régua da rádio), a não ser que
  /// a música escolhida para começar também seja longa.
  bool _goodLength(Song s) {
    final d = s.duration;
    if (d == null) return true;
    if (d < minLength) return false;
    return d <= RadioSession.longTrack || (seed?.duration ?? Duration.zero) > RadioSession.longTrack;
  }

  /// Posição sorteada com peso.
  int _weighted(List<double> weights) {
    final total = weights.fold<double>(0, (a, b) => a + b);
    var x = _random.nextDouble() * total;
    for (var i = 0; i < weights.length; i++) {
      x -= weights[i];
      if (x < 0) return i;
    }
    return weights.length - 1;
  }

  static Future<List<T>> _safe<T>(Future<List<T>> Function() f) async {
    try {
      return [...await f()];
    } catch (e) {
      debugPrint('aleatório smart: $e');
      return <T>[];
    }
  }

  Map<String, dynamic> toJson() => {
        if (seed != null) 'seed': seed!.toJson(),
        'played': played,
        'recent': _recent,
        'banned': [..._banned],
        'bannedKeys': [..._bannedKeys],
        'events': [for (final e in events) e.toJson()],
        'origin': _origin,
        'record': {for (final MapEntry(:key, :value) in _record.entries) key: [value.$1, value.$2]},
      };

  /// A sessão guardada com a fila (o app fechou no meio).
  static SmartSession fromJson(Map<String, dynamic> j) {
    final seed = j['seed'];
    final s = SmartSession(seed: seed is Map ? Song.fromJson(Map<String, dynamic>.from(seed)) : null);
    // O construtor anota a semente como novidade; a guardada já vem nos eventos.
    s.events
      ..clear()
      ..addAll([for (final e in (j['events'] as List? ?? const [])) ?SmartEvent.fromJson(e)]);
    s.played = (j['played'] as num?)?.toInt() ?? 0;
    s._recent.addAll([for (final x in (j['recent'] as List? ?? const [])) if (x is num) x.toInt()]);
    s._banned.addAll([for (final x in (j['banned'] as List? ?? const [])) if (x is String) x]);
    s._bannedKeys.addAll([for (final x in (j['bannedKeys'] as List? ?? const [])) if (x is String) x]);
    final origem = j['origin'];
    if (origem is Map) {
      for (final MapEntry(:key, :value) in origem.entries) {
        if (key is String && (value == null || value is String)) s._origin[key] = value as String?;
      }
    }
    final placar = j['record'];
    if (placar is Map) {
      for (final MapEntry(:key, :value) in placar.entries) {
        if (key is String && value is List && value.length == 2 && value[0] is int && value[1] is int) {
          s._record[key] = (value[0] as int, value[1] as int);
        }
      }
    }
    return s;
  }
}
