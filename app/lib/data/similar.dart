import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import 'settings.dart';
import '../domain/music_provider.dart';
import 'lastfm.dart';
import 'local/local_provider.dart';
import 'recommend.dart';

/// **O método escolhido é quem decide de onde vêm as músicas.**
///
/// Antes não era: quem tem o AudioMuse no servidor caía direto no
/// `getSonicSimilarTracks` e as sete opções não mudavam nada — o servidor
/// respondia sempre a mesma coisa. Agora a escolha manda:
///
/// - [RecommendStyle.server]: o servidor responde (análise sônica do AudioMuse
///   quando ele tem a extensão; senão o "similar" dele, com o Last.fm no meio
///   quando não há análise sônica);
/// - qualquer outro método: a conta é feita aqui, com os vetores guardados no
///   aparelho — é o único jeito de "mesmo clima" ser diferente de "mesma
///   época", porque o servidor só sabe uma medida de parecido.
///
/// Sem os vetores, os métodos locais não têm com que contar e o servidor
/// responde no lugar. Isso é um remendo, não a escolha da pessoa, então quem
/// chama precisa avisar na tela — ver [styleNeedsVectors].
bool styleNeedsVectors(RecommendStyle style) => style != RecommendStyle.server;

/// Escolher um método contado no aparelho já liga a análise guardada (quando
/// há de onde baixar): era preciso achar a opção noutra tela, e até lá a
/// escolha não mudava nada — o servidor respondia no lugar sem ninguém notar.
AppSettings chooseRecommendStyle(AppSettings s, RecommendStyle style) => s.copyWith(
      recommendStyle: style.id,
      recommendOffline: styleNeedsVectors(style) && s.analysisServer != null ? true : s.recommendOffline,
    );

/// O método escolhido vai valer agora, ou vai cair no servidor?
///
/// A tela usa isto para não prometer o que não vai acontecer.
bool styleWorksNow(RecommendStyle style, {required bool vectorsReady}) =>
    !styleNeedsVectors(style) || vectorsReady;

/// "Parecidas" com [seed], já com uma nota de 0 a 1 de quanto combinam.
///
/// A nota vem da análise sônica quando o servidor responde com ela (é a
/// medida dele); nos outros caminhos a ordem é a nota, porque a lista já vem
/// da melhor para a pior.
///
/// [strict]: só a fonte boa (os vetores ou a análise sônica do servidor),
/// sem cair no "similar" genérico quando ela não conhece a música. A rádio usa
/// isso para perceber que a semente é desconhecida (música recém-adicionada,
/// que o AudioMuse ainda não analisou) e pedir a outra — antes ela aceitava as
/// três ou quatro músicas genéricas e seguia com elas. Sem fonte boa no
/// servidor, as outras continuam valendo.
Future<List<(Song, double)>> findSimilarScored(
  MusicProvider p,
  Song seed, {
  int count = 50,
  LastFm? lastFm,
  LocalSimilar? local,
  RecommendStyle? style,
  bool strict = false,
}) async {
  final escolhido = style ?? local?.style ?? RecommendStyle.sound;
  final usaVetores = styleNeedsVectors(escolhido) && local != null && local.ready;

  if (usaVetores) {
    try {
      final r = await local.similar(seed, count: count, style: escolhido);
      if (r.isNotEmpty) return _ranked(r);
      // A semente não tem vetor: música nova, ou trocada depois do último
      // arquivo. Antes o servidor respondia no lugar e os sete métodos davam as
      // mesmas — de novo em 22/10/2026, quando a troca pelo hi-fi deixou um
      // terço da biblioteca sem vetor no app. A parecida mais próxima que tem
      // vetor faz o papel dela, e o método escolhido continua valendo.
      final ponte = await _standIn(p, seed, local, lastFm);
      if (ponte != null) {
        final r = await local.similar(ponte, count: count, style: escolhido);
        if (r.isNotEmpty) return _ranked([ponte, ...r].take(count).toList());
      }
    } catch (e) {
      debugPrint('parecidas no aparelho: $e');
    }
  }

  // Caminho do servidor: escolhido de propósito, ou remendo por falta dos
  // vetores.
  final sonic = p.serverInfo?.sonicSimilarity ?? false;
  if (sonic) {
    try {
      final r = await p.sonicSimilar(seed.id, count: count);
      if (r.isNotEmpty) return [for (final m in r) (m.song, m.similarity)];
    } catch (e) {
      debugPrint('análise sônica do servidor: $e');
    }
  }
  if (strict && (usaVetores || sonic)) return const [];
  if (!sonic && lastFm != null && p is! LocalProvider) {
    try {
      final r = await similarViaLastFm(p, lastFm, seed, count: count);
      if (r.length >= 5) return _ranked(r);
    } catch (_) {
      // Sem internet ou chave recusada: o servidor ainda pode responder.
    }
  }
  try {
    final r = await p.similarSongs(seed.id, count: count);
    if (r.isNotEmpty) return _ranked(r);
  } catch (e) {
    debugPrint('similar do servidor: $e');
  }
  // Último recurso: o servidor não respondeu (offline, ou biblioteca local sem
  // Last.fm). Com os vetores no aparelho dá para imitar a conta que o
  // AudioMuse faz no servidor — ver `Style::Server` no motor.
  if (local != null && local.ready) {
    try {
      return _ranked(await local.similar(seed, count: count, style: RecommendStyle.server));
    } catch (e) {
      debugPrint('imitando o servidor no aparelho: $e');
    }
  }
  return const [];
}

/// Quem faz o papel de [seed] nos vetores, quando ela não tem: a primeira das
/// parecidas que o servidor conhece e que tem vetor. A análise sônica vem
/// primeiro (o AudioMuse costuma conhecer a música antes do arquivo do
/// aparelho, que é exportado de hora em hora); sem ela, o "similar" do
/// servidor ou o Last.fm, que ao menos ficam no mesmo artista ou estilo.
Future<Song?> _standIn(MusicProvider p, Song seed, LocalSimilar local, LastFm? lastFm) async {
  const quantas = 10;
  final fontes = <Future<List<Song>> Function()>[
    if (p.serverInfo?.sonicSimilarity ?? false)
      () async => [for (final m in await p.sonicSimilar(seed.id, count: quantas)) m.song],
    () => p.similarSongs(seed.id, count: quantas),
    if (lastFm != null && p is! LocalProvider) () => similarViaLastFm(p, lastFm, seed, count: quantas),
  ];
  for (final fonte in fontes) {
    final List<Song> candidatas;
    try {
      candidatas = await fonte();
    } catch (_) {
      continue;
    }
    for (final c in candidatas) {
      if (c.id != seed.id && await local.knows(c.id)) return c;
    }
  }
  return null;
}

/// Mesma coisa sem as notas, para quem só quer a fila.
Future<List<Song>> findSimilar(MusicProvider p, Song seed,
        {int count = 50, LastFm? lastFm, LocalSimilar? local, RecommendStyle? style, bool strict = false}) async =>
    [
      for (final (s, _) in await findSimilarScored(p, seed,
          count: count, lastFm: lastFm, local: local, style: style, strict: strict))
        s
    ];

/// Lista já ordenada da melhor para a pior: a nota sai da posição.
List<(Song, double)> _ranked(List<Song> songs) =>
    [for (final (i, s) in songs.indexed) (s, 1 - 0.5 * i / songs.length)];
