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
  /// **'Player de Música'**
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
  /// **'Faixas seguidas do mesmo álbum tocam sem pausa, sem mixar.'**
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
