import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReplayGainMode { off, track, album, auto }

enum LoopMode { off, all, one }

enum MixStyleSetting { auto, bassSwap, blend, filter, echo, cut }

enum AnalysisModelSetting { auto, small, full }

/// Configurações do app (persistidas como JSON). A customização visual
/// completa (tokens de tema e layout) cresce aqui na Fase 4.
@immutable
class AppSettings {
  const AppSettings({
    this.crossfadeSeconds = 0,
    this.replayGainMode = ReplayGainMode.auto,
    this.replayGainPreampDb = 0,
    this.notifications = true,
    this.outputDeviceId,
    this.cacheLimitMb = 4096,
    this.transcodeFormat,
    this.maxBitRate = 0,
    this.volume = 1.0,
    this.locale,
    this.automixEnabled = true,
    this.automixStyle = MixStyleSetting.auto,
    this.automixMaxTempo = 8,
    this.automixBars = 16,
    this.automixMaxSeconds = 40,
    this.automixUnclearSeconds = 8,
    this.automixHarmonic = true,
    this.automixRampBars = 16,
    this.automixTrimSilence = true,
    this.automixRespectAlbums = true,
    this.analysisModel = AnalysisModelSetting.auto,
    this.preAnalyze = true,
    this.syncQueue = true,
    this.eqEnabled = false,
    this.eqPreamp = 0,
    this.eqGains = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.eqPreset = 'flat',
    this.trayIcon = true,
    this.closeToTray = false,
    this.connectEnabled = true,
    this.deviceName,
    this.localFolders = const [],
    this.lastFmApiKey,
    this.lastFmForRadio = true,
    this.jamNearbyAlerts = true,
    this.onlineLyrics = true,
    this.onlineCovers = true,
    this.musixmatchKey,
  });

  final int crossfadeSeconds;
  final ReplayGainMode replayGainMode;
  final double replayGainPreampDb;
  final bool notifications;
  final String? outputDeviceId;
  final int cacheLimitMb;
  final String? transcodeFormat;
  final int maxBitRate;
  final double volume;
  final String? locale;

  // AutoMix (transição de DJ)
  final bool automixEnabled;
  final MixStyleSetting automixStyle;
  final double automixMaxTempo;
  final int automixBars;
  final double automixMaxSeconds;
  final double automixUnclearSeconds;
  final bool automixHarmonic;
  final int automixRampBars;
  final bool automixTrimSilence;
  final bool automixRespectAlbums;
  final AnalysisModelSetting analysisModel;
  final bool preAnalyze;

  /// Salva a fila no servidor (continuar em outro aparelho).
  final bool syncQueue;

  // Equalizador
  final bool eqEnabled;
  final double eqPreamp;
  final List<double> eqGains;
  final String eqPreset;

  // Desktop
  final bool trayIcon;
  final bool closeToTray;

  /// Aparece para os outros aparelhos da mesma conta (BKT Player Connect) e
  /// aceita ser controlado por eles.
  final bool connectEnabled;

  /// Nome mostrado aos outros aparelhos (null = nome do sistema).
  final String? deviceName;

  /// Pastas das músicas do aparelho (modo sem servidor).
  final List<String> localFolders;

  /// Chave da API do Last.fm (músicas parecidas sem AudioMuse).
  final String? lastFmApiKey;

  /// Usar o Last.fm na rádio e no mix quando o servidor não tem análise sônica.
  final bool lastFmForRadio;

  /// Avisar quando passar perto de uma Jam (scan Bluetooth em segundo plano, Android).
  final bool jamNearbyAlerts;

  /// Buscar na internet as letras que faltam (LRCLIB, Musixmatch, lyrics.ovh).
  final bool onlineLyrics;

  /// Buscar na internet as capas que faltam nas músicas do aparelho.
  final bool onlineCovers;

  /// Chave da API oficial do Musixmatch (opcional).
  final String? musixmatchKey;

