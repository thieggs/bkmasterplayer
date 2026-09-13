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
    this.themeMode = ThemeMode.dark,
    this.seedColor = 0xFF7C4DFF,
    this.dynamicColorFromCover = true,
    this.uiScale = 1.0,
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
  });

  final ThemeMode themeMode;
  final int seedColor;
  final bool dynamicColorFromCover;
  final double uiScale;
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

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? seedColor,
    bool? dynamicColorFromCover,
    double? uiScale,
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
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        seedColor: seedColor ?? this.seedColor,
        dynamicColorFromCover: dynamicColorFromCover ?? this.dynamicColorFromCover,
        uiScale: uiScale ?? this.uiScale,
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
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'seedColor': seedColor,
        'dynamicColorFromCover': dynamicColorFromCover,
        'uiScale': uiScale,
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
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T pick<T>(String k, T def) => j[k] is T ? j[k] as T : def;
    return AppSettings(
      themeMode: ThemeMode.values.asNameMap()[j['themeMode']] ?? d.themeMode,
      seedColor: pick('seedColor', d.seedColor),
      dynamicColorFromCover: pick('dynamicColorFromCover', d.dynamicColorFromCover),
      uiScale: (j['uiScale'] as num?)?.toDouble() ?? d.uiScale,
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
