import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../l10n/l10n.dart';

/// Biblioteca no celular: a navegação de baixo só cabe 4 abas, então álbuns,
/// músicas, artistas etc. ficam aqui (no computador estão na barra lateral).
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final local = ref.watch(sessionProvider).value?.isLocal ?? false;
    final entries = [
      ('/albums', Icons.album_outlined, l10n.albums),
      ('/songs', Icons.music_note_outlined, l10n.songs),
      ('/artists', Icons.person_outline, l10n.artists),
      ('/playlists', Icons.queue_music_outlined, l10n.playlists),
      ('/genres', Icons.sell_outlined, l10n.genres),
      ('/favorites', Icons.favorite_border, l10n.favorites),
      if (!local) ('/offline', Icons.download_outlined, l10n.downloads),
      ('/jam', Icons.groups_outlined, l10n.party),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(l10n.library, style: Theme.of(context).textTheme.headlineMedium),
        ),
        for (final (path, icon, label) in entries)
          ListTile(
            leading: Icon(icon),
            title: Text(label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(path),
          ),
      ],
    );
  }
}
