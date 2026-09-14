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
  /// **'BKplayer 🎵'**
  String get appTitle;

  /// No description provided for @about.
  ///
  /// In pt, this message translates to:
  /// **'Sobre'**
  String get about;

  /// No description provided for @aboutText.
  ///
  /// In pt, this message translates to:
  /// **'Player open source para servidores OpenSubsonic (Navidrome), com AudioMuse-AI e AutoMix. Licença GPL-3.0.'**
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
  /// **'Nenhum outro aparelho encontrado. Abra o BKplayer no outro aparelho, com a mesma conta e na mesma rede.'**
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
  /// **'Nenhum BKplayer desta conta respondeu nesse endereço'**
  String get deviceNotFound;

  /// No description provided for @connectFailed.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível conectar a {device}'**
  String connectFailed(String device);

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
  /// **'O BKplayer lê as músicas desta pasta e das subpastas.'**
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
  /// **'Sem permissão para ler as músicas do aparelho. Libere em Configurações do Android → Apps → BKplayer → Permissões.'**
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
  /// **'{name} quer entrar na sua Jam'**
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
  /// **'Começar uma Jam'**
  String get startJam;

  /// No description provided for @startJamHint.
  ///
  /// In pt, this message translates to:
  /// **'Quem estiver perto com o BKplayer pode pedir para entrar, adicionar músicas e controlar. Você aprova cada pessoa.'**
  String get startJamHint;

  /// No description provided for @jamWaiting.
  ///
  /// In pt, this message translates to:
  /// **'Pedindo para entrar na Jam de {name}… Espere a pessoa aceitar.'**
  String jamWaiting(String name);

  /// No description provided for @jamRejected.
  ///
  /// In pt, this message translates to:
  /// **'O pedido não foi aceito.'**
  String get jamRejected;

  /// No description provided for @jamEnded.
  ///
  /// In pt, this message translates to:
  /// **'A Jam acabou.'**
  String get jamEnded;

  /// No description provided for @jamsNearby.
  ///
  /// In pt, this message translates to:
  /// **'Jams por perto'**
  String get jamsNearby;

  /// No description provided for @jamSearching.
  ///
  /// In pt, this message translates to:
  /// **'Procurando… Peça para quem está tocando abrir uma Jam no BKplayer.'**
  String get jamSearching;

  /// No description provided for @jamOf.
  ///
  /// In pt, this message translates to:
  /// **'Jam de {name}'**
  String jamOf(String name);

  /// No description provided for @join.
  ///
  /// In pt, this message translates to:
  /// **'Entrar'**
  String get join;

  /// No description provided for @jamOpen.
  ///
  /// In pt, this message translates to:
  /// **'Sua Jam está aberta'**
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
  /// **'{count, plural, =0{Ninguém na Jam} =1{1 pessoa na Jam} other{{count} pessoas na Jam}}'**
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
  /// **'Buscar nas músicas da Jam'**
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
  /// **'Escolha uma música deste aparelho para tocar na Jam.'**
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
  /// **'Na fila da Jam'**
  String get jamSent;

  /// No description provided for @jamSendFailed.
  ///
  /// In pt, this message translates to:
  /// **'Não deu para mandar'**
  String get jamSendFailed;

  /// No description provided for @jamInOne.
  ///
  /// In pt, this message translates to:
  /// **'Você está numa Jam'**
  String get jamInOne;

  /// No description provided for @jamMenuHint.
  ///
  /// In pt, this message translates to:
  /// **'Tocar junto com quem está perto'**
  String get jamMenuHint;

  /// No description provided for @jamAllowlist.
  ///
  /// In pt, this message translates to:
  /// **'Aceitos automaticamente na Jam'**
  String get jamAllowlist;

  /// No description provided for @jamAllowlistEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Ninguém: todo pedido espera você aceitar.'**
  String get jamAllowlistEmpty;

  /// No description provided for @jamAllowlistHint.
  ///
  /// In pt, this message translates to:
  /// **'Estas pessoas entram na sua Jam sem pedir. Toque no X para tirar.'**
  String get jamAllowlistHint;
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
