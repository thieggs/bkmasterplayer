import 'package:flutter/foundation.dart';

import '../domain/models.dart';
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
Future<List<(Song, double)>> findSimilarScored(
  MusicProvider p,
  Song seed, {
  int count = 50,
  LastFm? lastFm,
  LocalSimilar? local,
  RecommendStyle? style,
}) async {
  final escolhido = style ?? local?.style ?? RecommendStyle.sound;

  if (styleNeedsVectors(escolhido) && local != null && local.ready) {
    try {
      final r = await local.similar(seed, count: count, style: escolhido);
      if (r.isNotEmpty) return _ranked(r);
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

/// Mesma coisa sem as notas, para quem só quer a fila.
Future<List<Song>> findSimilar(MusicProvider p, Song seed,
        {int count = 50, LastFm? lastFm, LocalSimilar? local, RecommendStyle? style}) async =>
    [for (final (s, _) in await findSimilarScored(p, seed, count: count, lastFm: lastFm, local: local, style: style)) s];

/// Lista já ordenada da melhor para a pior: a nota sai da posição.
List<(Song, double)> _ranked(List<Song> songs) =>
    [for (final (i, s) in songs.indexed) (s, 1 - 0.5 * i / songs.length)];