  AppSettings copyWith({
    int? crossfadeSeconds,
    ReplayGainMode? replayGainMode,
    double? replayGainPreampDb,
    bool? notifications,
    String? outputDeviceId,
    bool clearOutputDevice = false,
    int? cacheLimitMb,
    String? transcodeFormat,
    bool clearTranscode = false,
    int? maxBitRate,
    double? volume,
    String? locale,
    bool clearLocale = false,
    bool? automixEnabled,
    MixStyleSetting? automixStyle,
    double? automixMaxTempo,
    int? automixBars,
    double? automixMaxSeconds,
    double? automixUnclearSeconds,
    bool? automixHarmonic,
    int? automixRampBars,
    bool? automixTrimSilence,
    bool? automixRespectAlbums,
    AnalysisModelSetting? analysisModel,
    bool? preAnalyze,
    bool? syncQueue,
    bool? eqEnabled,
    double? eqPreamp,
    List<double>? eqGains,
    String? eqPreset,
    bool? trayIcon,
    bool? closeToTray,
    bool? connectEnabled,
    String? deviceName,
    bool clearDeviceName = false,
    List<String>? localFolders,
    String? lastFmApiKey,
    bool clearLastFm = false,
    bool? lastFmForRadio,
    bool? jamNearbyAlerts,
    bool? onlineLyrics,
    bool? onlineCovers,
    String? musixmatchKey,
    bool clearMusixmatch = false,
  }) =>
      AppSettings(
        crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
        replayGainMode: replayGainMode ?? this.replayGainMode,
        replayGainPreampDb: replayGainPreampDb ?? this.replayGainPreampDb,
        notifications: notifications ?? this.notifications,
        outputDeviceId: clearOutputDevice ? null : (outputDeviceId ?? this.outputDeviceId),
        cacheLimitMb: cacheLimitMb ?? this.cacheLimitMb,
        transcodeFormat: clearTranscode ? null : (transcodeFormat ?? this.transcodeFormat),
        maxBitRate: maxBitRate ?? this.maxBitRate,
        volume: volume ?? this.volume,
        locale: clearLocale ? null : (locale ?? this.locale),
        automixEnabled: automixEnabled ?? this.automixEnabled,
        automixStyle: automixStyle ?? this.automixStyle,
        automixMaxTempo: automixMaxTempo ?? this.automixMaxTempo,
        automixBars: automixBars ?? this.automixBars,
        automixMaxSeconds: automixMaxSeconds ?? this.automixMaxSeconds,
        automixUnclearSeconds: automixUnclearSeconds ?? this.automixUnclearSeconds,
        automixHarmonic: automixHarmonic ?? this.automixHarmonic,
        automixRampBars: automixRampBars ?? this.automixRampBars,
        automixTrimSilence: automixTrimSilence ?? this.automixTrimSilence,
        automixRespectAlbums: automixRespectAlbums ?? this.automixRespectAlbums,
        analysisModel: analysisModel ?? this.analysisModel,
        preAnalyze: preAnalyze ?? this.preAnalyze,
        syncQueue: syncQueue ?? this.syncQueue,
        eqEnabled: eqEnabled ?? this.eqEnabled,
        eqPreamp: eqPreamp ?? this.eqPreamp,
        eqGains: eqGains ?? this.eqGains,
        eqPreset: eqPreset ?? this.eqPreset,
        trayIcon: trayIcon ?? this.trayIcon,
        closeToTray: closeToTray ?? this.closeToTray,
        connectEnabled: connectEnabled ?? this.connectEnabled,
        deviceName: clearDeviceName ? null : (deviceName ?? this.deviceName),
        localFolders: localFolders ?? this.localFolders,
        lastFmApiKey: clearLastFm ? null : (lastFmApiKey ?? this.lastFmApiKey),
        lastFmForRadio: lastFmForRadio ?? this.lastFmForRadio,
        jamNearbyAlerts: jamNearbyAlerts ?? this.jamNearbyAlerts,
        onlineLyrics: onlineLyrics ?? this.onlineLyrics,
        onlineCovers: onlineCovers ?? this.onlineCovers,
        musixmatchKey: clearMusixmatch ? null : (musixmatchKey ?? this.musixmatchKey),
      );

