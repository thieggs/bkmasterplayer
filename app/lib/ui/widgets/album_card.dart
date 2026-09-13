import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../actions.dart';
import 'cover_art.dart';

class AlbumCard extends ConsumerStatefulWidget {
  const AlbumCard({super.key, required this.album, this.width = 170});

  final Album album;
  final double width;

  @override
  ConsumerState<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends ConsumerState<AlbumCard> {
  bool _hover = false;

  Future<void> _menu(Offset pos) async {
    final l10n = context.l10n;
    final a = widget.album;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final v = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(pos & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(value: 0, child: Text(l10n.play)),
        PopupMenuItem(value: 1, child: Text(l10n.shuffle)),
        PopupMenuItem(value: 2, child: Text(l10n.playNext)),
        PopupMenuItem(value: 3, child: Text(l10n.addToQueue)),
        if (a.artistId != null) PopupMenuItem(value: 4, child: Text(l10n.goToArtist)),
      ],
    );
    switch (v) {
      case 0:
        LibraryActions.playAlbum(ref, a.id);
      case 1:
        LibraryActions.playAlbum(ref, a.id, shuffle: true);
      case 2:
        LibraryActions.enqueueAlbum(ref, a.id, next: true);
      case 3:
        LibraryActions.enqueueAlbum(ref, a.id);
      case 4:
        if (mounted) context.push('/artist/${a.artistId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.album;
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onSecondaryTapUp: (d) => _menu(d.globalPosition),
          onLongPressStart: (d) => _menu(d.globalPosition),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => context.push('/album/${a.id}'),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      CoverArt(coverArtId: a.coverArt, size: widget.width - 12, radius: 8),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: AnimatedOpacity(
                          opacity: _hover ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: FloatingActionButton.small(
                            heroTag: null,
                            elevation: 2,
                            onPressed: () => LibraryActions.playAlbum(ref, a.id),
                            child: const Icon(Icons.play_arrow),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  Text(
                    [a.displayArtist, if (a.year != null && a.year! > 0) '${a.year}'].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
