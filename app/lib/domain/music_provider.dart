import 'models.dart';

/// Um servidor de música. Hoje: OpenSubsonic. Futuro: Jellyfin, arquivos locais.
abstract class MusicProvider {
  String get accountId;
  ServerInfo? get serverInfo;

  Future<ServerInfo> connect();

  /// Endereço da rede de casa configurado.
  bool get hasLocalAddress;

  /// Usando o endereço da rede de casa agora.
  bool get onLocalAddress;

  /// Endereço em uso agora.
  String get activeAddress;

  set localAddress(String? url);

  /// Testa o endereço de casa e passa a usá-lo se responder (devolve se está nele).
  Future<bool> checkLocalAddress();

  /// Troca entre o endereço de casa (true) e o principal (false).
  Stream<bool> get endpointChanges;

  /// Chave do Connect desta conta (vem da senha no login; null = conta sem
  /// ela, entrou antes do Connect protegido, ou sem servidor).
  String? get connectKey;

  Future<List<Album>> albumList(
    AlbumListType type, {
    int size = 50,
    int offset = 0,
    String? genre,
    int? fromYear,
    int? toYear,
  });
  Future<Album> album(String id);
  Future<List<Artist>> artists();
  Future<Artist> artist(String id);
  Future<ArtistInfo?> artistInfo(String id);
  Future<List<Song>> topSongs(String artistName, {int count = 10});
  Future<List<Song>> randomSongs({int size = 50, String? genre});
  Future<List<Genre>> genres();
  Future<List<Song>> songsByGenre(String genre, {int count = 100, int offset = 0});
  Future<SearchResult> search(String query, {int artistCount = 10, int albumCount = 20, int songCount = 50});

  /// Todas as músicas da biblioteca, em páginas.
  Future<List<Song>> allSongs({int count = 200, int offset = 0});

  Future<List<Playlist>> playlists();
  Future<Playlist> playlist(String id);
  Future<Playlist> createPlaylist(String name, {List<String> songIds = const []});
  Future<void> addToPlaylist(String playlistId, List<String> songIds);
  Future<void> removeFromPlaylist(String playlistId, List<int> indexes);
  Future<void> renamePlaylist(String playlistId, String name);
  Future<void> deletePlaylist(String playlistId);

  Future<List<Song>> starredSongs();
  Future<void> setStarred({String? songId, String? albumId, String? artistId, required bool starred});
  Future<void> setRating(String id, int rating);

  Future<void> scrobble(String songId, {required bool submission, DateTime? time});
  Future<Lyrics?> lyrics(Song song);

  /// Instant Mix / rádio (no Navidrome com AudioMuse, vem da análise sônica).
  Future<List<Song>> similarSongs(String songId, {int count = 50});
  Future<List<SonicMatch>> sonicSimilar(String songId, {int count = 50});
  Future<List<SonicMatch>> sonicPath(String startSongId, String endSongId, {int count = 25});

  /// Fila salva no servidor (continuar em outro aparelho).
  Future<void> savePlayQueue(List<String> songIds, {String? current, Duration position = Duration.zero});
  Future<({List<Song> songs, String? current, Duration position})?> playQueue();

  Uri streamUri(Song song, {String? format, int? maxBitRate});
  String streamCacheKey(Song song, {String? format, int? maxBitRate});
  Uri? coverUri(String? coverArtId, {int? size});
  String? coverCacheKey(String? coverArtId, {int? size});

  /// Endereço [path] no servidor de análise do AutoMix (BK Analyzer) em
  /// [server], com o login desta conta; null se a fonte não tem esse servidor.
  Uri? analyzerUri(String server, String path);
}
