import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/providers.dart';
import '../../data/online_meta.dart';
import 'cover_art.dart';

/// O desenho genérico que o Navidrome manda quando o artista não tem foto
/// tem uns 550 bytes; foto de verdade tem dezenas de milhares.
const _minimoDeFoto = 4000;

typedef ArtistPhotoKey = ({String name, String? coverArt});

/// Caminho da foto do artista, ou null (aí fica o desenho genérico).
///
/// O servidor **sempre** responde alguma coisa — não dá para descobrir pelo
/// erro que falta foto. O que denuncia é o tamanho: abaixo disso é o desenho,
/// e só então vale procurar na internet.
final artistPhotoProvider = FutureProvider.autoDispose.family<String?, ArtistPhotoKey>((ref, a) async {
  final dir = ref.watch(cacheDirProvider);
  final cover = a.coverArt;
  if (cover != null && isFileCover(cover)) return cover;

  final session = await ref.watch(sessionProvider.future);
  if (session != null && cover != null) {
    final uri = session.provider.coverUri(cover, size: 600);
    final key = session.provider.coverCacheKey(cover, size: 600);
    if (uri != null && key != null) {
      try {
        final f = await CoverImageProvider.fetchFile(
            url: uri.toString(), cacheKey: key, cacheDir: p.join(dir.path, 'ui_covers'));
        if (await f.length() >= _minimoDeFoto) return f.path;
      } catch (_) {
        // Sem rede: fica o desenho genérico.
      }
    }
  }

  if (!ref.read(settingsProvider).onlineCovers) return null;
  return fetchArtistPhoto(artist: a.name, dir: p.join(dir.path, 'fotos_artista'));
});

/// Foto do artista, com o desenho genérico enquanto não há nada.
class ArtistPhoto extends ConsumerWidget {
  const ArtistPhoto({super.key, required this.name, required this.coverArt, this.size = 48, this.radius});

  final String name;
  final String? coverArt;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final caminho = ref.watch(artistPhotoProvider((name: name, coverArt: coverArt))).value;
    final vazio = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.person, size: size * 0.45, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size / 2),
      child: caminho == null
          ? vazio
          : Image(
              image: ResizeImage(FileImage(File(caminho)),
                  width: coverRequestSize(size), allowUpscaling: false),
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : vazio,
              errorBuilder: (_, _, _) => vazio,
            ),
    );
  }
}
