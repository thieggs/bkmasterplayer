import '../domain/models.dart';
import '../domain/music_provider.dart';
import 'lastfm.dart';

/// A versão que o servidor tem hoje de [old].
///
/// Música trocada por um arquivo melhor (a troca pelo hi-fi põe um FLAC no
/// lugar do MP3) ganha id novo no Navidrome. O id velho continua respondendo,
/// mas o arquivo sumiu e tocar dá erro. A fila, as listas abertas antes e os
/// downloads guardam o id velho; a busca do servidor só conhece o novo.
///
/// Devolve a própria música (como o servidor a mostra agora) se ela continua
/// na biblioteca, a substituta se achou uma, e `null` se não achou nada.
/// [strict] é para quem confere sem ter visto erro: só troca pela mesma
/// gravação (mesmo ISRC, ou mesmo artista e mesma duração).
///
/// A regra foi medida nas 5312 trocas da biblioteca em 23/10/2026: o título
/// novo perde "(Remastered)", " - Ao Vivo", convidados (25%); o número da
/// faixa e o álbum mudam muito; o ISRC bate em 98,5%. Assim acerta 99,2%.
Future<Song?> currentVersion(MusicProvider p, Song old, {bool strict = false}) async {
  final core = titleCore(old.title);
  if (core.isEmpty) return null;
  final artists = _artists(old);
  bool withArtist(Song s) => artists.isEmpty || _artists(s).any(artists.contains);
  // Só o núcleo do título acha 98,9%; com os artistas, os convidados de um
  // lado e não do outro derrubam para 67%. O primeiro artista é a segunda
  // tentativa, para título comum ("Intro") com outras cinquenta na frente.
  final first = artists.isEmpty ? '' : _artistNames(old).map(matchKey).firstWhere((a) => a.isNotEmpty, orElse: () => '');
  final found = <String, Song>{};
  for (final q in [core, if (first.isNotEmpty) '$core $first']) {
    for (final s in (await p.search(q, artistCount: 0, albumCount: 0, songCount: 50)).songs) {
      if (s.id == old.id) return s;
      if (titleCore(s.title) == core) found[s.id] = s;
    }
    if (found.values.any(withArtist)) break;
  }
  if (found.isEmpty) return null;

  // A fila guardada antes desta versão não tem o ISRC; o servidor ainda
  // responde o id velho com as etiquetas dele.
  var isrc = old.isrc.toSet();
  if (isrc.isEmpty) {
    try {
      isrc = (await p.songsByIds([old.id])).firstOrNull?.isrc.toSet() ?? const {};
    } catch (_) {}
  }
  int gap(Song s) => old.duration == null || s.duration == null ? 0 : (s.duration! - old.duration!).inSeconds.abs();
  final all = found.values.toList();
  // Remasterização muda a duração em 3 a 7 s: com o mesmo ISRC, não importa.
  var ok = [for (final s in all) if (s.isrc.any(isrc.contains)) s];
  if (ok.isEmpty) ok = [for (final s in all) if (withArtist(s) && gap(s) <= 3) s];
  if (ok.isEmpty && !strict) ok = [for (final s in all) if (gap(s) <= 3) s];
  if (ok.isEmpty) return null;
  ok.sort((a, b) {
    final c = (_lossless.contains(b.suffix?.toLowerCase()) ? 1 : 0) - (_lossless.contains(a.suffix?.toLowerCase()) ? 1 : 0);
    return c != 0 ? c : gap(a) - gap(b);
  });
  return ok.first;
}

/// O título sem o que costuma mudar entre a versão velha e a nova: "(feat. X)",
/// "[Live in NYC - 1993]", " - Remastered 2011", " / Good Luck", "Ao Vivo" no
/// fim, e "&#039;" de etiqueta mal gravada.
String titleCore(String title) {
  final clean = title
      .replaceAll(RegExp(r'&#0*39;'), "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      // Parênteses antes do " - ": "(Live in NYC - 1993)" é um bloco só.
      .replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ')
      .replaceFirst(RegExp(r'\s+[-:/]\s+.*$'), '');
  final t = matchKey(clean)
      .replaceFirst(RegExp(r'\s(ao vivo|live( version)?|remasterizad[ao]|(\d{4} )?remaster(ed)?( \d{4})?)$'), '')
      .trim();
  return t.isNotEmpty ? t : matchKey(title);
}

const _lossless = {'flac', 'alac', 'wav', 'aiff', 'aif', 'ape', 'wv', 'dsf', 'dff'};

final _separators = RegExp(r'\s*(?:•|,|;|&amp;|&|/| feat\.? | ft\.? | x | e )\s*', caseSensitive: false);

Iterable<String> _artistNames(Song s) =>
    s.artists.isNotEmpty ? s.artists.map((a) => a.name) : (s.artist ?? '').split(_separators);

Set<String> _artists(Song s) => {for (final a in _artistNames(s)) matchKey(a)}..remove('');
