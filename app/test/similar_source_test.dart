import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/recommend.dart';
import 'package:player_musica/data/similar.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/domain/music_provider.dart';

/// O método escolhido é quem decide de onde vêm as músicas.
///
/// Este teste existe por causa de um defeito de verdade: quem tinha o
/// AudioMuse no servidor caía direto no `getSonicSimilarTracks`, e as sete
/// opções do rádio não mudavam nada. Cada caso aqui olha **quem foi
/// perguntado**, não só o que voltou.

const _seed = Song(id: 'semente', title: 'Semente', artist: 'Banda');

Song _s(String id) => Song(id: id, title: id, artist: 'Banda');

/// Anota qual caminho do servidor foi usado.
class _FakeProvider implements MusicProvider {
  _FakeProvider({this.sonic = false, this.sonicGives = true, this.similarGives = true});

  final bool sonic;

  /// O servidor tem a extensão mas devolve lista vazia (música sem análise).
  final bool sonicGives;
  final bool similarGives;

  final chamadas = <String>[];

  @override
  ServerInfo? get serverInfo => ServerInfo(
        type: 'navidrome',
        version: '0.63.2',
        apiVersion: '1.16.1',
        openSubsonic: true,
        extensions: sonic ? const {'sonicSimilarity': [1]} : const {},
      );

  @override
  Future<List<SonicMatch>> sonicSimilar(String songId, {int count = 50}) async {
    chamadas.add('sonicSimilar');
    if (!sonicGives) return const [];
    // Notas de propósito fora de ordem decrescente simples, para dar para
    // provar que são as do servidor e não a posição na lista.
    return [
      SonicMatch(song: _s('sonica-1'), similarity: 0.91),
      SonicMatch(song: _s('sonica-2'), similarity: 0.42),
    ];
  }

