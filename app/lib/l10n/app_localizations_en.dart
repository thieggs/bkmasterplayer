// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'BKmasterplayer 🎵';

  @override
  String get about => 'About';

  @override
  String get aboutText =>
      'Open source player for OpenSubsonic servers (Navidrome), with AudioMuse-AI and AutoMix. MIT license.';

  @override
  String get accentColor => 'Accent color';

  @override
  String get addedToPlaylist => 'Added to playlist';

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String get shareLink => 'Share link';

  @override
  String shareLinkCopied(String link) {
    return 'Link copied: $link';
  }

  @override
  String get shareUnavailable =>
      'Couldn\'t create the link. On Navidrome, sharing has to be on (ND_ENABLESHARING=true).';

  @override
  String get addToQueue => 'Add to queue';

  @override
  String get album => 'Album';

  @override
  String get albums => 'Albums';

  @override
  String get appearance => 'Appearance';

  @override
  String get artist => 'Artist';

  @override
  String get artistRadio => 'Artist radio';

  @override
  String get artists => 'Artists';

  @override
  String get audioMuse => 'AudioMuse-AI (sonic analysis)';

  @override
  String get audioMuseActive =>
      'Active: sonic radio and sonic path are available in the menus';

  @override
  String get audioMuseInactive =>
      'Not detected. Install the AudioMuse-AI plugin on Navidrome (0.62+) to enable sonic radio.';

  @override
  String get buildingMix => 'Building the mix…';

  @override
  String get cache => 'Music cache';

  @override
  String get cancel => 'Cancel';

  @override
  String get clear => 'Clear';

  @override
  String get compilation => 'Compilation';

  @override
  String get connect => 'Connect';

  @override
  String get crossfade => 'Crossfade';

  @override
  String get crossfadeHint =>
      'Consecutive tracks from the same album always play gapless, without crossfade.';

  @override
  String get crossfadeOff => 'Off (gapless)';

  @override
  String get delete => 'Delete';

  @override
  String get desktop => 'Desktop';

  @override
  String get discover => 'Discover';

  @override
  String get dynamicColor => 'Cover colors';

  @override
  String get dynamicColorHint =>
      'The theme follows the cover of the playing song';

  @override
  String get favorite => 'Favorite';

  @override
  String get favorites => 'Favorites';

  @override
  String get filter => 'Filter';

  @override
  String get genres => 'Genres';

  @override
  String get goToAlbum => 'Go to album';

  @override
  String get goToArtist => 'Go to artist';

  @override
  String get home => 'Home';

  @override
  String get instantMix => 'Instant mix';

  @override
  String get loginHint =>
      'Works with Navidrome, Gonic, Ampache, Airsonic and other Subsonic-compatible servers. Your password is not stored, only a token.';

  @override
  String get loginSubtitle => 'Connect to your music server';

  @override
  String get logout => 'Log out';

  @override
  String get lyrics => 'Lyrics';

  @override
  String get mostPlayed => 'Most played';

  @override
  String get newPlaylist => 'New playlist';

  @override
  String get next => 'Next';

  @override
  String get noLyrics => 'No lyrics for this song';

  @override
  String get noResults => 'Nothing found';

  @override
  String get noSimilarSongs => 'No similar songs found';

  @override
  String get nothingHere => 'Nothing here yet';

  @override
  String get nothingPlaying => 'Nothing playing';

  @override
  String get offline => 'Server offline — retry';

  @override
  String get ok => 'OK';

  @override
  String get outputDevice => 'Audio output';

  @override
  String get password => 'Password';

  @override
  String get pause => 'Pause';

  @override
  String get play => 'Play';

  @override
  String get playback => 'Playback';

  @override
  String get playlist => 'Playlist';

  @override
  String get playlistName => 'Playlist name';

  @override
  String get playlists => 'Playlists';

  @override
  String get playNext => 'Play next';

  @override
  String get playNow => 'Play now';

  @override
  String get preamp => 'Preamp';

  @override
  String get previous => 'Previous';

  @override
  String get qualityOriginal => 'Original (no transcoding)';

  @override
  String get queue => 'Queue';

  @override
  String get queueEmpty => 'The queue is empty';

  @override
  String get random => 'Random';

  @override
  String get recentlyAdded => 'Recently added';

  @override
  String get recentlyPlayed => 'Recently played';

  @override
  String get removeFromPlaylist => 'Remove from playlist';

  @override
  String get rename => 'Rename';

  @override
  String get repeat => 'Repeat';

  @override
  String get replayGain => 'Volume normalization (ReplayGain)';

  @override
  String get required => 'Required';

  @override
  String get retry => 'Retry';

  @override
  String get notConnected => 'Not connected to the server yet';

  @override
  String get couldNotLoad => 'Couldn\'t load this right now';

  @override
  String get rgAlbum => 'Album';

  @override
  String get rgAuto => 'Automatic';

  @override
  String get rgOff => 'Off';

  @override
  String get rgTrack => 'Track';

  @override
  String get search => 'Search';

  @override
  String get searchEmptyHint => 'Search for artists, albums and songs';

  @override
  String get recentSearches => 'Recent searches';

  @override
  String get clearRecentSearches => 'Clear';

  @override
  String get removeRecentSearch => 'Remove from recent';

  @override
  String get searchHint => 'Search…';

  @override
  String get seeAll => 'See all';

  @override
  String get server => 'Server';

  @override
  String get serverUrl => 'Server address';

  @override
  String get settings => 'Settings';

  @override
  String get shuffle => 'Shuffle';

  @override
  String get shuffleLibrary => 'Shuffle library';

  @override
  String get similarArtists => 'Similar artists';

  @override
  String get songs => 'Songs';

  @override
  String get library => 'Library';

  @override
  String get sonicPath => 'Sonic path to…';

  @override
  String get sonicPathPickTarget => 'Pick the destination song';

  @override
  String get sonicRadio => 'Sonic radio (AudioMuse)';

  @override
  String get sortByArtist => 'Artist (A–Z)';

  @override
  String get sortByName => 'Name (A–Z)';

  @override
  String get sortByYear => 'Year';

  @override
  String get streaming => 'Streaming';

  @override
  String get streamQuality => 'Streaming quality';

  @override
  String get mobileQuality => 'Quality on mobile data';

  @override
  String get mobileQualityHint => 'Saves your data plan when there is no Wi-Fi';

  @override
  String get sameAsWifi => 'Same as Wi-Fi';

  @override
  String get systemDefault => 'System default';

  @override
  String get theme => 'Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'System';

  @override
  String get topRated => 'Top rated';

  @override
  String get topSongs => 'Top songs';

  @override
  String get trackNotifications => 'Notify on track change';

  @override
  String get trackNotificationsHint =>
      'Shows a notification with the cover. Quick changes update the same notification (no stacking).';

  @override
  String get uiScale => 'Interface size';

  @override
  String get unfavorite => 'Unfavorite';

  @override
  String get username => 'Username';

  @override
  String get wrongCredentials => 'Wrong username or password';

  @override
  String albumCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count albums',
      one: '1 album',
      zero: 'No albums',
    );
    return '$_temp0';
  }

  @override
  String songCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
      zero: 'No songs',
    );
    return '$_temp0';
  }

  @override
  String disc(int number) {
    return 'Disc $number';
  }

  @override
  String seconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds',
      one: '1 second',
    );
    return '$_temp0';
  }

  @override
  String queueSummary(int count, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs up next',
      one: '1 song up next',
    );
    return '$_temp0 • $duration';
  }

  @override
  String cacheUsage(String used, int limit) {
    return '$used MB used of $limit MB';
  }

  @override
  String deletePlaylistQuestion(String name) {
    return 'Delete the playlist \"$name\"?';
  }

  @override
  String get outputDeviceFailed =>
      'Couldn\'t use that device; keeping the previous one.';

  @override
  String get automix => 'AutoMix (DJ transitions)';

  @override
  String get automixEnable => 'Enable AutoMix';

  @override
  String get automixEnableHint =>
      'Analyzes songs (beat, bars, key) and makes beat-synced transitions like a DJ. Without a clear beat, it makes a smooth transition.';

  @override
  String get automixStyle => 'Transition style';

  @override
  String get mixAuto => 'Automatic (recommended)';

  @override
  String get mixBassSwap => 'Bass swap';

  @override
  String get mixBlend => 'Smooth blend';

  @override
  String get mixFilter => 'Filter';

  @override
  String get mixEcho => 'Echo';

  @override
  String get mixCut => 'Cut on the bar';

  @override
  String get automixBars => 'Preferred length (bars)';

  @override
  String get automixBarsHint =>
      'How long both songs play together when the structure allows.';

  @override
  String get automixMaxSeconds => 'Maximum transition length';

  @override
  String get automixUnclear => 'Transition when the song is unclear';

  @override
  String get automixUnclearHint =>
      'How much of the song to use when there\'s no reliable beat or defined intro/outro.';

  @override
  String get automixMaxTempo => 'Maximum speed change';

  @override
  String get automixMaxTempoHint =>
      'How much the next song may speed up/slow down so the beats match (pitch is kept).';

  @override
  String get automixRamp => 'Return to original tempo (bars)';

  @override
  String get automixRampKeep => 'keep';

  @override
  String get automixRampHint =>
      'After the transition, the song slowly returns to its original speed.';

  @override
  String get automixHarmonic => 'Harmonic mixing';

  @override
  String get automixHarmonicHint =>
      'When keys clash (Camelot wheel), makes a short filtered transition.';

  @override
  String get automixTrim => 'Trim silence at start and end';

  @override
  String get automixAlbums => 'Respect albums';

  @override
  String get automixAlbumsHint =>
      'In continuous albums (live, mixed, concept), consecutive tracks play gapless, without mixing. Albums with silence between tracks are mixed as usual.';

  @override
  String get automixPreAnalyze => 'Pre-analyze the queue';

  @override
  String get automixPreAnalyzeHint =>
      'Analyzes upcoming songs ahead of time, in the background, at low priority.';

  @override
  String get analysisServer => 'Analysis server';

  @override
  String get analysisServerOff => 'Off: this device analyzes the songs';

  @override
  String get analysisServerHint =>
      'With BK Analyzer running on a computer, AutoMix analyses come ready from it (full model, more songs sync) and this device only plans the transition. Away from the server, this device analyzes as before.';

  @override
  String get analysisServerSet => 'Set up';

  @override
  String get analysisServerAddress => 'Analysis server address';

  @override
  String get analysisServerExample =>
      'e.g. http://192.168.1.10:4540, or the portal link (Tailscale)';

  @override
  String get analysisServerPanel => 'Open dashboard';

  @override
  String get analysisServerTest => 'Test';

  @override
  String get analysisServerRemove => 'Turn off';

  @override
  String get analysisServerChange => 'Change address';

  @override
  String get dlManagerTitle => 'Downloading';

  @override
  String get dlPaused => 'Downloads paused';

  @override
  String dlAllDone(int count) {
    return '$count songs downloaded';
  }

  @override
  String dlProgress(int done, int total) {
    return '$done of $total songs';
  }

  @override
  String dlBytes(String done, String total) {
    return '$done of $total';
  }

  @override
  String dlEta(String time) {
    return '~$time left';
  }

  @override
  String dlFailedCount(int count) {
    return '$count failed';
  }

  @override
  String get dlPause => 'Pause';

  @override
  String get dlResume => 'Resume';

  @override
  String get dlParallel => 'At once';

  @override
  String get dlFewer => 'Fewer';

  @override
  String get dlMore => 'More';

  @override
  String dlRetryFailed(int count) {
    return 'Retry ($count)';
  }

  @override
  String get dlClear => 'Clear finished';

  @override
  String dlMoreQueued(int count) {
    return 'and $count more queued';
  }

  @override
  String get dlFailed => 'failed';

  @override
  String get dlQueued => 'queued';

  @override
  String get dlParallelSetting => 'Simultaneous downloads';

  @override
  String get dlParallelHint =>
      'How many songs download together for offline listening. More is faster on a good connection; fewer leaves bandwidth for playback.';

  @override
  String get dlWifiOnly => 'Download on Wi-Fi only';

  @override
  String get dlWifiOnlyHint => 'On mobile data, downloads wait for Wi-Fi';

  @override
  String get dlWaitingWifi => 'Waiting for Wi-Fi';

  @override
  String analysisServerOk(String done, String total, int workers) {
    return 'Connected · $done of $total songs analyzed · workers online: $workers';
  }

  @override
  String get analysisServerLoginFail =>
      'The analysis server rejected this account\'s login (does it use another Navidrome?)';

  @override
  String get analysisServerViaPortal =>
      'Through the portal: works away from home, and the address updates by itself when the tunnel changes.';

  @override
  String get analysisServerPortalFound =>
      'Portal found: AutoMix analysis now goes through it';

  @override
  String get analysisServerUnreachable => 'No answer from the analysis server';

  @override
  String get analysisServerNotBk => 'That address is not a BK Analyzer';

  @override
  String get automixDefaults => 'Restore AutoMix defaults';

  @override
  String get analysisModel => 'Analysis model';

  @override
  String get modelAuto => 'Automatic';

  @override
  String get modelSmall => 'Small';

  @override
  String get modelFull => 'Full';

  @override
  String get noAvx2 => 'no AVX2';

  @override
  String modelDeviceInfo(
    int cores,
    String simd,
    String recommended,
    String active,
  ) {
    return 'This device: $cores cores, $simd. Recommended: $recommended. In use: $active.';
  }

  @override
  String get modelHint =>
      'Small (10 MB) is fast and ships with the app. Full (83 MB) is more accurate, for powerful PCs.';

  @override
  String get downloadFullModel => 'Download full model (83 MB)';

  @override
  String get modelDownloaded => 'Full model downloaded and enabled';

  @override
  String get modelDownloadFailed => 'Model download failed';

  @override
  String get mixing => 'Mixing';

  @override
  String get nextMix => 'Next transition';

  @override
  String get analyzedBpm => 'Analyzed BPM';

  @override
  String get crossfadeAutomixNote =>
      'With AutoMix on, crossfade only applies when AutoMix is off.';

  @override
  String get radioOn =>
      'Endless radio on: the queue keeps going with similar songs';

  @override
  String get radioOff =>
      'Turn on endless radio (fills the queue with similar songs)';

  @override
  String get syncQueue => 'Sync the queue with the server';

  @override
  String get syncQueueHint =>
      'Saves the queue on the server so you can resume on another device.';

  @override
  String get equalizer => 'Equalizer';

  @override
  String get eqFlat => 'Flat';

  @override
  String get eqBass => 'Bass';

  @override
  String get eqTreble => 'Treble';

  @override
  String get eqVocal => 'Vocal';

  @override
  String get eqElectronic => 'Electronic';

  @override
  String get eqClassical => 'Classical';

  @override
  String get eqLoudness => 'Low volume';

  @override
  String get eqHeadphones => 'Headphones';

  @override
  String get eqCustom => 'Custom';

  @override
  String get eqHint =>
      'If you boost many bands, lower the preamp to avoid distortion.';

  @override
  String get openEqualizer => 'Open equalizer';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get customize => 'Customize';

  @override
  String get customizeHint =>
      'Theme, covers, now playing screen, layout, buttons and profiles';

  @override
  String get amoled => 'Pure black (AMOLED)';

  @override
  String get amoledHint => 'Fully black background in dark theme';

  @override
  String get usePalette => 'Use the color palette';

  @override
  String get cornerRadius => 'Corner radius';

  @override
  String get density => 'Density';

  @override
  String get densityCompact => 'Compact';

  @override
  String get densityStandard => 'Standard';

  @override
  String get densityComfortable => 'Comfortable';

  @override
  String get nowPlaying => 'Now playing';

  @override
  String get coverShape => 'Cover shape';

  @override
  String get shapeSquare => 'Square';

  @override
  String get shapeRounded => 'Rounded';

  @override
  String get shapeCircle => 'Round';

  @override
  String get nowPlayingLayout => 'Now playing layout';

  @override
  String get layoutSide => 'Cover + queue/lyrics';

  @override
  String get layoutLyrics => 'Cover + lyrics';

  @override
  String get layoutMinimal => 'Minimal';

  @override
  String get layoutVinyl => 'Vinyl';

  @override
  String get vinylScratch => 'Spin the record to seek';

  @override
  String get vinylScratchHint =>
      'Turn the cover with your finger, like a record, to move through the song. It plays again from wherever the needle landed when you let go.';

  @override
  String get vinylScratchAudio => 'Sound of the spinning record';

  @override
  String get vinylScratchAudioHint =>
      'The sound follows the spin, pitch going up and down, and plays backwards when you turn it the other way. Off, the song simply goes quiet while you search.';

  @override
  String get vinylSecondsPerTurn => 'Music per turn of the record';

  @override
  String get vinylSecondsPerTurnHint =>
      'How far the song moves on one full turn. The default, 1.8 s, is one turn of a 33⅓ RPM LP: spin it at the pace of a real record and the pitch comes out right. More seconds search faster; fewer, finer.';

  @override
  String vinylTurnSeconds(double n) {
    final intl.NumberFormat nNumberFormat =
        intl.NumberFormat.decimalPatternDigits(
          locale: localeName,
          decimalDigits: 1,
        );
    final String nString = nNumberFormat.format(n);

    return '$nString s';
  }

  @override
  String get vinylGlide => 'Coasting when you let go';

  @override
  String get vinylGlideHint =>
      'How long the record takes to settle back to normal speed after you let go. A harder throw carries it further — so where you land depends on the spin, not on where you let go. At zero it stops dead and you land where you released it.';

  @override
  String get vinylGlideOff => 'Stops dead';

  @override
  String get vinylCurve => 'Deceleration curve';

  @override
  String get curveVinyl => 'Vinyl (brakes, then eases in)';

  @override
  String get curveLinear => 'Constant';

  @override
  String get curveBrake => 'Brake at the end';

  @override
  String get vinylMemory => 'How far back the spin can go';

  @override
  String get vinylMemoryWholeSong => 'The whole song';

  @override
  String minutesShort(int n) {
    return '$n min';
  }

  @override
  String get vinylSpeedLimit => 'How fast the needle holds on';

  @override
  String get vinylNoLimit => 'No limit';

  @override
  String get vinylNoLimitHint =>
      'The needle never lifts: the whole spin comes out as sound, however fast. The only thing holding it back is what has already been decoded.';

  @override
  String get backgroundBlur => 'Blurred cover background';

  @override
  String get layout => 'Layout';

  @override
  String get sidebar => 'Sidebar';

  @override
  String get sidebarExpanded => 'Expanded';

  @override
  String get sidebarRail => 'Icons only';

  @override
  String get cardSize => 'Card size';

  @override
  String get sizeSmall => 'Small';

  @override
  String get sizeMedium => 'Medium';

  @override
  String get sizeLarge => 'Large';

  @override
  String get startPage => 'Start page';

  @override
  String get showQueueOnStart => 'Open with the queue visible';

  @override
  String get playerBarButtons => 'Player bar buttons (drag to reorder)';

  @override
  String get homeSections => 'Home sections (drag to reorder)';

  @override
  String get behavior => 'Behavior';

  @override
  String get songTap => 'When clicking a song';

  @override
  String get tapPlayFromHere => 'Play the list from it';

  @override
  String get tapPlayOne => 'Play only it';

  @override
  String get shortcuts => 'Keyboard shortcuts';

  @override
  String get shortcutsList =>
      'Space: play/pause • Ctrl+→/←: next/previous • Shift+→/←: ±10 s • Ctrl+F: search';

  @override
  String get profiles => 'Visual profiles';

  @override
  String get exportProfile => 'Export profile';

  @override
  String get exportProfileHint =>
      'Copies theme and layout as JSON (to keep or share)';

  @override
  String get profileCopied => 'Profile copied to the clipboard';

  @override
  String get importProfile => 'Import profile';

  @override
  String get importProfileHint => 'Pastes a previously copied JSON profile';

  @override
  String get profileImported => 'Profile applied';

  @override
  String get profileInvalid => 'The clipboard doesn\'t contain a valid profile';

  @override
  String get resetAppearance => 'Restore default appearance';

  @override
  String get volume => 'Volume';

  @override
  String get trayIcon => 'System tray icon';

  @override
  String get closeToTray => 'Close to tray';

  @override
  String get closeToTrayHint =>
      'Closing the window keeps the music playing; quit from the tray menu.';

  @override
  String get miniPlayer => 'Mini player';

  @override
  String get expand => 'Expand';

  @override
  String get downloadOffline => 'Download for offline';

  @override
  String get availableOffline => 'Available offline (tap to remove)';

  @override
  String downloadingCount(int done, int total) {
    return 'Downloading $done of $total';
  }

  @override
  String get removeOfflineQuestion => 'Remove from downloads?';

  @override
  String get downloads => 'Downloads';

  @override
  String get downloadsHint =>
      'Downloaded albums and playlists play even without internet or with the server off.';

  @override
  String get mixSynced => 'beat-synced';

  @override
  String get mixSimple => 'simple';

  @override
  String get automixOffTap => 'AutoMix off — click to turn on';

  @override
  String get automixOnTap => 'Click to turn AutoMix off';

  @override
  String get automixOnWaiting => 'AutoMix on — analyzing the next song';

  @override
  String get filterSongs => 'Filter by song, artist or album';

  @override
  String get devices => 'Devices';

  @override
  String get localAddress => 'Home network address (optional)';

  @override
  String get localAddressHint =>
      'Used when you\'re on the server\'s network (faster). Away from home, the main address is used.';

  @override
  String get localAddressNone => 'Not set';

  @override
  String get localAddressInUse => 'in use now';

  @override
  String get localAddressAway => 'out of reach now (using the main address)';

  @override
  String get portal => 'Portal';

  @override
  String get portalHint =>
      'A fixed address that says where the server is right now. When the server\'s address changes, the app finds the new one by itself.';

  @override
  String get portalNone => 'no portal: the server address is fixed';

  @override
  String get portalFingerprint => 'Fingerprint';

  @override
  String get portalFingerprintHint =>
      'Check it with whoever gave you the link. It is what proves the server is theirs and nobody else\'s.';

  @override
  String get commands => 'Commands';

  @override
  String get commandsHint =>
      'Rules like \"when this happens, do that\". The app only resumes what it paused itself: if you paused by hand, it won\'t start playing on its own.';

  @override
  String get commandsWhen => 'When this happens';

  @override
  String get pauseOnVolumeZero => 'Volume at minimum pauses';

  @override
  String get pauseOnVolumeZeroHintMobile =>
      'Turning the device volume all the way down pauses; turning it up resumes.';

  @override
  String get pauseOnVolumeZeroHintDesktop =>
      'Setting the app volume to zero pauses; raising it resumes.';

  @override
  String get pauseOnUnplug => 'Unplugging headphones pauses';

  @override
  String get pauseOnUnplugHint =>
      'Without this the music would keep going on the speaker.';

  @override
  String get commandsKeepOpen => 'So the app doesn\'t close by itself';

  @override
  String get keepAliveWhenPaused => 'Keep the app alive while paused';

  @override
  String get keepAliveWhenPausedHint =>
      'Off, Android may close the app while it is paused and you come back to an empty queue. On, the notification stays in the bar. Takes effect next time the app starts.';

  @override
  String get batteryUnrestricted => 'Battery unrestricted';

  @override
  String get batteryUnrestrictedOk =>
      'Allowed: the system won\'t close the app in the background.';

  @override
  String get batteryUnrestrictedBad =>
      'The system may close the app in the background to save battery.';

  @override
  String get batteryUnrestrictedFix => 'Allow';

  @override
  String get closeToTrayWarn =>
      'Closing the window quits the app and the music stops. Turn on \"close to tray\" under Computer so it only leaves the screen.';

  @override
  String get trayGoneWarn =>
      'Careful: with the tray icon off and \"close to tray\" on, the app disappears with no way to bring it back.';

  @override
  String get generatePlaylist => 'Generate playlist';

  @override
  String get generateHint =>
      'Choose how the playlist should be built. The AudioMuse analysis picks the songs.';

  @override
  String get genSeed => 'Starting song';

  @override
  String get genSeedNone => 'None — the whole library';

  @override
  String get genGuide => 'Guided by';

  @override
  String get genGenre => 'Genre';

  @override
  String get genAny => 'Any';

  @override
  String get genEra => 'Era';

  @override
  String get genByMinutes => 'By time';

  @override
  String get genByCount => 'By count';

  @override
  String get genOnlyStarred => 'Favourites only';

  @override
  String get genOnlyDownloaded => 'Downloaded only';

  @override
  String get genOnlyDownloadedHint =>
      'Works without the internet, using what is already on the device.';

  @override
  String get genDo => 'Generate';

  @override
  String get genAgain => 'Generate again';

  @override
  String get genSave => 'Save as playlist';

  @override
  String genMinutes(int n) {
    return '$n min';
  }

  @override
  String genSongs(int n) {
    return '$n songs';
  }

  @override
  String genResult(int n, int d) {
    return '$n songs · $d min';
  }

  @override
  String get recommend => 'Recommendations';

  @override
  String get recommendHint =>
      'Which songs the AudioMuse analysis picks for the radio, the instant mix and the endless queue. Not to be confused with AutoMix, which only blends one song into the next.';

  @override
  String get radioSheetTitle => 'Radio';

  @override
  String get radioSheetHint => 'Tap how AudioMuse should pick what comes next.';

  @override
  String get radioSheetOnline =>
      'Asking the server. Keep it on the device to work without the internet.';

  @override
  String get recommendStyleSound => 'Similar sound';

  @override
  String get recommendStyleSoundHint => 'Timbre and arrangement. The default.';

  @override
  String get recommendStyleMood => 'Same mood';

  @override
  String get recommendStyleMoodHint =>
      'Danceable, aggressive, happy, party, relaxed, sad.';

  @override
  String get recommendStyleGenre => 'Same musical style';

  @override
  String get recommendStyleGenreHint =>
      'The genres the analysis recognised in the song.';

  @override
  String get recommendStyleEra => 'Same era';

  @override
  String get recommendStyleEraHint =>
      'Nearby years, with the sound breaking ties.';

  @override
  String get recommendStyleLyrics => 'Same subject';

  @override
  String get recommendStyleLyricsHint => 'By what the lyrics talk about.';

  @override
  String get recommendStyleMix => 'Good to mix into';

  @override
  String get recommendStyleMixHint =>
      'Close tempo and a key that fits, the way DJs do it.';

  @override
  String get recommendStyleServer => 'The way AudioMuse does';

  @override
  String get recommendStyleServerHint =>
      'The server\'s own formula: three quarters lyrics, one quarter sound.';

  @override
  String get recommendOffline => 'Keep on this device (works without internet)';

  @override
  String get recommendOfflineHint =>
      'Downloads the AudioMuse analysis once. After that, similar songs come instantly, with no internet, and using less battery than asking the server.';

  @override
  String recommendReady(int n) {
    final intl.NumberFormat nNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String nString = nNumberFormat.format(n);

    return '$nString songs ready on this device';
  }

  @override
  String get recommendDownloading => 'Downloading…';

  @override
  String get recommendNoServer =>
      'Set the analysis server in Account and server to be able to download.';

  @override
  String get recommendUpdate => 'Check for update';

  @override
  String get localAddressOk => 'The home address responded and is now in use';

  @override
  String get localAddressNotNow =>
      'No response right now; it will be used when you\'re at home';

  @override
  String get save => 'Save';

  @override
  String get remove => 'Remove';

  @override
  String get playOn => 'Play on';

  @override
  String get thisDevice => 'This device';

  @override
  String devicePlaying(String title) {
    return 'Playing: $title';
  }

  @override
  String devicePaused(String title) {
    return 'Paused: $title';
  }

  @override
  String get deviceIdle => 'Idle';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String get sleepTimerHint =>
      'Music stops on its own; the volume fades out first.';

  @override
  String sleepTimerActive(String time) {
    return 'Stops in $time';
  }

  @override
  String get sleepTimerEndOfTrackActive => 'Stops at the end of this song';

  @override
  String get sleepTimerEndOfTrack => 'At the end of this song';

  @override
  String sleepTimerMinutes(int minutes) {
    return '$minutes minutes';
  }

  @override
  String get sleepTimerAdd10 => '10 more minutes';

  @override
  String get sleepTimerOff => 'Turn off the timer';

  @override
  String get sleepTimerDone => 'Sleep timer: music paused';

  @override
  String get deviceOffline => 'Out of reach';

  @override
  String get deviceControlling => 'Controlling from here';

  @override
  String playingOn(String device) {
    return 'Playing on $device';
  }

  @override
  String get noDevicesFound =>
      'No other devices found. Open BKmasterplayer on the other device, with the same account and on the same network.';

  @override
  String get addDeviceByAddress => 'Add by address';

  @override
  String get addDeviceHint =>
      'Device IP (e.g., its Tailscale address, 100.x.y.z)';

  @override
  String get deviceNotFound =>
      'No BKmasterplayer of this account answered at that address';

  @override
  String connectFailed(String device) {
    return 'Couldn\'t connect to $device';
  }

  @override
  String connectAuthFailed(String device) {
    return '$device didn\'t prove it belongs to your account. Sign in again on both devices.';
  }

  @override
  String get connectNeedsLogin =>
      'Tap to turn on protected Connect on this device (asks for the account password once). Since this version, the server password no longer travels between devices.';

  @override
  String get deviceNeedsLogin => 'Needs to sign in again';

  @override
  String get connectEnableTitle => 'Turn on protected Connect';

  @override
  String connectPasswordHint(String user) {
    return 'Password of the account $user. It never leaves this device: it becomes a key only your account\'s devices have. Do the same on your other devices.';
  }

  @override
  String get connectEnabledNow => 'Protected Connect is on for this device';

  @override
  String get connectWrongPassword => 'That password doesn\'t match the account';

  @override
  String get connectSection => 'Other devices (Connect)';

  @override
  String get connectEnable => 'Play and control across devices';

  @override
  String get connectEnableHint =>
      'This device shows up for your other devices with the same account and can be controlled by them, like Spotify Connect.';

  @override
  String get deviceName => 'This device\'s name';

  @override
  String get or => 'or';

  @override
  String get useLocalMusic => 'Use only this device\'s music';

  @override
  String get useLocalMusicHint =>
      'No server: plays the files in a folder on this device. You can change the folders later in Settings.';

  @override
  String get musicFolder => 'Music folder';

  @override
  String get musicFolderHint =>
      'BKmasterplayer reads the music in this folder and its subfolders.';

  @override
  String get chooseOtherFolder => 'Choose another';

  @override
  String get useThisFolder => 'Use this folder';

  @override
  String get musicPermissionDenied =>
      'No permission to read this device\'s music. Allow it in Android Settings → Apps → BKmasterplayer → Permissions.';

  @override
  String get noLocalSongs => 'No music found in that folder.';

  @override
  String scanningMusic(int count) {
    return 'Reading the music… $count files';
  }

  @override
  String localSongCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
      zero: 'No songs',
    );
    return '$_temp0';
  }

  @override
  String get addFolder => 'Add folder';

  @override
  String get rescanLibrary => 'Refresh the library';

  @override
  String get lastFmKey => 'Last.fm API key';

  @override
  String get lastFmKeyHint =>
      'Not set: radio and mix without AudioMuse use only the server';

  @override
  String get lastFmKeySet => 'Set';

  @override
  String get lastFmKeyHelp =>
      'Free: create one at last.fm/api/account/create and copy the \"API key\".';

  @override
  String get lastFmKeyOk => 'Last.fm key works';

  @override
  String get lastFmKeyBad =>
      'Last.fm rejected that key (check that you copied the right API key)';

  @override
  String get lastFmForRadio => 'Use Last.fm for similar songs';

  @override
  String get lastFmForRadioHint =>
      'In instant mix and radio, when the server has no AudioMuse, and for this device\'s music.';

  @override
  String jamRequestTitle(String name) {
    return '$name wants to join your Party';
  }

  @override
  String jamRequestBody(String via) {
    return 'Request $via. People in the Party can add songs and control playback.';
  }

  @override
  String get viaWifi => 'over Wi-Fi';

  @override
  String get viaBluetooth => 'over Bluetooth';

  @override
  String get jamAlwaysAccept => 'Always accept this person';

  @override
  String get accept => 'Accept';

  @override
  String get reject => 'Decline';

  @override
  String get startJam => 'Start a Party';

  @override
  String get startJamHint =>
      'People nearby with BKmasterplayer can ask to join, add songs and control playback. You approve each person.';

  @override
  String jamWaiting(String name) {
    return 'Asking to join $name\'s Party… Wait for them to accept.';
  }

  @override
  String get jamRejected => 'The request wasn\'t accepted.';

  @override
  String get jamEnded => 'The Party ended.';

  @override
  String get jamCopyAddress => 'Copy';

  @override
  String get jamAddressCopied => 'Copied';

  @override
  String get jamClose => 'Close';

  @override
  String get jamScanQr => 'Scan QR';

  @override
  String get jamQrHint =>
      'Point your phone\'s camera at this code — it opens the app and joins the party.';

  @override
  String get jamShowQr => 'Show QR';

  @override
  String get jamJoinByQr =>
      'By QR: point your phone\'s camera at the code shown on the device that started the party. No scanner app, no permission needed.';

  @override
  String get jamJoinByAddress => 'Join by address';

  @override
  String get jamJoinByAddressHint =>
      'For when the party does not show up on its own — on iPhone, or on Wi-Fi that filters. Ask whoever started it for the address.';

  @override
  String get jamMyAddress => 'Your address, for anyone typing it in';

  @override
  String get jamAddressBad => 'I could not make sense of that address.';

  @override
  String get jamsNearby => 'Parties nearby';

  @override
  String get jamSearching =>
      'Searching… Ask whoever is playing to open a Party in BKmasterplayer.';

  @override
  String jamOf(String name) {
    return '$name\'s Party';
  }

  @override
  String get join => 'Join';

  @override
  String get jamOpen => 'Your Party is open';

  @override
  String jamOpenHint(String name) {
    return 'Shows up as \"$name\" to people nearby.';
  }

  @override
  String get jamLeave => 'Leave';

  @override
  String jamBarHosting(int n) {
    return 'Party open · $n in the room';
  }

  @override
  String jamBarGuest(String nome) {
    return 'In $nome\'s party';
  }

  @override
  String get endJam => 'End';

  @override
  String jamPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people in the Party',
      one: '1 person in the Party',
      zero: 'Nobody in the Party',
    );
    return '$_temp0';
  }

  @override
  String get jamNobodyYet =>
      'When someone asks to join, you\'ll see the request here and in a prompt.';

  @override
  String get leaveJam => 'Leave';

  @override
  String get upNext => 'Up next';

  @override
  String get jamAdd => 'Add';

  @override
  String get jamMine => 'Mine';

  @override
  String get jamQueueTitle => 'Party queue';

  @override
  String get jamQueueEmpty => 'Nothing queued yet: add a song.';

  @override
  String addedBy(String name) {
    return 'by $name';
  }

  @override
  String get jamSearchHost => 'Search the Party\'s music';

  @override
  String jamAdded(String title) {
    return '\"$title\" was queued';
  }

  @override
  String get jamSendFile => 'Send a file from this device';

  @override
  String get jamSendFileHint =>
      'Pick a song on this device to play in the Party.';

  @override
  String get jamSearchMine => 'Search your music to send';

  @override
  String jamSending(String title) {
    return 'Sending \"$title\"…';
  }

  @override
  String get jamSent => 'In the Party\'s queue';

  @override
  String get jamSendFailed => 'Couldn\'t send it';

  @override
  String get jamInOne => 'You\'re in a Party';

  @override
  String get jamMenuHint => 'Play together with people nearby';

  @override
  String get jamAllowlist => 'Auto-accepted in the Party';

  @override
  String get jamAllowlistEmpty =>
      'Nobody: every request waits for you to accept.';

  @override
  String get jamAllowlistHint =>
      'These people join your Party without asking. Tap X to remove.';

  @override
  String get jamNearbyAlerts => 'Notify me when there\'s a Party nearby';

  @override
  String get jamNearbyAlertsHint =>
      'Uses Bluetooth in low-power mode, even with the app closed.';

  @override
  String get joinJamNoAccount => 'Join a Party nearby (no account)';

  @override
  String get downloadAll => 'Download every song on the server';

  @override
  String get downloadAllHint =>
      'To listen to everything offline. Takes a lot of space.';

  @override
  String readingLibrary(int count) {
    return 'Reading the library… $count songs';
  }

  @override
  String downloadAllConfirm(int count, String size) {
    return 'Download $count songs (about $size)? They stay on this device and play without internet; you can remove them later in Downloads.';
  }

  @override
  String get downloadAllMobileData =>
      'You\'re on mobile data: better to download on Wi-Fi.';

  @override
  String get wholeLibrary => 'Whole library';

  @override
  String get downloadNew => 'Download new ones';

  @override
  String get download => 'Download';

  @override
  String get onlineMeta => 'Lyrics and covers from the internet';

  @override
  String get onlineLyrics => 'Fetch missing lyrics';

  @override
  String get onlineLyricsHint =>
      'When the server or the file has no lyrics: LRCLIB (with synced lyrics) and, with your key, Musixmatch. The source is shown below the lyrics.';

  @override
  String get musixmatchKey => 'Musixmatch API key';

  @override
  String get musixmatchKeyHint =>
      'Optional: without it, lyrics come from LRCLIB.';

  @override
  String get musixmatchKeyHelp =>
      'From a developer account at developer.musixmatch.com. Full lyrics require a Musixmatch commercial plan; the app shows the rights notice and reports the display as the terms require. On the free plan (partial lyrics only), the app uses the other sources.';

  @override
  String get onlineCovers => 'Fetch missing covers';

  @override
  String get onlineCoversHint =>
      'For this device\'s music without covers: looks the album up on Cover Art Archive (MusicBrainz) and Deezer.';

  @override
  String get djModeFrom => 'DJ mode from this song';

  @override
  String get djModeOn =>
      'DJ mode on: AudioMuse and AutoMix pick the next song by the best fit (tap to turn off)';

  @override
  String get djModeOff =>
      'DJ mode: let AudioMuse and AutoMix pick the next songs';

  @override
  String get settingsAccount => 'Account and server';

  @override
  String get settingsLook => 'Look and feel';

  @override
  String get settingsLookHint =>
      'Themes, colors, fonts, background and screen layout';

  @override
  String get settingsStorage => 'Downloads and cache';

  @override
  String get settingsSources => 'Lyrics, covers and Last.fm';

  @override
  String get settingsDevices => 'Devices and Party';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get licenses => 'Open source licenses';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get diagnosticsSubtitle =>
      'Logged errors and the report to send along with a problem';

  @override
  String get diagnosticsHint =>
      'The app logs the errors that happen. When asking for help with a problem, send the report: it doesn\'t include your password, tokens, the server address or your username.';

  @override
  String diagnosticsErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errors this session',
      one: '1 error this session',
      zero: 'No errors this session',
    );
    return '$_temp0';
  }

  @override
  String get diagnosticsCopy => 'Copy report';

  @override
  String get diagnosticsSave => 'Save report';

  @override
  String get diagnosticsClear => 'Clear log';

  @override
  String get diagnosticsCopied => 'Report copied';

  @override
  String get diagnosticsCleared => 'Log cleared';

  @override
  String get diagnosticsEmpty => 'Nothing logged yet.';

  @override
  String get startupFailed => 'The audio engine didn\'t start';

  @override
  String get startupFailedHint =>
      'Close and reopen the app. If it keeps happening, copy the report below and send it along with the problem.';

  @override
  String get fontCredits =>
      'Theme fonts: Nunito, Space Grotesk, JetBrains Mono, Playfair Display and Bebas Neue (SIL Open Font License).';

  @override
  String get openDownloads => 'Open downloads';

  @override
  String get openDownloadsHint =>
      'Albums, playlists and the whole library to listen offline';

  @override
  String get lookColors => 'Colors';

  @override
  String get lookFonts => 'Fonts';

  @override
  String get lookShapes => 'Shapes and sizes';

  @override
  String get lookBackground => 'Background';

  @override
  String get lookStructure => 'Screen layout';

  @override
  String get lookMotion => 'Animations';

  @override
  String get lookEditHint =>
      'Everything applies right away; the app itself is the preview.';

  @override
  String get original => 'original';

  @override
  String get colorSource => 'App color';

  @override
  String get colorFromCover => 'From the playing cover (original)';

  @override
  String get colorFixed => 'Fixed color';

  @override
  String get baseColor => 'Base color';

  @override
  String get baseColorHint =>
      'With cover colors, it is used when nothing is playing.';

  @override
  String get pickColor => 'Pick a color…';

  @override
  String get colorHex => 'Code';

  @override
  String get hue => 'Hue';

  @override
  String get saturation => 'Saturation';

  @override
  String get brightness => 'Brightness';

  @override
  String get useThis => 'Use';

  @override
  String get paletteStyle => 'Palette style';

  @override
  String get variantTonalSpot => 'Tonal (original)';

  @override
  String get variantFidelity => 'True to color';

  @override
  String get variantMonochrome => 'Monochrome';

  @override
  String get variantNeutral => 'Neutral';

  @override
  String get variantVibrant => 'Vibrant';

  @override
  String get variantExpressive => 'Expressive';

  @override
  String get variantContent => 'Content';

  @override
  String get variantRainbow => 'Rainbow';

  @override
  String get variantFruitSalad => 'Fruit salad';

  @override
  String get contrast => 'Contrast';

  @override
  String get contrastSoft => 'Soft';

  @override
  String get contrastStandard => 'Standard';

  @override
  String get contrastMax => 'Maximum';

  @override
  String get manualColors => 'Custom colors';

  @override
  String get manualColorsHint =>
      'They replace the computed color. × goes back to automatic.';

  @override
  String get colorPrimary => 'Primary';

  @override
  String get colorSecondary => 'Secondary';

  @override
  String get colorTertiary => 'Tertiary';

  @override
  String get colorBackground => 'Background';

  @override
  String get colorText => 'Text';

  @override
  String get automatic => 'Automatic';

  @override
  String get fontTitles => 'Titles';

  @override
  String get fontBody => 'Text';

  @override
  String get fontSystem => 'System (original)';

  @override
  String get fontSample => 'The right song at the right time';

  @override
  String get buttons => 'Buttons';

  @override
  String get buttonFilled => 'Filled (original)';

  @override
  String get buttonTonal => 'Tonal';

  @override
  String get buttonOutlined => 'Outlined';

  @override
  String get cards => 'Cards';

  @override
  String get cardFlat => 'Flat (original)';

  @override
  String get cardElevated => 'Elevated';

  @override
  String get cardOutlined => 'Outlined';

  @override
  String get preview => 'Preview';

  @override
  String get backgroundStyle => 'Screen background';

  @override
  String get bgSolid => 'Solid (original)';

  @override
  String get bgGradient => 'Gradient';

  @override
  String get bgCover => 'Blurred cover';

  @override
  String get bgImage => 'Image';

  @override
  String get chooseImage => 'Choose image…';

  @override
  String get imageTooBig => 'Image too large (12 MB max)';

  @override
  String get backgroundDim => 'Theme color on top';

  @override
  String get backgroundDimHint => 'Higher keeps text easier to read.';

  @override
  String get sidebarTabs => 'Sidebar tabs';

  @override
  String get sidebarTabsHint => 'Desktop and tablet. Drag to reorder.';

  @override
  String get mobileTabs => 'Phone tabs';

  @override
  String get mobileTabsHint =>
      'From 2 to 4, plus Settings (always last). Drag to reorder.';

  @override
  String get mobileTabsLimit => 'The phone fits 2 to 4 tabs, plus Settings';

  @override
  String get navLabels => 'Tab labels';

  @override
  String get labelsAuto => 'Automatic (original)';

  @override
  String get labelsAll => 'Always';

  @override
  String get labelsSelected => 'Only the open one';

  @override
  String get labelsNone => 'Never';

  @override
  String get playerStyle => 'Player bar';

  @override
  String get playerDocked => 'Docked (original)';

  @override
  String get playerFloating => 'Floating';

  @override
  String get transitions => 'Screen transitions';

  @override
  String get transDefault => 'Default (original)';

  @override
  String get transFade => 'Fade';

  @override
  String get transSlide => 'Slide';

  @override
  String get transNone => 'No animation';

  @override
  String get animSpeed => 'Animations';

  @override
  String get animNormal => 'Normal (original)';

  @override
  String get animFast => 'Fast';

  @override
  String get animOff => 'Off';

  @override
  String get themes => 'Themes';

  @override
  String get themesHint => 'Tap to apply; long-press (or ⋮) for more options.';

  @override
  String get themeOriginal => 'BKmasterplayer (original)';

  @override
  String get themeVinyl => 'Vinyl';

  @override
  String get themePaper => 'Paper';

  @override
  String get themeContrast => 'High contrast';

  @override
  String get themeAuto => 'Automatic';

  @override
  String get themeModified => 'modified';

  @override
  String get saveAsTheme => 'Save the current look as a theme';

  @override
  String get themeName => 'Theme name';

  @override
  String get myTheme => 'My theme';

  @override
  String themeSaved(String name) {
    return 'Theme \"$name\" saved';
  }

  @override
  String get applyTheme => 'Apply';

  @override
  String get duplicate => 'Duplicate';

  @override
  String copyOf(String name) {
    return '$name (copy)';
  }

  @override
  String get saveChangesHere => 'Save changes to this theme';

  @override
  String get exportThemeFile => 'Export file';

  @override
  String get importTheme => 'Import theme (file)';

  @override
  String themeImported(String name) {
    return 'Theme \"$name\" imported and applied';
  }

  @override
  String get backupFiles => 'Backup and files';

  @override
  String get exportBackup => 'Export full backup';

  @override
  String get exportBackupHint =>
      'All your themes and the current look in one file';

  @override
  String get restoreBackup => 'Restore backup (file)';

  @override
  String get restoreBackupConfirm =>
      'Replace your themes and current look with the backup\'s? The current state is kept in the automatic backups.';

  @override
  String get restore => 'Restore';

  @override
  String get backupRestored => 'Backup restored';

  @override
  String get autoBackups => 'Automatic backups';

  @override
  String get autoBackupsHint => 'Made before every big change (the last 10)';

  @override
  String get noAutoBackups =>
      'None yet: they appear when you switch themes with unsaved changes, import or restore.';

  @override
  String get fileSaved => 'File saved';

  @override
  String get invalidThemeFile =>
      'Invalid file: not a BKmasterplayer theme or backup';

  @override
  String get textProfiles => 'As text (clipboard)';

  @override
  String deleteThemeConfirm(String name) {
    return 'Delete theme \"$name\"?';
  }

  @override
  String get backToOriginal => 'Back to the original look';

  @override
  String get backToOriginalHint =>
      'The BKmasterplayer theme, as the app ships (the current look goes to automatic backups if not saved).';

  @override
  String get party => 'Party';

  @override
  String lyricsSource(String source) {
    return 'Lyrics: $source';
  }

  @override
  String get lastFmCredit => 'Data from Last.fm';

  @override
  String get lastFmCreditHint =>
      'Similar songs and artists, top tracks and biographies come from Last.fm. Tap to open the site.';

  @override
  String get openOnLastFm => 'View on Last.fm';

  @override
  String get automixStatus => 'AutoMix status';

  @override
  String get automixTapStatus => 'Tap to see the AutoMix status';

  @override
  String get mixNowPlaying => 'Now playing';

  @override
  String get mixUpNext => 'Up next';

  @override
  String get mixNoNext => 'No next song in the queue';

  @override
  String get mixAnalyzing => 'Analyzing…';

  @override
  String get beatReliable => 'reliable beat';

  @override
  String get beatUnreliable => 'unreliable beat';

  @override
  String get automixWaitingAnalysis =>
      'Waiting for both songs\' analyses to plan the transition.';

  @override
  String get automixOffStatus =>
      'Off: songs change the regular way (crossfade or gapless).';

  @override
  String get automixSettingsLink => 'AutoMix settings';

  @override
  String get automixUnreliableHelp =>
      'To sync, beats must fall on a steady grid (±10 ms) through most of the section. Live-played music with drifting tempo often doesn\'t pass; then the transition is simple.';
}
