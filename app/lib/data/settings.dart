import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReplayGainMode { off, track, album, auto }

enum LoopMode { off, all, one }

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
