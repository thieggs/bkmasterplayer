import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In pt, this message translates to:
  /// **'BKmasterplayer 🎵'**
  String get appTitle;

  /// No description provided for @about.
  ///
  /// In pt, this message translates to:
  /// **'Sobre'**
  String get about;

  /// No description provided for @aboutText.
  ///
  /// In pt, this message translates to:
  /// **'Player open source para servidores OpenSubsonic (Navidrome), com AudioMuse-AI e AutoMix. Licença MIT.'**
  String get aboutText;

  /// No description provided for @accentColor.
  ///
  /// In pt, this message translates to:
  /// **'Cor de destaque'**
  String get accentColor;

  /// No description provided for @addedToPlaylist.
  ///
  /// In pt, this message translates to:
  /// **'Adicionado à playlist'**
  String get addedToPlaylist;

  /// No description provided for @addToPlaylist.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar à playlist'**
  String get addToPlaylist;

  /// No description provided for @shareLink.
  ///
  /// In pt, this message translates to:
  /// **'Compartilhar link'**
  String get shareLink;

  /// No description provided for @shareLinkCopied.
  ///
  /// In pt, this message translates to:
  /// **'Link copiado: {link}'**
  String shareLinkCopied(String link);

  /// No description provided for @shareUnavailable.
  ///
  /// In pt, this message translates to:
  /// **'Não deu para criar o link. No Navidrome, o compartilhamento precisa estar ligado (ND_ENABLESHARING=true).'**
  String get shareUnavailable;

  /// No description provided for @addToQueue.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar à fila'**
  String get addToQueue;

  /// No description provided for @album.
  ///
  /// In pt, this message translates to:
  /// **'Álbum'**
  String get album;

  /// No description provided for @albums.
  ///
  /// In pt, this message translates to:
  /// **'Álbuns'**
  String get albums;

  /// No description provided for @appearance.
  ///
  /// In pt, this message translates to:
  /// **'Aparência'**
  String get appearance;

  /// No description provided for @artist.
  ///
  /// In pt, this message translates to:
  /// **'Artista'**
  String get artist;

  /// No description provided for @artistRadio.
  ///
  /// In pt, this message translates to:
  /// **'Rádio do artista'**
  String get artistRadio;

  /// No description provided for @artists.
  ///
  /// In pt, this message translates to:
  /// **'Artistas'**
  String get artists;

  /// No description provided for @audioMuse.
  ///
  /// In pt, this message translates to:
  /// **'AudioMuse-AI (análise sônica)'**
  String get audioMuse;

  /// No description provided for @audioMuseActive.
  ///
  /// In pt, this message translates to:
  /// **'Ativo: rádio sônica e caminho sônico disponíveis nos menus'**
  String get audioMuseActive;

  /// No description provided for @audioMuseInactive.
  ///
  /// In pt, this message translates to:
  /// **'Não detectado. Instale o plugin AudioMuse-AI no Navidrome (0.62+) para liberar a rádio sônica.'**
  String get audioMuseInactive;

  /// No description provided for @buildingMix.
  ///
  /// In pt, this message translates to:
  /// **'Montando o mix…'**
  String get buildingMix;

  /// No description provided for @cache.
  ///
  /// In pt, this message translates to:
  /// **'Cache de músicas'**
  String get cache;

  /// No description provided for @cancel.
  ///
  /// In pt, this message translates to:
  /// **'Cancelar'**
  String get cancel;

  /// No description provided for @clear.
  ///
  /// In pt, this message translates to:
  /// **'Limpar'**
  String get clear;

  /// No description provided for @compilation.
  ///
  /// In pt, this message translates to:
  /// **'Coletânea'**
  String get compilation;

  /// No description provided for @connect.
  ///
  /// In pt, this message translates to:
  /// **'Conectar'**
  String get connect;

  /// No description provided for @crossfade.
  ///
  /// In pt, this message translates to:
  /// **'Crossfade'**
  String get crossfade;

  /// No description provided for @crossfadeHint.
  ///
  /// In pt, this message translates to:
  /// **'Faixas seguidas do mesmo álbum sempre tocam sem pausa e sem crossfade.'**
  String get crossfadeHint;

  /// No description provided for @crossfadeOff.
  ///
  /// In pt, this message translates to:
  /// **'Desligado (sem pausa entre faixas)'**
  String get crossfadeOff;

  /// No description provided for @delete.
  ///
  /// In pt, this message translates to:
  /// **'Excluir'**
  String get delete;

  /// No description provided for @desktop.
  ///
  /// In pt, this message translates to:
  /// **'Computador'**
  String get desktop;

  /// No description provided for @discover.
  ///
  /// In pt, this message translates to:
  /// **'Descobrir'**
  String get discover;

  /// No description provided for @dynamicColor.
  ///
  /// In pt, this message translates to:
  /// **'Cores da capa'**
  String get dynamicColor;

  /// No description provided for @dynamicColorHint.
  ///
  /// In pt, this message translates to:
  /// **'O tema acompanha a capa da música tocando'**
  String get dynamicColorHint;

  /// No description provided for @favorite.
  ///
  /// In pt, this message translates to:
  /// **'Favoritar'**
  String get favorite;

  /// No description provided for @favorites.
  ///
  /// In pt, this message translates to:
  /// **'Favoritas'**
  String get favorites;

  /// No description provided for @filter.
  ///
  /// In pt, this message translates to:
  /// **'Filtrar'**
  String get filter;

  /// No description provided for @genres.
  ///
  /// In pt, this message translates to:
  /// **'Gêneros'**
  String get genres;

  /// No description provided for @goToAlbum.
  ///
  /// In pt, this message translates to:
  /// **'Ir para o álbum'**
  String get goToAlbum;

  /// No description provided for @goToArtist.
  ///
  /// In pt, this message translates to:
  /// **'Ir para o artista'**
  String get goToArtist;

  /// No description provided for @home.
  ///
  /// In pt, this message translates to:
  /// **'Início'**
  String get home;

  /// No description provided for @instantMix.
  ///
  /// In pt, this message translates to:
  /// **'Mix instantâneo'**
  String get instantMix;

  /// No description provided for @loginHint.
  ///
  /// In pt, this message translates to:
  /// **'Funciona com Navidrome, Gonic, Ampache, Airsonic e outros servidores compatíveis com Subsonic. A senha não é guardada: só um token.'**
  String get loginHint;

  /// No description provided for @loginSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Conecte ao seu servidor de música'**
  String get loginSubtitle;

  /// No description provided for @logout.
  ///
  /// In pt, this message translates to:
  /// **'Sair'**
  String get logout;

  /// No description provided for @lyrics.
  ///
  /// In pt, this message translates to:
  /// **'Letra'**
  String get lyrics;

  /// No description provided for @mostPlayed.
  ///
  /// In pt, this message translates to:
  /// **'Mais tocados'**
  String get mostPlayed;

  /// No description provided for @newPlaylist.
  ///
  /// In pt, this message translates to:
  /// **'Nova playlist'**
  String get newPlaylist;

  /// No description provided for @next.
  ///
  /// In pt, this message translates to:
  /// **'Próxima'**
  String get next;

  /// No description provided for @noLyrics.
  ///
  /// In pt, this message translates to:
  /// **'Sem letra para esta música'**
  String get noLyrics;

  /// No description provided for @noResults.
  ///
  /// In pt, this message translates to:
  /// **'Nada encontrado'**
  String get noResults;

  /// No description provided for @noSimilarSongs.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma música parecida encontrada'**
  String get noSimilarSongs;

  /// No description provided for @nothingHere.
  ///
  /// In pt, this message translates to:
  /// **'Nada por aqui ainda'**
  String get nothingHere;

  /// No description provided for @nothingPlaying.
  ///
  /// In pt, this message translates to:
  /// **'Nada tocando'**
  String get nothingPlaying;

  /// No description provided for @offline.
  ///
  /// In pt, this message translates to:
  /// **'Servidor offline — tentar de novo'**
  String get offline;

  /// No description provided for @ok.
  ///
  /// In pt, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @outputDevice.
  ///
  /// In pt, this message translates to:
  /// **'Saída de áudio'**
  String get outputDevice;

  /// No description provided for @password.
  ///
  /// In pt, this message translates to:
  /// **'Senha'**
  String get password;

  /// No description provided for @pause.
  ///
  /// In pt, this message translates to:
  /// **'Pausar'**
  String get pause;

  /// No description provided for @play.
  ///
  /// In pt, this message translates to:
  /// **'Tocar'**
  String get play;

  /// No description provided for @playback.
  ///
  /// In pt, this message translates to:
  /// **'Reprodução'**
  String get playback;

  /// No description provided for @playlist.
  ///
  /// In pt, this message translates to:
  /// **'Playlist'**
  String get playlist;

  /// No description provided for @playlistName.
  ///
  /// In pt, this message translates to:
  /// **'Nome da playlist'**
  String get playlistName;

  /// No description provided for @playlists.
  ///
  /// In pt, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @playNext.
  ///
  /// In pt, this message translates to:
  /// **'Tocar a seguir'**
  String get playNext;

  /// No description provided for @playNow.
  ///
  /// In pt, this message translates to:
  /// **'Tocar agora'**
  String get playNow;

  /// No description provided for @preamp.
  ///
  /// In pt, this message translates to:
  /// **'Pré-amplificação'**
  String get preamp;

  /// No description provided for @previous.
  ///
  /// In pt, this message translates to:
  /// **'Anterior'**
  String get previous;

  /// No description provided for @qualityOriginal.
  ///
  /// In pt, this message translates to:
  /// **'Original (sem conversão)'**
  String get qualityOriginal;

  /// No description provided for @queue.
  ///
  /// In pt, this message translates to:
  /// **'Fila'**
  String get queue;

  /// No description provided for @queueEmpty.
  ///
  /// In pt, this message translates to:
  /// **'A fila está vazia'**
  String get queueEmpty;

  /// No description provided for @random.
  ///
  /// In pt, this message translates to:
  /// **'Aleatório'**
  String get random;

  /// No description provided for @recentlyAdded.
  ///
  /// In pt, this message translates to:
  /// **'Adicionados recentemente'**
  String get recentlyAdded;

  /// No description provided for @recentlyPlayed.
  ///
  /// In pt, this message translates to:
  /// **'Tocados recentemente'**
  String get recentlyPlayed;

  /// No description provided for @removeFromPlaylist.
  ///
  /// In pt, this message translates to:
  /// **'Remover da playlist'**
  String get removeFromPlaylist;

  /// No description provided for @rename.
  ///
  /// In pt, this message translates to:
  /// **'Renomear'**
  String get rename;

  /// No description provided for @repeat.
  ///
  /// In pt, this message translates to:
  /// **'Repetir'**
  String get repeat;

  /// No description provided for @replayGain.
  ///
  /// In pt, this message translates to:
  /// **'Normalização de volume (ReplayGain)'**
  String get replayGain;

  /// No description provided for @required.
  ///
  /// In pt, this message translates to:
  /// **'Obrigatório'**
  String get required;

  /// No description provided for @retry.
  ///
  /// In pt, this message translates to:
  /// **'Tentar de novo'**
  String get retry;

  /// No description provided for @rgAlbum.
  ///
  /// In pt, this message translates to:
  /// **'Por álbum'**
  String get rgAlbum;

  /// No description provided for @rgAuto.
  ///
  /// In pt, this message translates to:
  /// **'Automático'**
  String get rgAuto;

  /// No description provided for @rgOff.
  ///
  /// In pt, this message translates to:
  /// **'Desligado'**
  String get rgOff;

  /// No description provided for @rgTrack.
  ///
  /// In pt, this message translates to:
  /// **'Por faixa'**
  String get rgTrack;

  /// No description provided for @search.
  ///
  /// In pt, this message translates to:
  /// **'Buscar'**
  String get search;

  /// No description provided for @searchEmptyHint.
  ///
  /// In pt, this message translates to:
  /// **'Busque por artistas, álbuns e músicas'**
  String get searchEmptyHint;

  /// No description provided for @recentSearches.
  ///
  /// In pt, this message translates to:
  /// **'Buscas recentes'**
  String get recentSearches;

  /// No description provided for @clearRecentSearches.
  ///
  /// In pt, this message translates to:
  /// **'Limpar'**
  String get clearRecentSearches;

  /// No description provided for @removeRecentSearch.
  ///
  /// In pt, this message translates to:
  /// **'Tirar das recentes'**
  String get removeRecentSearch;

  /// No description provided for @searchHint.
  ///
  /// In pt, this message translates to:
  /// **'Buscar…'**
  String get searchHint;

  /// No description provided for @seeAll.
  ///
  /// In pt, this message translates to:
  /// **'Ver tudo'**
  String get seeAll;

  /// No description provided for @server.
  ///
  /// In pt, this message translates to:
  /// **'Servidor'**
  String get server;

  /// No description provided for @serverUrl.
  ///
  /// In pt, this message translates to:
  /// **'Endereço do servidor'**
  String get serverUrl;

  /// No description provided for @settings.
  ///
  /// In pt, this message translates to:
  /// **'Configurações'**
  String get settings;

  /// No description provided for @shuffle.
  ///
  /// In pt, this message translates to:
  /// **'Aleatório'**
  String get shuffle;

  /// No description provided for @shuffleLibrary.
  ///
  /// In pt, this message translates to:
  /// **'Aleatório na biblioteca'**
  String get shuffleLibrary;

  /// No description provided for @similarArtists.
  ///
  /// In pt, this message translates to:
  /// **'Artistas parecidos'**
  String get similarArtists;

  /// No description provided for @songs.
  ///
  /// In pt, this message translates to:
  /// **'Músicas'**
  String get songs;

  /// No description provided for @library.
  ///
  /// In pt, this message translates to:
  /// **'Biblioteca'**
  String get library;

  /// No description provided for @sonicPath.
  ///
  /// In pt, this message translates to:
  /// **'Caminho sônico até…'**
  String get sonicPath;

  /// No description provided for @sonicPathPickTarget.
  ///
  /// In pt, this message translates to:
  /// **'Escolha a música de destino'**
  String get sonicPathPickTarget;

  /// No description provided for @sonicRadio.
  ///
  /// In pt, this message translates to:
  /// **'Rádio sônica (AudioMuse)'**
  String get sonicRadio;

  /// No description provided for @sortByArtist.
  ///
  /// In pt, this message translates to:
  /// **'Artista (A–Z)'**
  String get sortByArtist;

  /// No description provided for @sortByName.
  ///
  /// In pt, this message translates to:
  /// **'Nome (A–Z)'**
  String get sortByName;

  /// No description provided for @sortByYear.
  ///
  /// In pt, this message translates to:
  /// **'Ano'**
  String get sortByYear;

  /// No description provided for @streaming.
  ///
  /// In pt, this message translates to:
  /// **'Streaming'**
  String get streaming;

  /// No description provided for @streamQuality.
  ///
  /// In pt, this message translates to:
  /// **'Qualidade do streaming'**
  String get streamQuality;

  /// No description provided for @mobileQuality.
  ///
  /// In pt, this message translates to:
  /// **'Qualidade nos dados móveis'**
  String get mobileQuality;

  /// No description provided for @mobileQualityHint.
  ///
  /// In pt, this message translates to:
  /// **'Economiza o plano quando não há Wi-Fi'**
  String get mobileQualityHint;

  /// No description provided for @sameAsWifi.
  ///
  /// In pt, this message translates to:
  /// **'A mesma do Wi-Fi'**
  String get sameAsWifi;

  /// No description provided for @systemDefault.
  ///
  /// In pt, this message translates to:
  /// **'Padrão do sistema'**
  String get systemDefault;

  /// No description provided for @theme.
  ///
  /// In pt, this message translates to:
  /// **'Tema'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In pt, this message translates to:
  /// **'Escuro'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In pt, this message translates to:
  /// **'Claro'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In pt, this message translates to:
  /// **'Sistema'**
  String get themeSystem;

  /// No description provided for @topRated.
  ///
  /// In pt, this message translates to:
  /// **'Mais bem avaliados'**
  String get topRated;

  /// No description provided for @topSongs.
  ///
  /// In pt, this message translates to:
  /// **'Mais tocadas'**
  String get topSongs;

  /// No description provided for @trackNotifications.
  ///
  /// In pt, this message translates to:
  /// **'Notificar troca de música'**
  String get trackNotifications;

  /// No description provided for @trackNotificationsHint.
  ///
  /// In pt, this message translates to:
  /// **'Mostra uma notificação com a capa. Trocas seguidas atualizam a mesma notificação (não empilha).'**
  String get trackNotificationsHint;

  /// No description provided for @uiScale.
  ///
  /// In pt, this message translates to:
  /// **'Tamanho da interface'**
  String get uiScale;

  /// No description provided for @unfavorite.
  ///
  /// In pt, this message translates to:
  /// **'Desfavoritar'**
  String get unfavorite;

  /// No description provided for @username.
  ///
  /// In pt, this message translates to:
  /// **'Usuário'**
  String get username;

  /// No description provided for @wrongCredentials.
  ///
  /// In pt, this message translates to:
  /// **'Usuário ou senha incorretos'**
  String get wrongCredentials;

  /// No description provided for @albumCount.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =0{Nenhum álbum} =1{1 álbum} other{{count} álbuns}}'**
  String albumCount(int count);

  /// No description provided for @songCount.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =0{Nenhuma música} =1{1 música} other{{count} músicas}}'**
  String songCount(int count);

  /// No description provided for @disc.
  ///
  /// In pt, this message translates to:
  /// **'Disco {number}'**
  String disc(int number);

  /// No description provided for @seconds.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 segundo} other{{count} segundos}}'**
  String seconds(int count);

  /// No description provided for @queueSummary.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =1{1 música a seguir} other{{count} músicas a seguir}} • {duration}'**
  String queueSummary(int count, String duration);

  /// No description provided for @cacheUsage.
  ///
  /// In pt, this message translates to:
  /// **'{used} MB usados de {limit} MB'**
  String cacheUsage(String used, int limit);

  /// No description provided for @deletePlaylistQuestion.
  ///
  /// In pt, this message translates to:
  /// **'Excluir a playlist \"{name}\"?'**
  String deletePlaylistQuestion(String name);

  /// No description provided for @outputDeviceFailed.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível usar esse dispositivo; continuando no anterior.'**
  String get outputDeviceFailed;

  /// No description provided for @automix.
  ///
  /// In pt, this message translates to:
  /// **'AutoMix (transição de DJ)'**
  String get automix;

  /// No description provided for @automixEnable.
  ///
  /// In pt, this message translates to:
  /// **'Ativar AutoMix'**
  String get automixEnable;

  /// No description provided for @automixEnableHint.
  ///
  /// In pt, this message translates to:
  /// **'Analisa as músicas (batida, compasso, tom) e faz transições sincronizadas como um DJ. Sem batida clara, faz uma transição suave.'**
  String get automixEnableHint;

  /// No description provided for @automixStyle.
  ///
  /// In pt, this message translates to:
  /// **'Estilo da transição'**
  String get automixStyle;

  /// No description provided for @mixAuto.
  ///
  /// In pt, this message translates to:
  /// **'Automático (recomendado)'**
  String get mixAuto;

  /// No description provided for @mixBassSwap.
  ///
  /// In pt, this message translates to:
  /// **'Troca de grave'**
  String get mixBassSwap;

  /// No description provided for @mixBlend.
  ///
  /// In pt, this message translates to:
  /// **'Mistura suave'**
  String get mixBlend;

  /// No description provided for @mixFilter.
  ///
  /// In pt, this message translates to:
  /// **'Filtro'**
  String get mixFilter;

  /// No description provided for @mixEcho.
  ///
  /// In pt, this message translates to:
  /// **'Eco'**
  String get mixEcho;

  /// No description provided for @mixCut.
  ///
  /// In pt, this message translates to:
  /// **'Corte no compasso'**
  String get mixCut;

  /// No description provided for @automixBars.
  ///
  /// In pt, this message translates to:
  /// **'Duração preferida (compassos)'**
  String get automixBars;

  /// No description provided for @automixBarsHint.
  ///
  /// In pt, this message translates to:
  /// **'Quanto as duas músicas tocam juntas quando a estrutura permite.'**
  String get automixBarsHint;

  /// No description provided for @automixMaxSeconds.
  ///
  /// In pt, this message translates to:
  /// **'Duração máxima da transição'**
  String get automixMaxSeconds;

  /// No description provided for @automixUnclear.
  ///
  /// In pt, this message translates to:
  /// **'Transição quando a música não é clara'**
  String get automixUnclear;

  /// No description provided for @automixUnclearHint.
  ///
  /// In pt, this message translates to:
  /// **'Quanto da música usar na transição quando não há batida confiável ou intro/outro definidas.'**
  String get automixUnclearHint;

  /// No description provided for @automixMaxTempo.
  ///
  /// In pt, this message translates to:
  /// **'Mudança máxima de velocidade'**
  String get automixMaxTempo;

  /// No description provided for @automixMaxTempoHint.
  ///
  /// In pt, this message translates to:
  /// **'Até quanto a próxima música pode acelerar/desacelerar para as batidas casarem (sem mudar o tom).'**
  String get automixMaxTempoHint;

  /// No description provided for @automixRamp.
  ///
  /// In pt, this message translates to:
  /// **'Volta ao tempo original (compassos)'**
  String get automixRamp;

  /// No description provided for @automixRampKeep.
  ///
  /// In pt, this message translates to:
  /// **'mantém'**
  String get automixRampKeep;

  /// No description provided for @automixRampHint.
  ///
  /// In pt, this message translates to:
  /// **'Depois da transição, a música volta devagar à velocidade original.'**
  String get automixRampHint;

  /// No description provided for @automixHarmonic.
  ///
  /// In pt, this message translates to:
  /// **'Mixagem harmônica'**
  String get automixHarmonic;

  /// No description provided for @automixHarmonicHint.
  ///
  /// In pt, this message translates to:
  /// **'Quando os tons não combinam (roda Camelot), faz uma transição curta com filtro.'**
  String get automixHarmonicHint;

  /// No description provided for @automixTrim.
  ///
  /// In pt, this message translates to:
  /// **'Cortar silêncio no começo e no fim'**
  String get automixTrim;

  /// No description provided for @automixAlbums.
  ///
  /// In pt, this message translates to:
  /// **'Respeitar álbuns'**
  String get automixAlbums;

  /// No description provided for @automixAlbumsHint.
  ///
  /// In pt, this message translates to:
  /// **'Em álbuns contínuos (ao vivo, mixados, conceituais), faixas seguidas emendam sem pausa, sem mixar. Álbuns com silêncio entre as faixas são mixados normalmente.'**
  String get automixAlbumsHint;

  /// No description provided for @automixPreAnalyze.
  ///
  /// In pt, this message translates to:
  /// **'Pré-analisar a fila'**
  String get automixPreAnalyze;

  /// No description provided for @automixPreAnalyzeHint.
  ///
  /// In pt, this message translates to:
  /// **'Analisa as próximas músicas com antecedência, em segundo plano e com prioridade baixa.'**
  String get automixPreAnalyzeHint;

  /// No description provided for @analysisServer.
  ///
  /// In pt, this message translates to:
  /// **'Servidor de análise'**
  String get analysisServer;

  /// No description provided for @analysisServerOff.
  ///
  /// In pt, this message translates to:
  /// **'Desligado: o aparelho analisa as músicas'**
  String get analysisServerOff;

  /// No description provided for @analysisServerHint.
  ///
  /// In pt, this message translates to:
  /// **'Com o BK Analyzer rodando num computador, as análises do AutoMix vêm prontas de lá (modelo completo, mais músicas sincronizam) e o aparelho só decide a transição. Sem o servidor por perto, o aparelho analisa como antes.'**
  String get analysisServerHint;

  /// No description provided for @analysisServerSet.
  ///
  /// In pt, this message translates to:
  /// **'Configurar'**
  String get analysisServerSet;

  /// No description provided for @analysisServerAddress.
  ///
  /// In pt, this message translates to:
  /// **'Endereço do servidor de análise'**
  String get analysisServerAddress;

  /// No description provided for @analysisServerExample.
  ///
  /// In pt, this message translates to:
  /// **'ex.: http://192.168.1.10:4540, ou o link do portal (Tailscale)'**
  String get analysisServerExample;

  /// No description provided for @analysisServerPanel.
  ///
  /// In pt, this message translates to:
  /// **'Abrir painel'**
  String get analysisServerPanel;

  /// No description provided for @analysisServerTest.
  ///
  /// In pt, this message translates to:
  /// **'Testar'**
  String get analysisServerTest;

  /// No description provided for @analysisServerRemove.
  ///
  /// In pt, this message translates to:
  /// **'Desligar'**
  String get analysisServerRemove;

  /// No description provided for @analysisServerChange.
  ///
  /// In pt, this message translates to:
  /// **'Trocar endereço'**
  String get analysisServerChange;

  /// No description provided for @dlManagerTitle.
  ///
  /// In pt, this message translates to:
  /// **'Baixando'**
  String get dlManagerTitle;

  /// No description provided for @dlPaused.
  ///
  /// In pt, this message translates to:
  /// **'Downloads pausados'**
  String get dlPaused;

  /// No description provided for @dlAllDone.
  ///
  /// In pt, this message translates to:
  /// **'{count} músicas baixadas'**
  String dlAllDone(int count);

  /// No description provided for @dlProgress.
  ///
  /// In pt, this message translates to:
  /// **'{done} de {total} músicas'**
  String dlProgress(int done, int total);

  /// No description provided for @dlBytes.
  ///
  /// In pt, this message translates to:
  /// **'{done} de {total}'**
  String dlBytes(String done, String total);

  /// No description provided for @dlEta.
  ///
  /// In pt, this message translates to:
  /// **'faltam ~{time}'**
  String dlEta(String time);

  /// No description provided for @dlFailedCount.
  ///
  /// In pt, this message translates to:
  /// **'{count} falharam'**
  String dlFailedCount(int count);

  /// No description provided for @dlPause.
  ///
  /// In pt, this message translates to:
  /// **'Pausar'**
  String get dlPause;

  /// No description provided for @dlResume.
  ///
  /// In pt, this message translates to:
  /// **'Continuar'**
  String get dlResume;

  /// No description provided for @dlParallel.
  ///
  /// In pt, this message translates to:
  /// **'Ao mesmo tempo'**
  String get dlParallel;

  /// No description provided for @dlFewer.
  ///
  /// In pt, this message translates to:
  /// **'Menos'**
  String get dlFewer;

  /// No description provided for @dlMore.
  ///
  /// In pt, this message translates to:
  /// **'Mais'**
  String get dlMore;

  /// No description provided for @dlRetryFailed.
  ///
  /// In pt, this message translates to:
  /// **'Tentar de novo ({count})'**
  String dlRetryFailed(int count);

  /// No description provided for @dlClear.
  ///
  /// In pt, this message translates to:
  /// **'Limpar concluídas'**
  String get dlClear;

  /// No description provided for @dlMoreQueued.
  ///
  /// In pt, this message translates to:
  /// **'e mais {count} na fila'**
  String dlMoreQueued(int count);

  /// No description provided for @dlFailed.
  ///
  /// In pt, this message translates to:
  /// **'falhou'**
  String get dlFailed;

  /// No description provided for @dlQueued.
  ///
  /// In pt, this message translates to:
  /// **'na fila'**
  String get dlQueued;

  /// No description provided for @dlParallelSetting.
  ///
  /// In pt, this message translates to:
  /// **'Downloads ao mesmo tempo'**
  String get dlParallelSetting;

  /// No description provided for @dlParallelHint.
  ///
  /// In pt, this message translates to:
  /// **'Quantas músicas baixam juntas para ouvir offline. Mais é mais rápido numa conexão boa; menos deixa a rede livre para tocar.'**
  String get dlParallelHint;

  /// No description provided for @dlWifiOnly.
  ///
  /// In pt, this message translates to:
  /// **'Baixar só no Wi-Fi'**
  String get dlWifiOnly;

  /// No description provided for @dlWifiOnlyHint.
  ///
  /// In pt, this message translates to:
  /// **'Nos dados móveis, os downloads esperam o Wi-Fi'**
  String get dlWifiOnlyHint;

  /// No description provided for @dlWaitingWifi.
  ///
  /// In pt, this message translates to:
  /// **'Esperando o Wi-Fi'**
  String get dlWaitingWifi;

  /// No description provided for @analysisServerOk.
  ///
  /// In pt, this message translates to:
  /// **'Conectado · {done} de {total} músicas analisadas · trabalhadores ligados: {workers}'**
  String analysisServerOk(String done, String total, int workers);

  /// No description provided for @analysisServerLoginFail.
  ///
  /// In pt, this message translates to:
  /// **'O servidor de análise não aceitou o login desta conta (ele usa outro Navidrome?)'**
  String get analysisServerLoginFail;

  /// No description provided for @analysisServerViaPortal.
  ///
  /// In pt, this message translates to:
  /// **'Pelo portal: funciona fora de casa, e o endereço se atualiza sozinho quando o túnel muda.'**
  String get analysisServerViaPortal;

  /// No description provided for @analysisServerPortalFound.
  ///
  /// In pt, this message translates to:
  /// **'Portal encontrado: a análise do AutoMix passa a ir por ele'**
  String get analysisServerPortalFound;

  /// No description provided for @analysisServerUnreachable.
  ///
  /// In pt, this message translates to:
  /// **'Sem resposta do servidor de análise'**
  String get analysisServerUnreachable;

  /// No description provided for @analysisServerNotBk.
  ///
  /// In pt, this message translates to:
  /// **'Esse endereço não é de um BK Analyzer'**
  String get analysisServerNotBk;

  /// No description provided for @automixDefaults.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar padrões do AutoMix'**
  String get automixDefaults;

  /// No description provided for @analysisModel.
  ///
  /// In pt, this message translates to:
  /// **'Modelo de análise'**
  String get analysisModel;

  /// No description provided for @modelAuto.
  ///
  /// In pt, this message translates to:
  /// **'Automático'**
  String get modelAuto;

  /// No description provided for @modelSmall.
  ///
  /// In pt, this message translates to:
  /// **'Pequeno'**
  String get modelSmall;

  /// No description provided for @modelFull.
  ///
  /// In pt, this message translates to:
  /// **'Completo'**
  String get modelFull;

  /// No description provided for @noAvx2.
  ///
  /// In pt, this message translates to:
  /// **'sem AVX2'**
  String get noAvx2;

  /// No description provided for @modelDeviceInfo.
  ///
  /// In pt, this message translates to:
  /// **'Este aparelho: {cores} núcleos, {simd}. Recomendado: {recommended}. Em uso: {active}.'**
  String modelDeviceInfo(
    int cores,
    String simd,
    String recommended,
    String active,
  );

  /// No description provided for @modelHint.
  ///
  /// In pt, this message translates to:
  /// **'O pequeno (10 MB) é rápido e vem com o app. O completo (83 MB) é mais preciso e indicado para PCs fortes.'**
  String get modelHint;

  /// No description provided for @downloadFullModel.
  ///
  /// In pt, this message translates to:
  /// **'Baixar modelo completo (83 MB)'**
  String get downloadFullModel;

  /// No description provided for @modelDownloaded.
  ///
  /// In pt, this message translates to:
  /// **'Modelo completo baixado e ativado'**
  String get modelDownloaded;

  /// No description provided for @modelDownloadFailed.
  ///
  /// In pt, this message translates to:
  /// **'Falha ao baixar o modelo'**
  String get modelDownloadFailed;

  /// No description provided for @mixing.
  ///
  /// In pt, this message translates to:
  /// **'Mixando'**
  String get mixing;

  /// No description provided for @nextMix.
  ///
  /// In pt, this message translates to:
  /// **'Próxima transição'**
  String get nextMix;

  /// No description provided for @analyzedBpm.
  ///
  /// In pt, this message translates to:
  /// **'BPM analisado'**
  String get analyzedBpm;

  /// No description provided for @crossfadeAutomixNote.
  ///
  /// In pt, this message translates to:
  /// **'Com o AutoMix ligado, o crossfade só vale quando ele está desativado.'**
  String get crossfadeAutomixNote;

  /// No description provided for @radioOn.
  ///
  /// In pt, this message translates to:
  /// **'Rádio infinita ligada: a fila continua com músicas parecidas'**
  String get radioOn;

  /// No description provided for @radioOff.
  ///
  /// In pt, this message translates to:
  /// **'Ligar rádio infinita (completa a fila com músicas parecidas)'**
  String get radioOff;

  /// No description provided for @syncQueue.
  ///
  /// In pt, this message translates to:
  /// **'Sincronizar a fila com o servidor'**
  String get syncQueue;

  /// No description provided for @syncQueueHint.
  ///
  /// In pt, this message translates to:
  /// **'Salva a fila no servidor para continuar de onde parou em outro aparelho.'**
  String get syncQueueHint;

  /// No description provided for @equalizer.
  ///
  /// In pt, this message translates to:
  /// **'Equalizador'**
  String get equalizer;

  /// No description provided for @eqFlat.
  ///
  /// In pt, this message translates to:
  /// **'Plano'**
  String get eqFlat;

  /// No description provided for @eqBass.
  ///
  /// In pt, this message translates to:
  /// **'Graves'**
  String get eqBass;

  /// No description provided for @eqTreble.
  ///
  /// In pt, this message translates to:
  /// **'Agudos'**
  String get eqTreble;

  /// No description provided for @eqVocal.
  ///
  /// In pt, this message translates to:
  /// **'Vocal'**
  String get eqVocal;

  /// No description provided for @eqElectronic.
  ///
  /// In pt, this message translates to:
  /// **'Eletrônica'**
  String get eqElectronic;

  /// No description provided for @eqClassical.
  ///
  /// In pt, this message translates to:
  /// **'Clássica'**
  String get eqClassical;

  /// No description provided for @eqLoudness.
  ///
  /// In pt, this message translates to:
  /// **'Volume baixo'**
  String get eqLoudness;

  /// No description provided for @eqHeadphones.
  ///
  /// In pt, this message translates to:
  /// **'Fone de ouvido'**
  String get eqHeadphones;

  /// No description provided for @eqCustom.
  ///
  /// In pt, this message translates to:
  /// **'Personalizado'**
  String get eqCustom;

  /// No description provided for @eqHint.
  ///
  /// In pt, this message translates to:
  /// **'Se aumentar muitas bandas, reduza a pré-amplificação para evitar distorção.'**
  String get eqHint;

  /// No description provided for @openEqualizer.
  ///
  /// In pt, this message translates to:
  /// **'Abrir equalizador'**
  String get openEqualizer;

  /// No description provided for @on.
  ///
  /// In pt, this message translates to:
  /// **'Ligado'**
  String get on;

  /// No description provided for @off.
  ///
  /// In pt, this message translates to:
  /// **'Desligado'**
  String get off;

  /// No description provided for @customize.
  ///
  /// In pt, this message translates to:
  /// **'Personalizar'**
  String get customize;

  /// No description provided for @customizeHint.
  ///
  /// In pt, this message translates to:
  /// **'Tema, capas, tela tocando agora, layout, botões e perfis'**
  String get customizeHint;

  /// No description provided for @amoled.
  ///
  /// In pt, this message translates to:
  /// **'Preto puro (AMOLED)'**
  String get amoled;

  /// No description provided for @amoledHint.
  ///
  /// In pt, this message translates to:
  /// **'Fundo totalmente preto no tema escuro'**
  String get amoledHint;

  /// No description provided for @usePalette.
  ///
  /// In pt, this message translates to:
  /// **'Usar a paleta de cores'**
  String get usePalette;

  /// No description provided for @cornerRadius.
  ///
  /// In pt, this message translates to:
  /// **'Arredondamento dos cantos'**
  String get cornerRadius;

  /// No description provided for @density.
  ///
  /// In pt, this message translates to:
  /// **'Densidade'**
  String get density;

  /// No description provided for @densityCompact.
  ///
  /// In pt, this message translates to:
  /// **'Compacta'**
  String get densityCompact;

  /// No description provided for @densityStandard.
  ///
  /// In pt, this message translates to:
  /// **'Padrão'**
  String get densityStandard;

  /// No description provided for @densityComfortable.
  ///
  /// In pt, this message translates to:
  /// **'Confortável'**
  String get densityComfortable;

  /// No description provided for @nowPlaying.
  ///
  /// In pt, this message translates to:
  /// **'Tocando agora'**
  String get nowPlaying;

  /// No description provided for @coverShape.
  ///
  /// In pt, this message translates to:
  /// **'Formato das capas'**
  String get coverShape;

  /// No description provided for @shapeSquare.
  ///
  /// In pt, this message translates to:
  /// **'Quadrada'**
  String get shapeSquare;

  /// No description provided for @shapeRounded.
  ///
  /// In pt, this message translates to:
  /// **'Arredondada'**
  String get shapeRounded;

  /// No description provided for @shapeCircle.
  ///
  /// In pt, this message translates to:
  /// **'Redonda'**
  String get shapeCircle;

  /// No description provided for @nowPlayingLayout.
  ///
  /// In pt, this message translates to:
  /// **'Layout da tela tocando agora'**
  String get nowPlayingLayout;

  /// No description provided for @layoutSide.
  ///
  /// In pt, this message translates to:
  /// **'Capa + fila/letra'**
  String get layoutSide;

  /// No description provided for @layoutLyrics.
  ///
  /// In pt, this message translates to:
  /// **'Capa + letra'**
  String get layoutLyrics;

  /// No description provided for @layoutMinimal.
  ///
  /// In pt, this message translates to:
  /// **'Minimalista'**
  String get layoutMinimal;

  /// No description provided for @layoutVinyl.
  ///
  /// In pt, this message translates to:
  /// **'Vinil'**
  String get layoutVinyl;

  /// No description provided for @backgroundBlur.
  ///
  /// In pt, this message translates to:
  /// **'Fundo desfocado da capa'**
  String get backgroundBlur;

  /// No description provided for @layout.
  ///
  /// In pt, this message translates to:
  /// **'Layout'**
  String get layout;

  /// No description provided for @sidebar.
  ///
  /// In pt, this message translates to:
  /// **'Barra lateral'**
  String get sidebar;

  /// No description provided for @sidebarExpanded.
  ///
  /// In pt, this message translates to:
  /// **'Expandida'**
  String get sidebarExpanded;

  /// No description provided for @sidebarRail.
  ///
  /// In pt, this message translates to:
  /// **'Só ícones'**
  String get sidebarRail;

  /// No description provided for @cardSize.
  ///
  /// In pt, this message translates to:
  /// **'Tamanho dos cartões'**
  String get cardSize;

  /// No description provided for @sizeSmall.
  ///
  /// In pt, this message translates to:
  /// **'Pequeno'**
  String get sizeSmall;

  /// No description provided for @sizeMedium.
  ///
  /// In pt, this message translates to:
  /// **'Médio'**
  String get sizeMedium;

  /// No description provided for @sizeLarge.
  ///
  /// In pt, this message translates to:
  /// **'Grande'**
  String get sizeLarge;

  /// No description provided for @startPage.
  ///
  /// In pt, this message translates to:
  /// **'Página inicial'**
  String get startPage;

  /// No description provided for @showQueueOnStart.
  ///
  /// In pt, this message translates to:
  /// **'Abrir com a fila visível'**
  String get showQueueOnStart;

  /// No description provided for @playerBarButtons.
  ///
  /// In pt, this message translates to:
  /// **'Botões da barra do player (arraste para ordenar)'**
  String get playerBarButtons;

  /// No description provided for @homeSections.
  ///
  /// In pt, this message translates to:
  /// **'Seções do Início (arraste para ordenar)'**
  String get homeSections;

  /// No description provided for @behavior.
  ///
  /// In pt, this message translates to:
  /// **'Comportamento'**
  String get behavior;

  /// No description provided for @songTap.
  ///
  /// In pt, this message translates to:
  /// **'Ao clicar numa música'**
  String get songTap;

  /// No description provided for @tapPlayFromHere.
  ///
  /// In pt, this message translates to:
  /// **'Tocar a lista a partir dela'**
  String get tapPlayFromHere;

  /// No description provided for @tapPlayOne.
  ///
  /// In pt, this message translates to:
  /// **'Tocar só ela'**
  String get tapPlayOne;

  /// No description provided for @shortcuts.
  ///
  /// In pt, this message translates to:
  /// **'Atalhos de teclado'**
  String get shortcuts;

  /// No description provided for @shortcutsList.
  ///
  /// In pt, this message translates to:
  /// **'Espaço: tocar/pausar • Ctrl+→/←: próxima/anterior • Shift+→/←: ±10 s • Ctrl+F: buscar'**
  String get shortcutsList;

  /// No description provided for @profiles.
  ///
  /// In pt, this message translates to:
  /// **'Perfis visuais'**
  String get profiles;

  /// No description provided for @exportProfile.
  ///
  /// In pt, this message translates to:
  /// **'Exportar perfil'**
  String get exportProfile;

  /// No description provided for @exportProfileHint.
  ///
  /// In pt, this message translates to:
  /// **'Copia tema e layout como JSON (para guardar ou compartilhar)'**
  String get exportProfileHint;

  /// No description provided for @profileCopied.
  ///
  /// In pt, this message translates to:
  /// **'Perfil copiado para a área de transferência'**
  String get profileCopied;

  /// No description provided for @importProfile.
  ///
  /// In pt, this message translates to:
  /// **'Importar perfil'**
  String get importProfile;

  /// No description provided for @importProfileHint.
  ///
  /// In pt, this message translates to:
  /// **'Cola um perfil JSON copiado antes'**
  String get importProfileHint;

  /// No description provided for @profileImported.
  ///
  /// In pt, this message translates to:
  /// **'Perfil aplicado'**
  String get profileImported;

  /// No description provided for @profileInvalid.
  ///
  /// In pt, this message translates to:
  /// **'A área de transferência não tem um perfil válido'**
  String get profileInvalid;

  /// No description provided for @resetAppearance.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar aparência padrão'**
  String get resetAppearance;

  /// No description provided for @volume.
  ///
  /// In pt, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @trayIcon.
  ///
  /// In pt, this message translates to:
  /// **'Ícone na bandeja do sistema'**
  String get trayIcon;

  /// No description provided for @closeToTray.
  ///
  /// In pt, this message translates to:
  /// **'Fechar para a bandeja'**
  String get closeToTray;

  /// No description provided for @closeToTrayHint.
  ///
  /// In pt, this message translates to:
  /// **'Fechar a janela deixa a música tocando; sair pelo menu da bandeja.'**
  String get closeToTrayHint;

  /// No description provided for @miniPlayer.
  ///
  /// In pt, this message translates to:
  /// **'Mini player'**
  String get miniPlayer;

  /// No description provided for @expand.
  ///
  /// In pt, this message translates to:
  /// **'Expandir'**
  String get expand;

  /// No description provided for @downloadOffline.
  ///
  /// In pt, this message translates to:
  /// **'Baixar para ouvir offline'**
  String get downloadOffline;

  /// No description provided for @availableOffline.
  ///
  /// In pt, this message translates to:
  /// **'Disponível offline (toque para remover)'**
  String get availableOffline;

  /// No description provided for @downloadingCount.
  ///
  /// In pt, this message translates to:
  /// **'Baixando {done} de {total}'**
  String downloadingCount(int done, int total);

  /// No description provided for @removeOfflineQuestion.
  ///
  /// In pt, this message translates to:
  /// **'Remover das músicas baixadas?'**
  String get removeOfflineQuestion;

  /// No description provided for @downloads.
  ///
  /// In pt, this message translates to:
  /// **'Baixadas'**
  String get downloads;

  /// No description provided for @downloadsHint.
  ///
  /// In pt, this message translates to:
  /// **'Álbuns e playlists baixados tocam mesmo sem internet ou com o servidor desligado.'**
  String get downloadsHint;

  /// No description provided for @mixSynced.
  ///
  /// In pt, this message translates to:
  /// **'sincronizada'**
  String get mixSynced;

  /// No description provided for @mixSimple.
  ///
  /// In pt, this message translates to:
  /// **'simples'**
  String get mixSimple;

  /// No description provided for @automixOffTap.
  ///
  /// In pt, this message translates to:
  /// **'AutoMix desligado — clique para ligar'**
  String get automixOffTap;

  /// No description provided for @automixOnTap.
  ///
  /// In pt, this message translates to:
  /// **'Clique para desligar o AutoMix'**
  String get automixOnTap;

  /// No description provided for @automixOnWaiting.
  ///
  /// In pt, this message translates to:
  /// **'AutoMix ligado — analisando a próxima música'**
  String get automixOnWaiting;

  /// No description provided for @filterSongs.
  ///
  /// In pt, this message translates to:
  /// **'Filtrar por música, artista ou álbum'**
  String get filterSongs;

  /// No description provided for @devices.
  ///
  /// In pt, this message translates to:
  /// **'Aparelhos'**
  String get devices;

  /// No description provided for @localAddress.
  ///
  /// In pt, this message translates to:
  /// **'Endereço na rede de casa (opcional)'**
  String get localAddress;

  /// No description provided for @localAddressHint.
  ///
  /// In pt, this message translates to:
  /// **'Usado quando estiver na mesma rede do servidor: mais rápido. Fora de casa, vale o endereço principal.'**
  String get localAddressHint;

  /// No description provided for @localAddressNone.
  ///
  /// In pt, this message translates to:
  /// **'Não configurado'**
  String get localAddressNone;

  /// No description provided for @localAddressInUse.
  ///
  /// In pt, this message translates to:
  /// **'em uso agora'**
  String get localAddressInUse;

  /// No description provided for @localAddressAway.
  ///
  /// In pt, this message translates to:
  /// **'fora de alcance agora (usando o principal)'**
  String get localAddressAway;

  /// No description provided for @portal.
  ///
  /// In pt, this message translates to:
  /// **'Portal'**
  String get portal;

  /// No description provided for @portalHint.
  ///
  /// In pt, this message translates to:
  /// **'Um endereço fixo que diz onde o servidor está agora. Quando o endereço do servidor muda, o app descobre o novo sozinho.'**
  String get portalHint;

  /// No description provided for @portalNone.
  ///
  /// In pt, this message translates to:
  /// **'sem portal: o endereço do servidor é fixo'**
  String get portalNone;

  /// No description provided for @portalFingerprint.
  ///
  /// In pt, this message translates to:
  /// **'Impressão digital'**
  String get portalFingerprint;

  /// No description provided for @portalFingerprintHint.
  ///
  /// In pt, this message translates to:
  /// **'Confira com quem te passou o link. É o que garante que o servidor é o dele, e não o de outra pessoa.'**
  String get portalFingerprintHint;

  /// No description provided for @commands.
  ///
  /// In pt, this message translates to:
  /// **'Comandos'**
  String get commands;

  /// No description provided for @commandsHint.
  ///
  /// In pt, this message translates to:
  /// **'Regras do tipo \"quando acontecer isto, faça aquilo\". O app só volta a tocar o que ele mesmo pausou: se você pausou na mão, ele não sai tocando sozinho.'**
  String get commandsHint;

  /// No description provided for @commandsWhen.
  ///
  /// In pt, this message translates to:
  /// **'Quando acontecer'**
  String get commandsWhen;

  /// No description provided for @pauseOnVolumeZero.
  ///
  /// In pt, this message translates to:
  /// **'Volume no mínimo pausa'**
  String get pauseOnVolumeZero;

  /// No description provided for @pauseOnVolumeZeroHintMobile.
  ///
  /// In pt, this message translates to:
  /// **'Abaixar o volume do aparelho até o fim pausa; subir volta a tocar.'**
  String get pauseOnVolumeZeroHintMobile;

  /// No description provided for @pauseOnVolumeZeroHintDesktop.
  ///
  /// In pt, this message translates to:
  /// **'Zerar o volume do app pausa; subir volta a tocar.'**
  String get pauseOnVolumeZeroHintDesktop;

  /// No description provided for @pauseOnUnplug.
  ///
  /// In pt, this message translates to:
  /// **'Tirar o fone pausa'**
  String get pauseOnUnplug;

  /// No description provided for @pauseOnUnplugHint.
  ///
  /// In pt, this message translates to:
  /// **'Sem isso a música continuaria no alto-falante.'**
  String get pauseOnUnplugHint;

  /// No description provided for @commandsKeepOpen.
  ///
  /// In pt, this message translates to:
  /// **'Para o app não fechar sozinho'**
  String get commandsKeepOpen;

  /// No description provided for @keepAliveWhenPaused.
  ///
  /// In pt, this message translates to:
  /// **'Manter o app vivo quando pausado'**
  String get keepAliveWhenPaused;

  /// No description provided for @keepAliveWhenPausedHint.
  ///
  /// In pt, this message translates to:
  /// **'Desligado, o Android pode fechar o app enquanto ele está pausado, e você volta e perde a fila. Ligado, a notificação fica na barra. Vale ao abrir o app de novo.'**
  String get keepAliveWhenPausedHint;

  /// No description provided for @batteryUnrestricted.
  ///
  /// In pt, this message translates to:
  /// **'Bateria sem restrição'**
  String get batteryUnrestricted;

  /// No description provided for @batteryUnrestrictedOk.
  ///
  /// In pt, this message translates to:
  /// **'Liberado: o sistema não vai fechar o app em segundo plano.'**
  String get batteryUnrestrictedOk;

  /// No description provided for @batteryUnrestrictedBad.
  ///
  /// In pt, this message translates to:
  /// **'O sistema pode fechar o app em segundo plano para poupar bateria.'**
  String get batteryUnrestrictedBad;

  /// No description provided for @batteryUnrestrictedFix.
  ///
  /// In pt, this message translates to:
  /// **'Liberar'**
  String get batteryUnrestrictedFix;

  /// No description provided for @closeToTrayWarn.
  ///
  /// In pt, this message translates to:
  /// **'Fechar a janela encerra o app e a música para. Ligue \"fechar para a bandeja\" em Computador para ele só sumir da tela.'**
  String get closeToTrayWarn;

  /// No description provided for @trayGoneWarn.
  ///
  /// In pt, this message translates to:
  /// **'Cuidado: com o ícone da bandeja desligado e \"fechar para a bandeja\" ligado, o app some sem deixar como reabrir.'**
  String get trayGoneWarn;

  /// No description provided for @recommend.
  ///
  /// In pt, this message translates to:
  /// **'Recomendações'**
  String get recommend;

  /// No description provided for @recommendHint.
  ///
  /// In pt, this message translates to:
  /// **'Como o app escolhe as parecidas no mix instantâneo, no rádio e no AutoMix.'**
  String get recommendHint;

  /// No description provided for @recommendStyleSound.
  ///
  /// In pt, this message translates to:
  /// **'Parecida no som'**
  String get recommendStyleSound;

  /// No description provided for @recommendStyleSoundHint.
  ///
  /// In pt, this message translates to:
  /// **'O timbre e o arranjo. É o padrão.'**
  String get recommendStyleSoundHint;

  /// No description provided for @recommendStyleMood.
  ///
  /// In pt, this message translates to:
  /// **'Mesmo clima'**
  String get recommendStyleMood;

  /// No description provided for @recommendStyleMoodHint.
  ///
  /// In pt, this message translates to:
  /// **'Dançante, agressiva, feliz, festa, relaxada, triste.'**
  String get recommendStyleMoodHint;

  /// No description provided for @recommendStyleGenre.
  ///
  /// In pt, this message translates to:
  /// **'Mesmo estilo musical'**
  String get recommendStyleGenre;

  /// No description provided for @recommendStyleGenreHint.
  ///
  /// In pt, this message translates to:
  /// **'Os gêneros que a análise reconheceu na música.'**
  String get recommendStyleGenreHint;

  /// No description provided for @recommendStyleEra.
  ///
  /// In pt, this message translates to:
  /// **'Mesma época'**
  String get recommendStyleEra;

  /// No description provided for @recommendStyleEraHint.
  ///
  /// In pt, this message translates to:
  /// **'Anos próximos, com o som desempatando.'**
  String get recommendStyleEraHint;

  /// No description provided for @recommendStyleLyrics.
  ///
  /// In pt, this message translates to:
  /// **'Mesmo assunto'**
  String get recommendStyleLyrics;

  /// No description provided for @recommendStyleLyricsHint.
  ///
  /// In pt, this message translates to:
  /// **'Pelo que a letra fala.'**
  String get recommendStyleLyricsHint;

  /// No description provided for @recommendStyleMix.
  ///
  /// In pt, this message translates to:
  /// **'Combina pra emendar'**
  String get recommendStyleMix;

  /// No description provided for @recommendStyleMixHint.
  ///
  /// In pt, this message translates to:
  /// **'Andamento próximo e tom que casa, como os DJs fazem.'**
  String get recommendStyleMixHint;

  /// No description provided for @recommendStyleServer.
  ///
  /// In pt, this message translates to:
  /// **'Como o AudioMuse faz'**
  String get recommendStyleServer;

  /// No description provided for @recommendStyleServerHint.
  ///
  /// In pt, this message translates to:
  /// **'A mesma conta do servidor: três quartos letra, um quarto som.'**
  String get recommendStyleServerHint;

  /// No description provided for @recommendOffline.
  ///
  /// In pt, this message translates to:
  /// **'Guardar no aparelho (funciona sem internet)'**
  String get recommendOffline;

  /// No description provided for @recommendOfflineHint.
  ///
  /// In pt, this message translates to:
  /// **'Baixa uma vez o resultado da análise do AudioMuse. Depois as parecidas saem na hora, sem internet, e gastando menos bateria do que perguntar ao servidor.'**
  String get recommendOfflineHint;

  /// No description provided for @recommendReady.
  ///
  /// In pt, this message translates to:
  /// **'{n} músicas prontas no aparelho'**
  String recommendReady(int n);

  /// No description provided for @recommendDownloading.
  ///
  /// In pt, this message translates to:
  /// **'Baixando…'**
  String get recommendDownloading;

  /// No description provided for @recommendNoServer.
  ///
  /// In pt, this message translates to:
  /// **'Configure o servidor de análise acima para poder baixar.'**
  String get recommendNoServer;

  /// No description provided for @recommendUpdate.
  ///
  /// In pt, this message translates to:
  /// **'Procurar atualização'**
  String get recommendUpdate;

  /// No description provided for @localAddressOk.
  ///
  /// In pt, this message translates to:
  /// **'O endereço de casa respondeu e já está em uso'**
  String get localAddressOk;

  /// No description provided for @localAddressNotNow.
  ///
  /// In pt, this message translates to:
  /// **'Não respondeu agora; será usado quando você estiver em casa'**
  String get localAddressNotNow;

  /// No description provided for @save.
  ///
  /// In pt, this message translates to:
  /// **'Salvar'**
  String get save;

  /// No description provided for @remove.
  ///
  /// In pt, this message translates to:
  /// **'Remover'**
  String get remove;

  /// No description provided for @playOn.
  ///
  /// In pt, this message translates to:
  /// **'Tocar em'**
  String get playOn;

  /// No description provided for @thisDevice.
  ///
  /// In pt, this message translates to:
  /// **'Este aparelho'**
  String get thisDevice;

  /// No description provided for @devicePlaying.
  ///
  /// In pt, this message translates to:
  /// **'Tocando: {title}'**
  String devicePlaying(String title);

  /// No description provided for @devicePaused.
  ///
  /// In pt, this message translates to:
  /// **'Pausado: {title}'**
  String devicePaused(String title);

  /// No description provided for @deviceIdle.
  ///
  /// In pt, this message translates to:
  /// **'Parado'**
  String get deviceIdle;

  /// No description provided for @sleepTimer.
  ///
  /// In pt, this message translates to:
  /// **'Timer para dormir'**
  String get sleepTimer;

  /// No description provided for @sleepTimerHint.
  ///
  /// In pt, this message translates to:
  /// **'A música para sozinha; o volume abaixa aos poucos antes.'**
  String get sleepTimerHint;

  /// No description provided for @sleepTimerActive.
  ///
  /// In pt, this message translates to:
  /// **'Para em {time}'**
  String sleepTimerActive(String time);

  /// No description provided for @sleepTimerEndOfTrackActive.
  ///
  /// In pt, this message translates to:
  /// **'Para no fim desta música'**
  String get sleepTimerEndOfTrackActive;

  /// No description provided for @sleepTimerEndOfTrack.
  ///
  /// In pt, this message translates to:
  /// **'No fim desta música'**
  String get sleepTimerEndOfTrack;

  /// No description provided for @sleepTimerMinutes.
  ///
  /// In pt, this message translates to:
  /// **'{minutes} minutos'**
  String sleepTimerMinutes(int minutes);

  /// No description provided for @sleepTimerAdd10.
  ///
  /// In pt, this message translates to:
  /// **'Mais 10 minutos'**
  String get sleepTimerAdd10;

  /// No description provided for @sleepTimerOff.
  ///
  /// In pt, this message translates to:
  /// **'Desligar o timer'**
  String get sleepTimerOff;

  /// No description provided for @sleepTimerDone.
  ///
  /// In pt, this message translates to:
  /// **'Timer para dormir: música pausada'**
  String get sleepTimerDone;

  /// No description provided for @deviceOffline.
  ///
  /// In pt, this message translates to:
  /// **'Fora de alcance'**
  String get deviceOffline;

  /// No description provided for @deviceControlling.
  ///
  /// In pt, this message translates to:
  /// **'Controlando daqui'**
  String get deviceControlling;

  /// No description provided for @playingOn.
  ///
  /// In pt, this message translates to:
  /// **'Tocando em {device}'**
  String playingOn(String device);

  /// No description provided for @noDevicesFound.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum outro aparelho encontrado. Abra o BKmasterplayer no outro aparelho, com a mesma conta e na mesma rede.'**
  String get noDevicesFound;

  /// No description provided for @addDeviceByAddress.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar pelo endereço'**
  String get addDeviceByAddress;

  /// No description provided for @addDeviceHint.
  ///
  /// In pt, this message translates to:
  /// **'IP do aparelho (ex.: o do Tailscale, 100.x.y.z)'**
  String get addDeviceHint;

  /// No description provided for @deviceNotFound.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum BKmasterplayer desta conta respondeu nesse endereço'**
  String get deviceNotFound;

  /// No description provided for @connectFailed.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível conectar a {device}'**
  String connectFailed(String device);

  /// No description provided for @connectAuthFailed.
  ///
  /// In pt, this message translates to:
  /// **'{device} não provou ser da sua conta. Entre de novo na conta nos dois aparelhos.'**
  String connectAuthFailed(String device);

  /// No description provided for @connectNeedsLogin.
  ///
  /// In pt, this message translates to:
  /// **'Toque para ativar o Connect protegido neste aparelho (pede a senha da conta uma vez). Desde essa versão, a senha do servidor não passa mais de um aparelho para outro.'**
  String get connectNeedsLogin;

  /// No description provided for @deviceNeedsLogin.
  ///
  /// In pt, this message translates to:
  /// **'Precisa entrar de novo na conta'**
  String get deviceNeedsLogin;

  /// No description provided for @connectEnableTitle.
  ///
  /// In pt, this message translates to:
  /// **'Ativar o Connect protegido'**
  String get connectEnableTitle;

  /// No description provided for @connectPasswordHint.
  ///
  /// In pt, this message translates to:
  /// **'Senha da conta {user}. Ela não sai do aparelho: vira uma chave que só os aparelhos da sua conta têm. Faça o mesmo nos outros aparelhos.'**
  String connectPasswordHint(String user);

  /// No description provided for @connectEnabledNow.
  ///
  /// In pt, this message translates to:
  /// **'Connect protegido ativado neste aparelho'**
  String get connectEnabledNow;

  /// No description provided for @connectWrongPassword.
  ///
  /// In pt, this message translates to:
  /// **'A senha não confere com a da conta'**
  String get connectWrongPassword;

  /// No description provided for @connectSection.
  ///
  /// In pt, this message translates to:
  /// **'Outros aparelhos (Connect)'**
  String get connectSection;

  /// No description provided for @connectEnable.
  ///
  /// In pt, this message translates to:
  /// **'Tocar e controlar entre aparelhos'**
  String get connectEnable;

  /// No description provided for @connectEnableHint.
  ///
  /// In pt, this message translates to:
  /// **'Este aparelho aparece para os outros com a mesma conta e pode ser controlado por eles, como no Spotify Connect.'**
  String get connectEnableHint;

  /// No description provided for @deviceName.
  ///
  /// In pt, this message translates to:
  /// **'Nome deste aparelho'**
  String get deviceName;

  /// No description provided for @or.
  ///
  /// In pt, this message translates to:
  /// **'ou'**
  String get or;

  /// No description provided for @useLocalMusic.
  ///
  /// In pt, this message translates to:
  /// **'Usar só as músicas do aparelho'**
  String get useLocalMusic;

  /// No description provided for @useLocalMusicHint.
  ///
  /// In pt, this message translates to:
  /// **'Sem servidor: toca os arquivos de uma pasta deste aparelho. Dá para configurar as pastas depois, nos Ajustes.'**
  String get useLocalMusicHint;

  /// No description provided for @musicFolder.
  ///
  /// In pt, this message translates to:
  /// **'Pasta das músicas'**
  String get musicFolder;

  /// No description provided for @musicFolderHint.
  ///
  /// In pt, this message translates to:
  /// **'O BKmasterplayer lê as músicas desta pasta e das subpastas.'**
  String get musicFolderHint;

  /// No description provided for @chooseOtherFolder.
  ///
  /// In pt, this message translates to:
  /// **'Escolher outra'**
  String get chooseOtherFolder;

  /// No description provided for @useThisFolder.
  ///
  /// In pt, this message translates to:
  /// **'Usar esta pasta'**
  String get useThisFolder;

  /// No description provided for @musicPermissionDenied.
  ///
  /// In pt, this message translates to:
  /// **'Sem permissão para ler as músicas do aparelho. Libere em Configurações do Android → Apps → BKmasterplayer → Permissões.'**
  String get musicPermissionDenied;

  /// No description provided for @noLocalSongs.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma música encontrada nessa pasta.'**
  String get noLocalSongs;

  /// No description provided for @scanningMusic.
  ///
  /// In pt, this message translates to:
  /// **'Lendo as músicas… {count} arquivos'**
  String scanningMusic(int count);

  /// No description provided for @localSongCount.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =0{Nenhuma música} =1{1 música} other{{count} músicas}}'**
  String localSongCount(int count);

  /// No description provided for @addFolder.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar pasta'**
  String get addFolder;

  /// No description provided for @rescanLibrary.
  ///
  /// In pt, this message translates to:
  /// **'Atualizar a biblioteca'**
  String get rescanLibrary;

  /// No description provided for @lastFmKey.
  ///
  /// In pt, this message translates to:
  /// **'Chave da API do Last.fm'**
  String get lastFmKey;

  /// No description provided for @lastFmKeyHint.
  ///
  /// In pt, this message translates to:
  /// **'Não configurada: rádio e mix sem AudioMuse usam só o servidor'**
  String get lastFmKeyHint;

  /// No description provided for @lastFmKeySet.
  ///
  /// In pt, this message translates to:
  /// **'Configurada'**
  String get lastFmKeySet;

  /// No description provided for @lastFmKeyHelp.
  ///
  /// In pt, this message translates to:
  /// **'Grátis: crie em last.fm/api/account/create e copie a \"API key\".'**
  String get lastFmKeyHelp;

  /// No description provided for @lastFmKeyOk.
  ///
  /// In pt, this message translates to:
  /// **'Chave do Last.fm funcionando'**
  String get lastFmKeyOk;

  /// No description provided for @lastFmKeyBad.
  ///
  /// In pt, this message translates to:
  /// **'O Last.fm recusou essa chave (confira se copiou a API key certa)'**
  String get lastFmKeyBad;

  /// No description provided for @lastFmForRadio.
  ///
  /// In pt, this message translates to:
  /// **'Usar o Last.fm para músicas parecidas'**
  String get lastFmForRadio;

  /// No description provided for @lastFmForRadioHint.
  ///
  /// In pt, this message translates to:
  /// **'No mix instantâneo e na rádio, quando o servidor não tem o AudioMuse e nas músicas do aparelho.'**
  String get lastFmForRadioHint;

  /// No description provided for @jamRequestTitle.
  ///
  /// In pt, this message translates to:
  /// **'{name} quer entrar na sua Festa'**
  String jamRequestTitle(String name);

  /// No description provided for @jamRequestBody.
  ///
  /// In pt, this message translates to:
  /// **'Pedido {via}. Quem entra pode adicionar músicas e controlar o que toca.'**
  String jamRequestBody(String via);

  /// No description provided for @viaWifi.
  ///
  /// In pt, this message translates to:
  /// **'pelo Wi-Fi'**
  String get viaWifi;

  /// No description provided for @viaBluetooth.
  ///
  /// In pt, this message translates to:
  /// **'por Bluetooth'**
  String get viaBluetooth;

  /// No description provided for @jamAlwaysAccept.
  ///
  /// In pt, this message translates to:
  /// **'Aceitar sempre esta pessoa'**
  String get jamAlwaysAccept;

  /// No description provided for @accept.
  ///
  /// In pt, this message translates to:
  /// **'Aceitar'**
  String get accept;

  /// No description provided for @reject.
  ///
  /// In pt, this message translates to:
  /// **'Recusar'**
  String get reject;

  /// No description provided for @startJam.
  ///
  /// In pt, this message translates to:
  /// **'Começar uma Festa'**
  String get startJam;

  /// No description provided for @startJamHint.
  ///
  /// In pt, this message translates to:
  /// **'Quem estiver perto com o BKmasterplayer pode pedir para entrar, adicionar músicas e controlar. Você aprova cada pessoa.'**
  String get startJamHint;

  /// No description provided for @jamWaiting.
  ///
  /// In pt, this message translates to:
  /// **'Pedindo para entrar na Festa de {name}… Espere a pessoa aceitar.'**
  String jamWaiting(String name);

  /// No description provided for @jamRejected.
  ///
  /// In pt, this message translates to:
  /// **'O pedido não foi aceito.'**
  String get jamRejected;

  /// No description provided for @jamEnded.
  ///
  /// In pt, this message translates to:
  /// **'A Festa acabou.'**
  String get jamEnded;

  /// No description provided for @jamsNearby.
  ///
  /// In pt, this message translates to:
  /// **'Festas por perto'**
  String get jamsNearby;

  /// No description provided for @jamSearching.
  ///
  /// In pt, this message translates to:
  /// **'Procurando… Peça para quem está tocando abrir uma Festa no BKmasterplayer.'**
  String get jamSearching;

  /// No description provided for @jamOf.
  ///
  /// In pt, this message translates to:
  /// **'Festa de {name}'**
  String jamOf(String name);

  /// No description provided for @join.
  ///
  /// In pt, this message translates to:
  /// **'Entrar'**
  String get join;

  /// No description provided for @jamOpen.
  ///
  /// In pt, this message translates to:
  /// **'Sua Festa está aberta'**
  String get jamOpen;

  /// No description provided for @jamOpenHint.
  ///
  /// In pt, this message translates to:
  /// **'Aparece como \"{name}\" para quem está perto.'**
  String jamOpenHint(String name);

  /// No description provided for @endJam.
  ///
  /// In pt, this message translates to:
  /// **'Encerrar'**
  String get endJam;

  /// No description provided for @jamPeople.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =0{Ninguém na Festa} =1{1 pessoa na Festa} other{{count} pessoas na Festa}}'**
  String jamPeople(int count);

  /// No description provided for @jamNobodyYet.
  ///
  /// In pt, this message translates to:
  /// **'Quando alguém pedir para entrar, você vai ver o pedido aqui e num aviso.'**
  String get jamNobodyYet;

  /// No description provided for @leaveJam.
  ///
  /// In pt, this message translates to:
  /// **'Sair'**
  String get leaveJam;

  /// No description provided for @upNext.
  ///
  /// In pt, this message translates to:
  /// **'Próximas'**
  String get upNext;

  /// No description provided for @jamAdd.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar'**
  String get jamAdd;

  /// No description provided for @jamMine.
  ///
  /// In pt, this message translates to:
  /// **'Minhas'**
  String get jamMine;

  /// No description provided for @jamQueueEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Nada na fila ainda: adicione uma música.'**
  String get jamQueueEmpty;

  /// No description provided for @addedBy.
  ///
  /// In pt, this message translates to:
  /// **'por {name}'**
  String addedBy(String name);

  /// No description provided for @jamSearchHost.
  ///
  /// In pt, this message translates to:
  /// **'Buscar nas músicas da Festa'**
  String get jamSearchHost;

  /// No description provided for @jamAdded.
  ///
  /// In pt, this message translates to:
  /// **'\"{title}\" entrou na fila'**
  String jamAdded(String title);

  /// No description provided for @jamSendFile.
  ///
  /// In pt, this message translates to:
  /// **'Mandar um arquivo do aparelho'**
  String get jamSendFile;

  /// No description provided for @jamSendFileHint.
  ///
  /// In pt, this message translates to:
  /// **'Escolha uma música deste aparelho para tocar na Festa.'**
  String get jamSendFileHint;

  /// No description provided for @jamSearchMine.
  ///
  /// In pt, this message translates to:
  /// **'Buscar nas suas músicas para mandar'**
  String get jamSearchMine;

  /// No description provided for @jamSending.
  ///
  /// In pt, this message translates to:
  /// **'Mandando \"{title}\"…'**
  String jamSending(String title);

  /// No description provided for @jamSent.
  ///
  /// In pt, this message translates to:
  /// **'Na fila da Festa'**
  String get jamSent;

  /// No description provided for @jamSendFailed.
  ///
  /// In pt, this message translates to:
  /// **'Não deu para mandar'**
  String get jamSendFailed;

  /// No description provided for @jamInOne.
  ///
  /// In pt, this message translates to:
  /// **'Você está numa Festa'**
  String get jamInOne;

  /// No description provided for @jamMenuHint.
  ///
  /// In pt, this message translates to:
  /// **'Tocar junto com quem está perto'**
  String get jamMenuHint;

  /// No description provided for @jamAllowlist.
  ///
  /// In pt, this message translates to:
  /// **'Aceitos automaticamente na Festa'**
  String get jamAllowlist;

  /// No description provided for @jamAllowlistEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Ninguém: todo pedido espera você aceitar.'**
  String get jamAllowlistEmpty;

  /// No description provided for @jamAllowlistHint.
  ///
  /// In pt, this message translates to:
  /// **'Estas pessoas entram na sua Festa sem pedir. Toque no X para tirar.'**
  String get jamAllowlistHint;

  /// No description provided for @jamNearbyAlerts.
  ///
  /// In pt, this message translates to:
  /// **'Avisar quando houver uma Festa por perto'**
  String get jamNearbyAlerts;

  /// No description provided for @jamNearbyAlertsHint.
  ///
  /// In pt, this message translates to:
  /// **'Usa o Bluetooth em modo econômico, mesmo com o app fechado.'**
  String get jamNearbyAlertsHint;

  /// No description provided for @joinJamNoAccount.
  ///
  /// In pt, this message translates to:
  /// **'Entrar numa Festa por perto (sem conta)'**
  String get joinJamNoAccount;

  /// No description provided for @downloadAll.
  ///
  /// In pt, this message translates to:
  /// **'Baixar todas as músicas do servidor'**
  String get downloadAll;

  /// No description provided for @downloadAllHint.
  ///
  /// In pt, this message translates to:
  /// **'Para ouvir tudo sem internet. Ocupa bastante espaço.'**
  String get downloadAllHint;

  /// No description provided for @readingLibrary.
  ///
  /// In pt, this message translates to:
  /// **'Lendo a biblioteca… {count} músicas'**
  String readingLibrary(int count);

  /// No description provided for @downloadAllConfirm.
  ///
  /// In pt, this message translates to:
  /// **'Baixar {count} músicas (cerca de {size})? Elas ficam neste aparelho e tocam sem internet; dá para tirar depois em Downloads.'**
  String downloadAllConfirm(int count, String size);

  /// No description provided for @downloadAllMobileData.
  ///
  /// In pt, this message translates to:
  /// **'Você está nos dados móveis: é melhor baixar no Wi-Fi.'**
  String get downloadAllMobileData;

  /// No description provided for @wholeLibrary.
  ///
  /// In pt, this message translates to:
  /// **'Biblioteca inteira'**
  String get wholeLibrary;

  /// No description provided for @downloadNew.
  ///
  /// In pt, this message translates to:
  /// **'Baixar as novas'**
  String get downloadNew;

  /// No description provided for @download.
  ///
  /// In pt, this message translates to:
  /// **'Baixar'**
  String get download;

  /// No description provided for @onlineMeta.
  ///
  /// In pt, this message translates to:
  /// **'Letras e capas da internet'**
  String get onlineMeta;

  /// No description provided for @onlineLyrics.
  ///
  /// In pt, this message translates to:
  /// **'Buscar letras que faltam'**
  String get onlineLyrics;

  /// No description provided for @onlineLyricsHint.
  ///
  /// In pt, this message translates to:
  /// **'Quando o servidor ou o arquivo não tem a letra: LRCLIB (com letras sincronizadas) e, com a sua chave, Musixmatch. A fonte aparece embaixo da letra.'**
  String get onlineLyricsHint;

  /// No description provided for @musixmatchKey.
  ///
  /// In pt, this message translates to:
  /// **'Chave da API do Musixmatch'**
  String get musixmatchKey;

  /// No description provided for @musixmatchKeyHint.
  ///
  /// In pt, this message translates to:
  /// **'Opcional: sem ela, as letras vêm do LRCLIB.'**
  String get musixmatchKeyHint;

  /// No description provided for @musixmatchKeyHelp.
  ///
  /// In pt, this message translates to:
  /// **'Da conta de desenvolvedor em developer.musixmatch.com. Letra inteira exige um plano comercial da Musixmatch; o app mostra o aviso de direitos e faz o registro de exibição que os termos pedem. No plano gratuito (só parte da letra), o app usa as outras fontes.'**
  String get musixmatchKeyHelp;

  /// No description provided for @onlineCovers.
  ///
  /// In pt, this message translates to:
  /// **'Buscar capas que faltam'**
  String get onlineCovers;

  /// No description provided for @onlineCoversHint.
  ///
  /// In pt, this message translates to:
  /// **'Nas músicas do aparelho sem capa: procura o álbum no Cover Art Archive (MusicBrainz) e no Deezer.'**
  String get onlineCoversHint;

  /// No description provided for @djModeFrom.
  ///
  /// In pt, this message translates to:
  /// **'Modo DJ a partir desta música'**
  String get djModeFrom;

  /// No description provided for @djModeOn.
  ///
  /// In pt, this message translates to:
  /// **'Modo DJ ligado: o AudioMuse e o AutoMix escolhem a próxima pelo melhor encaixe (toque para desligar)'**
  String get djModeOn;

  /// No description provided for @djModeOff.
  ///
  /// In pt, this message translates to:
  /// **'Modo DJ: deixar o AudioMuse e o AutoMix escolherem as próximas'**
  String get djModeOff;

  /// No description provided for @settingsAccount.
  ///
  /// In pt, this message translates to:
  /// **'Conta e servidor'**
  String get settingsAccount;

  /// No description provided for @settingsLook.
  ///
  /// In pt, this message translates to:
  /// **'Personalização gráfica'**
  String get settingsLook;

  /// No description provided for @settingsLookHint.
  ///
  /// In pt, this message translates to:
  /// **'Temas, cores, fontes, fundo e estrutura das telas'**
  String get settingsLookHint;

  /// No description provided for @settingsStorage.
  ///
  /// In pt, this message translates to:
  /// **'Downloads e cache'**
  String get settingsStorage;

  /// No description provided for @settingsSources.
  ///
  /// In pt, this message translates to:
  /// **'Letras, capas e Last.fm'**
  String get settingsSources;

  /// No description provided for @settingsDevices.
  ///
  /// In pt, this message translates to:
  /// **'Aparelhos e Festa'**
  String get settingsDevices;

  /// No description provided for @language.
  ///
  /// In pt, this message translates to:
  /// **'Idioma'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In pt, this message translates to:
  /// **'Do sistema'**
  String get languageSystem;

  /// No description provided for @licenses.
  ///
  /// In pt, this message translates to:
  /// **'Licenças de código aberto'**
  String get licenses;

  /// No description provided for @appVersion.
  ///
  /// In pt, this message translates to:
  /// **'Versão {version}'**
  String appVersion(String version);

  /// No description provided for @diagnostics.
  ///
  /// In pt, this message translates to:
  /// **'Diagnóstico'**
  String get diagnostics;

  /// No description provided for @diagnosticsSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Erros registrados e o relatório para mandar junto com um problema'**
  String get diagnosticsSubtitle;

  /// No description provided for @diagnosticsHint.
  ///
  /// In pt, this message translates to:
  /// **'O app registra os erros que acontecem. Ao pedir ajuda com um problema, mande o relatório: ele não leva sua senha, tokens, o endereço do servidor nem o seu usuário.'**
  String get diagnosticsHint;

  /// No description provided for @diagnosticsErrors.
  ///
  /// In pt, this message translates to:
  /// **'{count, plural, =0{Nenhum erro nesta sessão} =1{1 erro nesta sessão} other{{count} erros nesta sessão}}'**
  String diagnosticsErrors(int count);

  /// No description provided for @diagnosticsCopy.
  ///
  /// In pt, this message translates to:
  /// **'Copiar relatório'**
  String get diagnosticsCopy;

  /// No description provided for @diagnosticsSave.
  ///
  /// In pt, this message translates to:
  /// **'Salvar relatório'**
  String get diagnosticsSave;

  /// No description provided for @diagnosticsClear.
  ///
  /// In pt, this message translates to:
  /// **'Limpar registro'**
  String get diagnosticsClear;

  /// No description provided for @diagnosticsCopied.
  ///
  /// In pt, this message translates to:
  /// **'Relatório copiado'**
  String get diagnosticsCopied;

  /// No description provided for @diagnosticsCleared.
  ///
  /// In pt, this message translates to:
  /// **'Registro limpo'**
  String get diagnosticsCleared;

  /// No description provided for @diagnosticsEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Nada registrado ainda.'**
  String get diagnosticsEmpty;

  /// No description provided for @startupFailed.
  ///
  /// In pt, this message translates to:
  /// **'O motor de áudio não iniciou'**
  String get startupFailed;

  /// No description provided for @startupFailedHint.
  ///
  /// In pt, this message translates to:
  /// **'Feche e abra o app de novo. Se continuar, copie o relatório abaixo e mande junto com o problema.'**
  String get startupFailedHint;

  /// No description provided for @fontCredits.
  ///
  /// In pt, this message translates to:
  /// **'Fontes dos temas: Nunito, Space Grotesk, JetBrains Mono, Playfair Display e Bebas Neue (SIL Open Font License).'**
  String get fontCredits;

  /// No description provided for @openDownloads.
  ///
  /// In pt, this message translates to:
  /// **'Abrir os downloads'**
  String get openDownloads;

  /// No description provided for @openDownloadsHint.
  ///
  /// In pt, this message translates to:
  /// **'Álbuns, playlists e a biblioteca inteira para ouvir sem internet'**
  String get openDownloadsHint;

  /// No description provided for @lookColors.
  ///
  /// In pt, this message translates to:
  /// **'Cores'**
  String get lookColors;

  /// No description provided for @lookFonts.
  ///
  /// In pt, this message translates to:
  /// **'Fontes'**
  String get lookFonts;

  /// No description provided for @lookShapes.
  ///
  /// In pt, this message translates to:
  /// **'Formas e tamanhos'**
  String get lookShapes;

  /// No description provided for @lookBackground.
  ///
  /// In pt, this message translates to:
  /// **'Fundo'**
  String get lookBackground;

  /// No description provided for @lookStructure.
  ///
  /// In pt, this message translates to:
  /// **'Estrutura das telas'**
  String get lookStructure;

  /// No description provided for @lookMotion.
  ///
  /// In pt, this message translates to:
  /// **'Animações'**
  String get lookMotion;

  /// No description provided for @lookEditHint.
  ///
  /// In pt, this message translates to:
  /// **'Tudo muda na hora; o próprio app é a prévia.'**
  String get lookEditHint;

  /// No description provided for @original.
  ///
  /// In pt, this message translates to:
  /// **'original'**
  String get original;

  /// No description provided for @colorSource.
  ///
  /// In pt, this message translates to:
  /// **'Cor do app'**
  String get colorSource;

  /// No description provided for @colorFromCover.
  ///
  /// In pt, this message translates to:
  /// **'Da capa que toca (original)'**
  String get colorFromCover;

  /// No description provided for @colorFixed.
  ///
  /// In pt, this message translates to:
  /// **'Cor fixa'**
  String get colorFixed;

  /// No description provided for @baseColor.
  ///
  /// In pt, this message translates to:
  /// **'Cor base'**
  String get baseColor;

  /// No description provided for @baseColorHint.
  ///
  /// In pt, this message translates to:
  /// **'Com a cor da capa, é a usada quando nada está tocando.'**
  String get baseColorHint;

  /// No description provided for @pickColor.
  ///
  /// In pt, this message translates to:
  /// **'Escolher cor…'**
  String get pickColor;

  /// No description provided for @colorHex.
  ///
  /// In pt, this message translates to:
  /// **'Código'**
  String get colorHex;

  /// No description provided for @hue.
  ///
  /// In pt, this message translates to:
  /// **'Matiz'**
  String get hue;

  /// No description provided for @saturation.
  ///
  /// In pt, this message translates to:
  /// **'Saturação'**
  String get saturation;

  /// No description provided for @brightness.
  ///
  /// In pt, this message translates to:
  /// **'Brilho'**
  String get brightness;

  /// No description provided for @useThis.
  ///
  /// In pt, this message translates to:
  /// **'Usar'**
  String get useThis;

  /// No description provided for @paletteStyle.
  ///
  /// In pt, this message translates to:
  /// **'Estilo da paleta'**
  String get paletteStyle;

  /// No description provided for @variantTonalSpot.
  ///
  /// In pt, this message translates to:
  /// **'Tonal (original)'**
  String get variantTonalSpot;

  /// No description provided for @variantFidelity.
  ///
  /// In pt, this message translates to:
  /// **'Fiel à cor'**
  String get variantFidelity;

  /// No description provided for @variantMonochrome.
  ///
  /// In pt, this message translates to:
  /// **'Monocromática'**
  String get variantMonochrome;

  /// No description provided for @variantNeutral.
  ///
  /// In pt, this message translates to:
  /// **'Neutra'**
  String get variantNeutral;

  /// No description provided for @variantVibrant.
  ///
  /// In pt, this message translates to:
  /// **'Vibrante'**
  String get variantVibrant;

  /// No description provided for @variantExpressive.
  ///
  /// In pt, this message translates to:
  /// **'Expressiva'**
  String get variantExpressive;

  /// No description provided for @variantContent.
  ///
  /// In pt, this message translates to:
  /// **'Conteúdo'**
  String get variantContent;

  /// No description provided for @variantRainbow.
  ///
  /// In pt, this message translates to:
  /// **'Arco-íris'**
  String get variantRainbow;

  /// No description provided for @variantFruitSalad.
  ///
  /// In pt, this message translates to:
  /// **'Salada de frutas'**
  String get variantFruitSalad;

  /// No description provided for @contrast.
  ///
  /// In pt, this message translates to:
  /// **'Contraste'**
  String get contrast;

  /// No description provided for @contrastSoft.
  ///
  /// In pt, this message translates to:
  /// **'Suave'**
  String get contrastSoft;

  /// No description provided for @contrastStandard.
  ///
  /// In pt, this message translates to:
  /// **'Padrão'**
  String get contrastStandard;

  /// No description provided for @contrastMax.
  ///
  /// In pt, this message translates to:
  /// **'Máximo'**
  String get contrastMax;

  /// No description provided for @manualColors.
  ///
  /// In pt, this message translates to:
  /// **'Cores à mão'**
  String get manualColors;

  /// No description provided for @manualColorsHint.
  ///
  /// In pt, this message translates to:
  /// **'Trocam a cor calculada. O × volta ao automático.'**
  String get manualColorsHint;

  /// No description provided for @colorPrimary.
  ///
  /// In pt, this message translates to:
  /// **'Principal'**
  String get colorPrimary;

  /// No description provided for @colorSecondary.
  ///
  /// In pt, this message translates to:
  /// **'Secundária'**
  String get colorSecondary;

  /// No description provided for @colorTertiary.
  ///
  /// In pt, this message translates to:
  /// **'Terciária'**
  String get colorTertiary;

  /// No description provided for @colorBackground.
  ///
  /// In pt, this message translates to:
  /// **'Fundo'**
  String get colorBackground;

  /// No description provided for @colorText.
  ///
  /// In pt, this message translates to:
  /// **'Texto'**
  String get colorText;

  /// No description provided for @automatic.
  ///
  /// In pt, this message translates to:
  /// **'Automática'**
  String get automatic;

  /// No description provided for @fontTitles.
  ///
  /// In pt, this message translates to:
  /// **'Títulos'**
  String get fontTitles;

  /// No description provided for @fontBody.
  ///
  /// In pt, this message translates to:
  /// **'Texto'**
  String get fontBody;

  /// No description provided for @fontSystem.
  ///
  /// In pt, this message translates to:
  /// **'Do sistema (original)'**
  String get fontSystem;

  /// No description provided for @fontSample.
  ///
  /// In pt, this message translates to:
  /// **'A música certa, na hora certa'**
  String get fontSample;

  /// No description provided for @buttons.
  ///
  /// In pt, this message translates to:
  /// **'Botões'**
  String get buttons;

  /// No description provided for @buttonFilled.
  ///
  /// In pt, this message translates to:
  /// **'Cheio (original)'**
  String get buttonFilled;

  /// No description provided for @buttonTonal.
  ///
  /// In pt, this message translates to:
  /// **'Suave'**
  String get buttonTonal;

  /// No description provided for @buttonOutlined.
  ///
  /// In pt, this message translates to:
  /// **'Contorno'**
  String get buttonOutlined;

  /// No description provided for @cards.
  ///
  /// In pt, this message translates to:
  /// **'Cartões'**
  String get cards;

  /// No description provided for @cardFlat.
  ///
  /// In pt, this message translates to:
  /// **'Liso (original)'**
  String get cardFlat;

  /// No description provided for @cardElevated.
  ///
  /// In pt, this message translates to:
  /// **'Com sombra'**
  String get cardElevated;

  /// No description provided for @cardOutlined.
  ///
  /// In pt, this message translates to:
  /// **'Contorno'**
  String get cardOutlined;

  /// No description provided for @preview.
  ///
  /// In pt, this message translates to:
  /// **'Prévia'**
  String get preview;

  /// No description provided for @backgroundStyle.
  ///
  /// In pt, this message translates to:
  /// **'Fundo das telas'**
  String get backgroundStyle;

  /// No description provided for @bgSolid.
  ///
  /// In pt, this message translates to:
  /// **'Liso (original)'**
  String get bgSolid;

  /// No description provided for @bgGradient.
  ///
  /// In pt, this message translates to:
  /// **'Gradiente'**
  String get bgGradient;

  /// No description provided for @bgCover.
  ///
  /// In pt, this message translates to:
  /// **'Capa desfocada'**
  String get bgCover;

  /// No description provided for @bgImage.
  ///
  /// In pt, this message translates to:
  /// **'Imagem'**
  String get bgImage;

  /// No description provided for @chooseImage.
  ///
  /// In pt, this message translates to:
  /// **'Escolher imagem…'**
  String get chooseImage;

  /// No description provided for @imageTooBig.
  ///
  /// In pt, this message translates to:
  /// **'Imagem grande demais (máximo 12 MB)'**
  String get imageTooBig;

  /// No description provided for @backgroundDim.
  ///
  /// In pt, this message translates to:
  /// **'Cor do tema por cima'**
  String get backgroundDim;

  /// No description provided for @backgroundDimHint.
  ///
  /// In pt, this message translates to:
  /// **'Mais alto deixa o texto mais legível.'**
  String get backgroundDimHint;

  /// No description provided for @sidebarTabs.
  ///
  /// In pt, this message translates to:
  /// **'Abas da barra lateral'**
  String get sidebarTabs;

  /// No description provided for @sidebarTabsHint.
  ///
  /// In pt, this message translates to:
  /// **'Computador e tablet. Arraste para mudar a ordem.'**
  String get sidebarTabsHint;

  /// No description provided for @mobileTabs.
  ///
  /// In pt, this message translates to:
  /// **'Abas do celular'**
  String get mobileTabs;

  /// No description provided for @mobileTabsHint.
  ///
  /// In pt, this message translates to:
  /// **'De 2 a 4, além de Ajustes (sempre no fim). Arraste para mudar a ordem.'**
  String get mobileTabsHint;

  /// No description provided for @mobileTabsLimit.
  ///
  /// In pt, this message translates to:
  /// **'O celular comporta de 2 a 4 abas, além de Ajustes'**
  String get mobileTabsLimit;

  /// No description provided for @navLabels.
  ///
  /// In pt, this message translates to:
  /// **'Nome das abas'**
  String get navLabels;

  /// No description provided for @labelsAuto.
  ///
  /// In pt, this message translates to:
  /// **'Automático (original)'**
  String get labelsAuto;

  /// No description provided for @labelsAll.
  ///
  /// In pt, this message translates to:
  /// **'Sempre'**
  String get labelsAll;

  /// No description provided for @labelsSelected.
  ///
  /// In pt, this message translates to:
  /// **'Só a aberta'**
  String get labelsSelected;

  /// No description provided for @labelsNone.
  ///
  /// In pt, this message translates to:
  /// **'Nunca'**
  String get labelsNone;

  /// No description provided for @playerStyle.
  ///
  /// In pt, this message translates to:
  /// **'Barra do player'**
  String get playerStyle;

  /// No description provided for @playerDocked.
  ///
  /// In pt, this message translates to:
  /// **'Grudada (original)'**
  String get playerDocked;

  /// No description provided for @playerFloating.
  ///
  /// In pt, this message translates to:
  /// **'Flutuante'**
  String get playerFloating;

  /// No description provided for @transitions.
  ///
  /// In pt, this message translates to:
  /// **'Troca de telas'**
  String get transitions;

  /// No description provided for @transDefault.
  ///
  /// In pt, this message translates to:
  /// **'Padrão (original)'**
  String get transDefault;

  /// No description provided for @transFade.
  ///
  /// In pt, this message translates to:
  /// **'Esmaecer'**
  String get transFade;

  /// No description provided for @transSlide.
  ///
  /// In pt, this message translates to:
  /// **'Deslizar'**
  String get transSlide;

  /// No description provided for @transNone.
  ///
  /// In pt, this message translates to:
  /// **'Sem animação'**
  String get transNone;

  /// No description provided for @animSpeed.
  ///
  /// In pt, this message translates to:
  /// **'Animações'**
  String get animSpeed;

  /// No description provided for @animNormal.
  ///
  /// In pt, this message translates to:
  /// **'Normais (original)'**
  String get animNormal;

  /// No description provided for @animFast.
  ///
  /// In pt, this message translates to:
  /// **'Rápidas'**
  String get animFast;

  /// No description provided for @animOff.
  ///
  /// In pt, this message translates to:
  /// **'Desligadas'**
  String get animOff;

  /// No description provided for @themes.
  ///
  /// In pt, this message translates to:
  /// **'Temas'**
  String get themes;

  /// No description provided for @themesHint.
  ///
  /// In pt, this message translates to:
  /// **'Toque para aplicar; segure (ou ⋮) para mais opções.'**
  String get themesHint;

  /// No description provided for @themeOriginal.
  ///
  /// In pt, this message translates to:
  /// **'BKmasterplayer (original)'**
  String get themeOriginal;

  /// No description provided for @themeVinyl.
  ///
  /// In pt, this message translates to:
  /// **'Vinil'**
  String get themeVinyl;

  /// No description provided for @themePaper.
  ///
  /// In pt, this message translates to:
  /// **'Papel'**
  String get themePaper;

  /// No description provided for @themeContrast.
  ///
  /// In pt, this message translates to:
  /// **'Alto contraste'**
  String get themeContrast;

  /// No description provided for @themeAuto.
  ///
  /// In pt, this message translates to:
  /// **'Automático'**
  String get themeAuto;

  /// No description provided for @themeModified.
  ///
  /// In pt, this message translates to:
  /// **'modificado'**
  String get themeModified;

  /// No description provided for @saveAsTheme.
  ///
  /// In pt, this message translates to:
  /// **'Salvar o visual atual como tema'**
  String get saveAsTheme;

  /// No description provided for @themeName.
  ///
  /// In pt, this message translates to:
  /// **'Nome do tema'**
  String get themeName;

  /// No description provided for @myTheme.
  ///
  /// In pt, this message translates to:
  /// **'Meu tema'**
  String get myTheme;

  /// No description provided for @themeSaved.
  ///
  /// In pt, this message translates to:
  /// **'Tema \"{name}\" salvo'**
  String themeSaved(String name);

  /// No description provided for @applyTheme.
  ///
  /// In pt, this message translates to:
  /// **'Aplicar'**
  String get applyTheme;

  /// No description provided for @duplicate.
  ///
  /// In pt, this message translates to:
  /// **'Duplicar'**
  String get duplicate;

  /// No description provided for @copyOf.
  ///
  /// In pt, this message translates to:
  /// **'{name} (cópia)'**
  String copyOf(String name);

  /// No description provided for @saveChangesHere.
  ///
  /// In pt, this message translates to:
  /// **'Salvar as mudanças neste tema'**
  String get saveChangesHere;

  /// No description provided for @exportThemeFile.
  ///
  /// In pt, this message translates to:
  /// **'Exportar arquivo'**
  String get exportThemeFile;

  /// No description provided for @importTheme.
  ///
  /// In pt, this message translates to:
  /// **'Importar tema (arquivo)'**
  String get importTheme;

  /// No description provided for @themeImported.
  ///
  /// In pt, this message translates to:
  /// **'Tema \"{name}\" importado e aplicado'**
  String themeImported(String name);

  /// No description provided for @backupFiles.
  ///
  /// In pt, this message translates to:
  /// **'Backup e arquivos'**
  String get backupFiles;

  /// No description provided for @exportBackup.
  ///
  /// In pt, this message translates to:
  /// **'Exportar backup completo'**
  String get exportBackup;

  /// No description provided for @exportBackupHint.
  ///
  /// In pt, this message translates to:
  /// **'Todos os seus temas e o visual atual num arquivo'**
  String get exportBackupHint;

  /// No description provided for @restoreBackup.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar backup (arquivo)'**
  String get restoreBackup;

  /// No description provided for @restoreBackupConfirm.
  ///
  /// In pt, this message translates to:
  /// **'Trocar seus temas e o visual atual pelos do backup? O estado de agora fica guardado nos backups automáticos.'**
  String get restoreBackupConfirm;

  /// No description provided for @restore.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar'**
  String get restore;

  /// No description provided for @backupRestored.
  ///
  /// In pt, this message translates to:
  /// **'Backup restaurado'**
  String get backupRestored;

  /// No description provided for @autoBackups.
  ///
  /// In pt, this message translates to:
  /// **'Backups automáticos'**
  String get autoBackups;

  /// No description provided for @autoBackupsHint.
  ///
  /// In pt, this message translates to:
  /// **'Feitos antes de cada troca grande (os 10 últimos)'**
  String get autoBackupsHint;

  /// No description provided for @noAutoBackups.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum ainda: aparecem quando você troca de tema com mudanças não salvas, importa ou restaura.'**
  String get noAutoBackups;

  /// No description provided for @fileSaved.
  ///
  /// In pt, this message translates to:
  /// **'Arquivo salvo'**
  String get fileSaved;

  /// No description provided for @invalidThemeFile.
  ///
  /// In pt, this message translates to:
  /// **'Arquivo inválido: não é um tema ou backup do BKmasterplayer'**
  String get invalidThemeFile;

  /// No description provided for @textProfiles.
  ///
  /// In pt, this message translates to:
  /// **'Como texto (área de transferência)'**
  String get textProfiles;

  /// No description provided for @deleteThemeConfirm.
  ///
  /// In pt, this message translates to:
  /// **'Excluir o tema \"{name}\"?'**
  String deleteThemeConfirm(String name);

  /// No description provided for @backToOriginal.
  ///
  /// In pt, this message translates to:
  /// **'Voltar à aparência original'**
  String get backToOriginal;

  /// No description provided for @backToOriginalHint.
  ///
  /// In pt, this message translates to:
  /// **'O tema BKmasterplayer, como o app vem (o visual de agora fica nos backups automáticos se não estiver salvo).'**
  String get backToOriginalHint;

  /// No description provided for @party.
  ///
  /// In pt, this message translates to:
  /// **'Festa'**
  String get party;

  /// No description provided for @lyricsSource.
  ///
  /// In pt, this message translates to:
  /// **'Letra: {source}'**
  String lyricsSource(String source);

  /// No description provided for @lastFmCredit.
  ///
  /// In pt, this message translates to:
  /// **'Dados do Last.fm'**
  String get lastFmCredit;

  /// No description provided for @lastFmCreditHint.
  ///
  /// In pt, this message translates to:
  /// **'Músicas e artistas parecidos, mais tocadas e biografias vêm do Last.fm. Toque para abrir o site.'**
  String get lastFmCreditHint;

  /// No description provided for @openOnLastFm.
  ///
  /// In pt, this message translates to:
  /// **'Ver no Last.fm'**
  String get openOnLastFm;

  /// No description provided for @automixStatus.
  ///
  /// In pt, this message translates to:
  /// **'Estado do AutoMix'**
  String get automixStatus;

  /// No description provided for @automixTapStatus.
  ///
  /// In pt, this message translates to:
  /// **'Toque para ver o estado do AutoMix'**
  String get automixTapStatus;

  /// No description provided for @mixNowPlaying.
  ///
  /// In pt, this message translates to:
  /// **'Tocando agora'**
  String get mixNowPlaying;

  /// No description provided for @mixUpNext.
  ///
  /// In pt, this message translates to:
  /// **'Próxima'**
  String get mixUpNext;

  /// No description provided for @mixNoNext.
  ///
  /// In pt, this message translates to:
  /// **'Sem próxima música na fila'**
  String get mixNoNext;

  /// No description provided for @mixAnalyzing.
  ///
  /// In pt, this message translates to:
  /// **'Analisando…'**
  String get mixAnalyzing;

  /// No description provided for @beatReliable.
  ///
  /// In pt, this message translates to:
  /// **'batida confiável'**
  String get beatReliable;

  /// No description provided for @beatUnreliable.
  ///
  /// In pt, this message translates to:
  /// **'batida não confiável'**
  String get beatUnreliable;

  /// No description provided for @automixWaitingAnalysis.
  ///
  /// In pt, this message translates to:
  /// **'Esperando as análises das duas músicas para planejar a transição.'**
  String get automixWaitingAnalysis;

  /// No description provided for @automixOffStatus.
  ///
  /// In pt, this message translates to:
  /// **'Desligado: as músicas trocam do jeito normal (crossfade ou sem pausa).'**
  String get automixOffStatus;

  /// No description provided for @automixSettingsLink.
  ///
  /// In pt, this message translates to:
  /// **'Ajustes do AutoMix'**
  String get automixSettingsLink;

  /// No description provided for @automixUnreliableHelp.
  ///
  /// In pt, this message translates to:
  /// **'Para sincronizar, as batidas precisam cair numa grade fixa (±10 ms) em boa parte do trecho. Música tocada ao vivo, com andamento que varia, costuma não passar; aí a transição fica simples.'**
  String get automixUnreliableHelp;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
