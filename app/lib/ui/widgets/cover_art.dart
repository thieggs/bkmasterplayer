import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/format.dart';
import '../../core/providers.dart';

/// Imagem de capa com cache em disco (o servidor gera a miniatura no tamanho pedido).
class CoverImageProvider extends ImageProvider<CoverImageProvider> {
  const CoverImageProvider({required this.url, required this.cacheKey, required this.cacheDir});

  final String url;
  final String cacheKey;
  final String cacheDir;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..maxConnectionsPerHost = 6;

  @override
  Future<CoverImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CoverImageProvider key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0, debugLabel: cacheKey);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final file = await fetchFile(url: url, cacheKey: cacheKey, cacheDir: cacheDir);
    return decode(await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()));
  }

  /// Arquivo da capa no cache em disco (baixa se ainda não tem).
  static Future<File> fetchFile({required String url, required String cacheKey, required String cacheDir}) async {
    final file = File(p.join(cacheDir, '${fnv1a32(cacheKey).toRadixString(16)}.img'));
    if (await file.exists()) return file;
    final req = await _http.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      throw StateError('capa: HTTP ${res.statusCode}');
    }
    final bytes = await consolidateHttpClientResponseBytes(res);
    if (bytes.isEmpty) throw StateError('capa vazia');
    final tmp = File('${file.path}.${bytes.length}.tmp');
    await tmp.writeAsBytes(bytes);
    await tmp.rename(file.path);
    return file;
  }

  @override
  bool operator ==(Object other) => other is CoverImageProvider && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}

/// Tamanhos pedidos ao servidor (poucos, para reaproveitar o cache).
int coverRequestSize(double logicalSize) {
  final px = logicalSize * 2;
  if (px <= 128) return 128;
  if (px <= 300) return 300;
  if (px <= 600) return 600;
  return 1200;
}

/// Capa guardada num arquivo do aparelho (biblioteca local, música de Jam).
bool isFileCover(String? coverArtId) => coverArtId != null && coverArtId.startsWith('/');

ImageProvider? coverProvider(WidgetRef ref, String? coverArtId, double logicalSize) {
  if (coverArtId == null) return null;
  if (isFileCover(coverArtId)) {
    return ResizeImage(FileImage(File(coverArtId)), width: coverRequestSize(logicalSize), allowUpscaling: false);
  }
  final session = ref.watch(sessionProvider).value;
  if (session == null) return null;
  final size = coverRequestSize(logicalSize);
  final uri = session.provider.coverUri(coverArtId, size: size);
  final key = session.provider.coverCacheKey(coverArtId, size: size);
  if (uri == null || key == null) return null;
  final dir = ref.watch(cacheDirProvider);
  return CoverImageProvider(url: uri.toString(), cacheKey: key, cacheDir: p.join(dir.path, 'ui_covers'));
}

class CoverArt extends ConsumerWidget {
  const CoverArt({super.key, required this.coverArtId, this.size = 48, this.radius, this.icon = Icons.album});

  final String? coverArtId;
  final double size;

  /// Arredondamento fixo; se nulo, segue o formato de capa escolhido pelo usuário.
  final double? radius;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      child: Icon(icon, size: size * 0.45, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
    );
    final provider = coverProvider(ref, coverArtId, size);
    final double r = radius ?? ref.watch(uiPrefsProvider.select<double>((p) => p.coverRadius(size)));
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: provider == null
          ? placeholder
          : Image(
              image: provider,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : placeholder,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