  @override
  Future<List<Song>> similarSongs(String songId, {int count = 50}) async {
    chamadas.add('similarSongs');
    return similarGives ? [_s('servidor-1'), _s('servidor-2')] : const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Quem conta no aparelho, de mentira: anota com que método foi chamado.
class _FakeLocal implements LocalSimilar {
  _FakeLocal({this.ready = true, this.style = RecommendStyle.sound, this.gives = true, this.throws = false});

  @override
  final bool ready;

  @override
  final RecommendStyle style;

  final bool gives;
  final bool throws;
  final pedidos = <RecommendStyle>[];

  @override
  Future<List<Song>> similar(Song seed, {RecommendStyle? style, int count = 50, List<Song>? pool}) async {
    pedidos.add(style ?? this.style);
    if (throws) throw Exception('arquivo de vetores quebrado');
    return gives ? [_s('local-1'), _s('local-2')] : const [];
  }
}

void main() {
  group('o método decide a fonte', () {
    test('método do aparelho com vetores prontos: o servidor não é perguntado', () async {
      final p = _FakeProvider(sonic: true);
      final local = _FakeLocal();
      final r = await findSimilar(p, _seed, local: local, style: RecommendStyle.mood);
      expect(r.map((s) => s.id), ['local-1', 'local-2']);
      expect(local.pedidos, [RecommendStyle.mood], reason: 'o método escolhido chega no motor');
      expect(p.chamadas, isEmpty, reason: 'era o defeito: o servidor respondia na frente da escolha');
    });

    test('"deixar o servidor escolher": o aparelho não conta, mesmo com vetores', () async {
      final p = _FakeProvider(sonic: true);
      final local = _FakeLocal();
      final r = await findSimilar(p, _seed, local: local, style: RecommendStyle.server);
      expect(r.map((s) => s.id), ['sonica-1', 'sonica-2']);
      expect(local.pedidos, isEmpty);
      expect(p.chamadas, ['sonicSimilar']);
    });

    test('cada método chega no motor do jeito que foi pedido', () async {
      final p = _FakeProvider(sonic: true);
      final local = _FakeLocal();
      for (final e in RecommendStyle.values) {
        await findSimilar(p, _seed, local: local, style: e);
      }
      expect(local.pedidos, [
        for (final e in RecommendStyle.values)
          if (e != RecommendStyle.server) e,
      ]);
    });

    test('sem estilo no pedido, vale o escolhido nos ajustes', () async {
      final p = _FakeProvider(sonic: true);
      final local = _FakeLocal(style: RecommendStyle.era);
      await findSimilar(p, _seed, local: local);
      expect(local.pedidos, [RecommendStyle.era]);
    });
  });

  group('sem a análise guardada no aparelho', () {
    test('o método do aparelho cai no servidor', () async {
      final p = _FakeProvider(sonic: true);
      final local = _FakeLocal(ready: false);
      final r = await findSimilar(p, _seed, local: local, style: RecommendStyle.genre);
      expect(local.pedidos, isEmpty, reason: 'não há vetores com que contar');
      expect(p.chamadas, ['sonicSimilar']);
      expect(r.map((s) => s.id), ['sonica-1', 'sonica-2']);
    });

    test('a tela sabe quais métodos não vão valer', () {
      expect(styleWorksNow(RecommendStyle.server, vectorsReady: false), isTrue);
      for (final e in RecommendStyle.values.where((e) => e != RecommendStyle.server)) {
        expect(styleWorksNow(e, vectorsReady: false), isFalse, reason: '${e.id} precisa dos vetores');
        expect(styleWorksNow(e, vectorsReady: true), isTrue);
      }
    });
  });

  group('quando um caminho não responde', () {
    test('motor quebrado não derruba o rádio: o servidor responde', () async {
      final p = _FakeProvider(sonic: true);
      final local = _FakeLocal(throws: true);
      final r = await findSimilar(p, _seed, local: local, style: RecommendStyle.sound);
      expect(r.map((s) => s.id), ['sonica-1', 'sonica-2']);
    });

    test('vetores sem essa música: o servidor responde', () async {
      final p = _FakeProvider(sonic: true);
      final local = _FakeLocal(gives: false);
      final r = await findSimilar(p, _seed, local: local, style: RecommendStyle.sound);
      expect(local.pedidos, [RecommendStyle.sound]);
      expect(r.map((s) => s.id), ['sonica-1', 'sonica-2']);
    });

    test('servidor sem AudioMuse: o "similar" dele', () async {
      final p = _FakeProvider();
      final r = await findSimilar(p, _seed, local: _FakeLocal(ready: false), style: RecommendStyle.sound);
      expect(p.chamadas, ['similarSongs']);
      expect(r.map((s) => s.id), ['servidor-1', 'servidor-2']);
    });

    test('extensão presente mas sem análise dessa música: cai no similar', () async {
      final p = _FakeProvider(sonic: true, sonicGives: false);
      final r = await findSimilar(p, _seed, local: _FakeLocal(ready: false), style: RecommendStyle.server);
      expect(p.chamadas, ['sonicSimilar', 'similarSongs']);
      expect(r.map((s) => s.id), ['servidor-1', 'servidor-2']);
    });

    test('servidor calado: com vetores, o aparelho imita a conta dele', () async {
      final p = _FakeProvider(sonicGives: false, similarGives: false);
      final local = _FakeLocal();
      final r = await findSimilar(p, _seed, local: local, style: RecommendStyle.server);
      expect(p.chamadas, ['similarSongs']);
      expect(local.pedidos, [RecommendStyle.server], reason: 'último recurso, ver Style::Server no motor');
      expect(r.map((s) => s.id), ['local-1', 'local-2']);
    });

    test('nada responde: lista vazia, sem estourar', () async {
      final p = _FakeProvider(similarGives: false);
      final r = await findSimilar(p, _seed, local: _FakeLocal(ready: false));
      expect(r, isEmpty);
    });
  });

  group('as notas que o AutoMix usa', () {
    test('do servidor vêm as medidas dele', () async {
      final r = await findSimilarScored(_FakeProvider(sonic: true), _seed, style: RecommendStyle.server);
      expect(r.map((e) => e.$2), [0.91, 0.42]);
    });

    test('do aparelho a nota é a posição, da melhor para a pior', () async {
      final r = await findSimilarScored(_FakeProvider(), _seed, local: _FakeLocal(), style: RecommendStyle.sound);
      expect(r.length, 2);
      expect(r.first.$2, greaterThan(r.last.$2));
      expect(r.first.$2, 1.0);
    });
  });
}