  Map<String, dynamic> toJson() => {
        'crossfadeSeconds': crossfadeSeconds,
        'replayGainMode': replayGainMode.name,
        'replayGainPreampDb': replayGainPreampDb,
        'notifications': notifications,
        'outputDeviceId': outputDeviceId,
        'cacheLimitMb': cacheLimitMb,
        'transcodeFormat': transcodeFormat,
        'maxBitRate': maxBitRate,
        'volume': volume,
        'locale': locale,
        'automixEnabled': automixEnabled,
        'automixStyle': automixStyle.name,
        'automixMaxTempo': automixMaxTempo,
        'automixBars': automixBars,
        'automixMaxSeconds': automixMaxSeconds,
        'automixUnclearSeconds': automixUnclearSeconds,
        'automixHarmonic': automixHarmonic,
        'automixRampBars': automixRampBars,
        'automixTrimSilence': automixTrimSilence,
        'automixRespectAlbums': automixRespectAlbums,
        'analysisModel': analysisModel.name,
        'preAnalyze': preAnalyze,
        'syncQueue': syncQueue,
        'eqEnabled': eqEnabled,
        'eqPreamp': eqPreamp,
        'eqGains': eqGains,
        'eqPreset': eqPreset,
        'trayIcon': trayIcon,
        'closeToTray': closeToTray,
        'connectEnabled': connectEnabled,
        'deviceName': deviceName,
        'localFolders': localFolders,
        'lastFmApiKey': lastFmApiKey,
        'lastFmForRadio': lastFmForRadio,
        'jamNearbyAlerts': jamNearbyAlerts,
        'onlineLyrics': onlineLyrics,
        'onlineCovers': onlineCovers,
        'musixmatchKey': musixmatchKey,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T pick<T>(String k, T def) => j[k] is T ? j[k] as T : def;
    return AppSettings(
      crossfadeSeconds: pick('crossfadeSeconds', d.crossfadeSeconds),
      replayGainMode: ReplayGainMode.values.asNameMap()[j['replayGainMode']] ?? d.replayGainMode,
      replayGainPreampDb: (j['replayGainPreampDb'] as num?)?.toDouble() ?? d.replayGainPreampDb,
      notifications: pick('notifications', d.notifications),
      outputDeviceId: j['outputDeviceId'] as String?,
      cacheLimitMb: pick('cacheLimitMb', d.cacheLimitMb),
      transcodeFormat: j['transcodeFormat'] as String?,
      maxBitRate: pick('maxBitRate', d.maxBitRate),
      volume: (j['volume'] as num?)?.toDouble() ?? d.volume,
      locale: j['locale'] as String?,
      automixEnabled: pick('automixEnabled', d.automixEnabled),
      automixStyle: MixStyleSetting.values.asNameMap()[j['automixStyle']] ?? d.automixStyle,
      automixMaxTempo: (j['automixMaxTempo'] as num?)?.toDouble() ?? d.automixMaxTempo,
      automixBars: pick('automixBars', d.automixBars),
      automixMaxSeconds: (j['automixMaxSeconds'] as num?)?.toDouble() ?? d.automixMaxSeconds,
      automixUnclearSeconds: (j['automixUnclearSeconds'] as num?)?.toDouble() ?? d.automixUnclearSeconds,
      automixHarmonic: pick('automixHarmonic', d.automixHarmonic),
      automixRampBars: pick('automixRampBars', d.automixRampBars),
      automixTrimSilence: pick('automixTrimSilence', d.automixTrimSilence),
      automixRespectAlbums: pick('automixRespectAlbums', d.automixRespectAlbums),
      analysisModel: AnalysisModelSetting.values.asNameMap()[j['analysisModel']] ?? d.analysisModel,
      preAnalyze: pick('preAnalyze', d.preAnalyze),
      syncQueue: pick('syncQueue', d.syncQueue),
      eqEnabled: pick('eqEnabled', d.eqEnabled),
      eqPreamp: (j['eqPreamp'] as num?)?.toDouble() ?? d.eqPreamp,
      eqGains: (j['eqGains'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? d.eqGains,
      eqPreset: j['eqPreset'] as String? ?? d.eqPreset,
      trayIcon: pick('trayIcon', d.trayIcon),
      closeToTray: pick('closeToTray', d.closeToTray),
      connectEnabled: pick('connectEnabled', d.connectEnabled),
      deviceName: j['deviceName'] as String?,
      localFolders: (j['localFolders'] as List?)?.whereType<String>().toList() ?? d.localFolders,
      lastFmApiKey: j['lastFmApiKey'] as String?,
      lastFmForRadio: pick('lastFmForRadio', d.lastFmForRadio),
      jamNearbyAlerts: pick('jamNearbyAlerts', d.jamNearbyAlerts),
      onlineLyrics: pick('onlineLyrics', d.onlineLyrics),
      onlineCovers: pick('onlineCovers', d.onlineCovers),
      musixmatchKey: j['musixmatchKey'] as String?,
    );
  }

  static const _key = 'settings';

  static AppSettings load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(SharedPreferences prefs) => prefs.setString(_key, jsonEncode(toJson()));
}
