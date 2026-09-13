import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferências de aparência e layout (customização completa). Guardadas à
/// parte das configurações de áudio para poderem ser exportadas/importadas
/// como um "perfil visual".
@immutable
class UiPrefs {
  const UiPrefs({
    this.amoled = false,
    this.radius = 12,
    this.density = 'auto',
    this.coverShape = 'rounded',
    this.nowPlayingLayout = 'side',
    this.nowPlayingBlur = 0.6,
    this.sidebar = 'auto',
    this.startPage = '/',
    this.showQueue = false,
    this.cardSize = 'medium',
    this.playerButtons = const ['shuffle', 'repeat', 'favorite', 'mix', 'eq', 'lyrics', 'queue', 'volume'],
    this.homeSections = const ['newest', 'recent', 'frequent', 'random'],
    this.songTap = 'playFromHere',
    this.customColor,
  });

  /// Fundo preto puro no tema escuro (telas OLED).
  final bool amoled;

  /// Arredondamento dos cantos (0 = quadrado).
  final double radius;

  /// auto | compact | standard | comfortable
  final String density;

  /// square | rounded | circle
  final String coverShape;

  /// side (capa + fila/letra) | lyrics (capa + letra) | minimal | vinyl
  final String nowPlayingLayout;

  /// Intensidade do fundo desfocado da capa (0 a 1).
  final double nowPlayingBlur;

  /// auto | expanded | rail
  final String sidebar;
  final String startPage;
  final bool showQueue;

  /// small | medium | large
  final String cardSize;

  /// Botões visíveis (e na ordem) na barra do player.
  final List<String> playerButtons;

  /// Seções do Início, na ordem.
  final List<String> homeSections;

  /// playFromHere | playOne | enqueue
  final String songTap;

  /// Cor de destaque livre (ARGB), além da paleta.
  final int? customColor;

  static const allPlayerButtons = ['shuffle', 'repeat', 'favorite', 'mix', 'eq', 'lyrics', 'queue', 'volume'];
  static const allHomeSections = ['newest', 'recent', 'frequent', 'random', 'starred', 'highest'];

  double get cardWidth => switch (cardSize) {
        'small' => 140,
        'large' => 230,
        _ => 175,
      };

  double coverRadius(double size) => switch (coverShape) {
        'square' => 0,
        'circle' => size / 2,
        _ => (radius * 0.6).clamp(0.0, size / 2),
      };

  UiPrefs copyWith({
    bool? amoled,
    double? radius,
    String? density,
    String? coverShape,
    String? nowPlayingLayout,
    double? nowPlayingBlur,
    String? sidebar,
    String? startPage,
    bool? showQueue,
    String? cardSize,
    List<String>? playerButtons,
    List<String>? homeSections,
    String? songTap,
    int? customColor,
    bool clearCustomColor = false,
  }) =>
      UiPrefs(
        amoled: amoled ?? this.amoled,
        radius: radius ?? this.radius,
        density: density ?? this.density,
        coverShape: coverShape ?? this.coverShape,
        nowPlayingLayout: nowPlayingLayout ?? this.nowPlayingLayout,
        nowPlayingBlur: nowPlayingBlur ?? this.nowPlayingBlur,
        sidebar: sidebar ?? this.sidebar,
        startPage: startPage ?? this.startPage,
        showQueue: showQueue ?? this.showQueue,
        cardSize: cardSize ?? this.cardSize,
        playerButtons: playerButtons ?? this.playerButtons,
        homeSections: homeSections ?? this.homeSections,
        songTap: songTap ?? this.songTap,
        customColor: clearCustomColor ? null : (customColor ?? this.customColor),
      );

  Map<String, dynamic> toJson() => {
        'amoled': amoled,
        'radius': radius,
        'density': density,
        'coverShape': coverShape,
        'nowPlayingLayout': nowPlayingLayout,
        'nowPlayingBlur': nowPlayingBlur,
        'sidebar': sidebar,
        'startPage': startPage,
        'showQueue': showQueue,
        'cardSize': cardSize,
        'playerButtons': playerButtons,
        'homeSections': homeSections,
        'songTap': songTap,
        'customColor': customColor,
      };

  factory UiPrefs.fromJson(Map<String, dynamic> j) {
    const d = UiPrefs();
    T pick<T>(String k, T def) => j[k] is T ? j[k] as T : def;
    List<String> strings(String k, List<String> def, List<String> allowed) {
      final v = j[k];
      if (v is! List) return def;
      return v.whereType<String>().where(allowed.contains).toList();
    }

    return UiPrefs(
      amoled: pick('amoled', d.amoled),
      radius: (j['radius'] as num?)?.toDouble().clamp(0, 28) ?? d.radius,
      density: pick('density', d.density),
      coverShape: pick('coverShape', d.coverShape),
      nowPlayingLayout: pick('nowPlayingLayout', d.nowPlayingLayout),
      nowPlayingBlur: (j['nowPlayingBlur'] as num?)?.toDouble().clamp(0, 1) ?? d.nowPlayingBlur,
      sidebar: pick('sidebar', d.sidebar),
      startPage: pick('startPage', d.startPage),
      showQueue: pick('showQueue', d.showQueue),
      cardSize: pick('cardSize', d.cardSize),
      playerButtons: strings('playerButtons', d.playerButtons, allPlayerButtons),
      homeSections: strings('homeSections', d.homeSections, allHomeSections),
      songTap: pick('songTap', d.songTap),
      customColor: j['customColor'] is int ? j['customColor'] as int : null,
    );
  }

  static const _key = 'ui';

  static UiPrefs load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return const UiPrefs();
    try {
      return UiPrefs.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const UiPrefs();
    }
  }

  Future<void> save(SharedPreferences prefs) => prefs.setString(_key, jsonEncode(toJson()));
}
