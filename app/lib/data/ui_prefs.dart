import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aparência e estrutura das telas (personalização gráfica).
///
/// O "tema" são os campos de aparência e estrutura ([themeJson]): é o que a
/// galeria salva, exporta e aplica. Comportamento ([startPage], [showQueue],
/// [songTap]) e o tema escolhido ([themeId]) ficam de fora e não mudam quando
/// se troca de tema.
@immutable
class UiPrefs {
  const UiPrefs({
    this.themeMode = 'dark',
    this.colorSource = 'cover',
    this.seed = 0xFF7C4DFF,
    this.variant = 'tonalSpot',
    this.contrast = 0.0,
    this.amoled = false,
    this.colors = const {},
    this.bodyFont = 'system',
    this.titleFont = 'system',
    this.radius = 12,
    this.coverShape = 'rounded',
    this.buttonStyle = 'filled',
    this.cardStyle = 'flat',
    this.density = 'auto',
    this.uiScale = 1.0,
    this.cardSize = 'medium',
    this.background = 'solid',
    this.backgroundImage,
    this.backgroundDim = 0.6,
    this.nowPlayingLayout = 'side',
    this.nowPlayingBlur = 0.6,
    this.vinylScratch = true,
    this.vinylScratchAudio = true,
    this.vinylMaxSpeed = defaultVinylMaxSpeed,
    this.vinylSecondsPerTurn = defaultVinylSecondsPerTurn,
    this.vinylMemory = 0,
    this.vinylGlide = defaultVinylGlide,
    this.vinylGlideCurve = 'vinyl',
    this.sidebar = 'auto',
    this.sidebarTabs = defaultSidebarTabs,
    this.mobileTabs = defaultMobileTabs,
    this.navLabels = 'auto',
    this.playerStyle = 'docked',
    this.playerButtons = allPlayerButtons,
    this.homeSections = const ['newest', 'recent', 'frequent', 'random'],
    this.transitions = 'default',
    this.animations = 'normal',
    this.startPage = '/',
    this.showQueue = false,
    this.songTap = 'playFromHere',
    this.themeId,
  });

  // ---- Cores ----

  /// system | light | dark
  final String themeMode;

  /// cover (cor tirada da capa que toca) | accent (cor fixa [seed])
  final String colorSource;

  /// Cor base da paleta (ARGB).
  final int seed;

  /// Estilo da paleta: nome de um `DynamicSchemeVariant` (tonalSpot, vibrant…).
  final String variant;

  /// Contraste da paleta, de -1 (suave) a 1 (máximo).
  final double contrast;

  /// Fundo preto puro no tema escuro (telas OLED).
  final bool amoled;

  /// Cores trocadas à mão por cima da paleta: primary, secondary, tertiary,
  /// background, text (ARGB).
  final Map<String, int> colors;

  // ---- Fontes ----

  /// system | nunito | spaceGrotesk | jetbrainsMono (texto)
  final String bodyFont;

  /// Fontes do texto e também playfair | bebas (títulos).
  final String titleFont;

  // ---- Formas e tamanhos ----

  /// Arredondamento dos cantos (0 = quadrado).
  final double radius;

  /// square | rounded | circle
  final String coverShape;

  /// filled | tonal | outlined
  final String buttonStyle;

  /// flat | elevated | outlined
  final String cardStyle;

  /// auto | compact | standard | comfortable
  final String density;

  /// Escala da interface (texto).
  final double uiScale;

  /// small | medium | large
  final String cardSize;

  // ---- Fundo ----

  /// solid | gradient | cover (capa desfocada) | image
  final String background;

  /// Imagem de fundo (nome do arquivo na pasta de imagens dos temas).
  final String? backgroundImage;

  /// Quanto a cor do tema cobre a capa/imagem do fundo (0 a 1): legibilidade.
  final double backgroundDim;

  // ---- Tocando agora ----

  /// side (capa + fila/letra) | lyrics (capa + letra) | minimal | vinyl
  final String nowPlayingLayout;

  /// Intensidade do fundo desfocado da capa (0 a 1).
  final double nowPlayingBlur;

  /// No layout vinil: girar o disco com o dedo adianta e volta a música.
  /// Quem quer só a capa redonda de vinil, sem a mecânica, desliga aqui.
  final bool vinylScratch;

  /// O som segue o giro (o tom sobe e desce, e volta de trás para frente) em
  /// vez de a música só emudecer enquanto se procura o ponto.
  final bool vinylScratchAudio;

  /// Acima de quantas vezes a velocidade normal a agulha levanta (vira
  /// chiado). Zero = sem limite, para quem quiser ouvir o giro inteiro.
  final double vinylMaxSpeed;

  /// Quanto de música anda numa volta do disco. O padrão é o de um LP de
  /// 33⅓ RPM, então girar no ritmo de um disco de verdade sai no tom certo.
  final double vinylSecondsPerTurn;

  /// Quantos segundos de música dá para voltar girando o disco. Zero = a
  /// música inteira (até onde o teto de RAM do motor deixa). Guardar custa
  /// memória: a 48 kHz, cada minuto são uns 11 MB.
  final double vinylMemory;

  /// Quantos segundos o disco leva para voltar à velocidade normal depois que
  /// o dedo sai. Zero = para na hora. Quanto mais forte o arremesso, mais
  /// longe ele carrega — como num disco de verdade.
  final double vinylGlide;

  /// Curva da desaceleração: vinyl (freia forte e vai encostando) | linear |
  /// brake (desliza solto e trava no fim).
  final String vinylGlideCurve;

  // ---- Estrutura ----

  /// auto | expanded | rail
  final String sidebar;

  /// Abas da barra lateral (computador/tablet), na ordem.
  final List<String> sidebarTabs;

  /// Abas da barra de baixo do celular, na ordem (Ajustes fica sempre no fim).
  final List<String> mobileTabs;

  /// Rótulos das abas: auto (como o app vem) | all | selected | none
  final String navLabels;

  /// docked (grudado embaixo) | floating (cartão flutuante)
  final String playerStyle;

  /// Botões visíveis (e na ordem) na barra do player.
  final List<String> playerButtons;

  /// Seções do Início, na ordem.
  final List<String> homeSections;

  // ---- Animações ----

  /// default | fade | slide | none (troca de telas)
  final String transitions;

  /// normal | fast | off
  final String animations;

  // ---- Comportamento (fora do tema) ----

  final String startPage;
  final bool showQueue;

  /// playFromHere | playOne | enqueue
  final String songTap;

  /// Tema da galeria aplicado por último (null = nenhum).
  final String? themeId;

  static const allPlayerButtons = ['shuffle', 'repeat', 'favorite', 'mix', 'eq', 'lyrics', 'queue', 'sleep', 'devices', 'mini', 'volume'];
  static const allHomeSections = ['newest', 'recent', 'frequent', 'random', 'starred', 'highest'];
  static const allTabs = ['home', 'search', 'library', 'albums', 'songs', 'artists', 'playlists', 'genres', 'generate', 'favorites', 'downloads'];
  static const defaultSidebarTabs = ['home', 'search', 'albums', 'songs', 'artists', 'playlists', 'genres', 'generate', 'favorites', 'downloads'];
  static const defaultMobileTabs = ['home', 'search', 'library'];
  static const bodyFonts = ['system', 'nunito', 'spaceGrotesk', 'jetbrainsMono'];
  static const titleFonts = ['system', 'nunito', 'spaceGrotesk', 'jetbrainsMono', 'playfair', 'bebas'];
  static const variants = ['tonalSpot', 'fidelity', 'monochrome', 'neutral', 'vibrant', 'expressive', 'content', 'rainbow', 'fruitSalad'];
  static const colorKeys = ['primary', 'secondary', 'tertiary', 'background', 'text'];

  /// No celular: de 2 a 4 abas além de Ajustes.
  static const maxMobileTabs = 4;

  /// Limite da agulha do vinil: o padrão e a faixa do controle. Zero, fora
  /// dela, quer dizer sem limite.
  static const defaultVinylMaxSpeed = 4.0;
  static const minVinylMaxSpeed = 2.0;
  static const maxVinylMaxSpeed = 16.0;

  /// Segundos de música por volta do disco: o padrão é a volta de um LP de
  /// 33⅓ RPM (1,8 s), a mesma de um disco de verdade.
  /// Opções de "quanto dá para voltar girando", em segundos (0 = a música
  /// inteira).
  static const vinylMemoryChoices = [0.0, 12.0, 60.0, 180.0];

  /// Deslize do disco ao soltar o dedo, em segundos (0 = para na hora).
  static const defaultVinylGlide = 0.6;
  static const maxVinylGlide = 3.0;
  static const glideCurves = ['vinyl', 'linear', 'brake'];

  static const defaultVinylSecondsPerTurn = 1.8;
  static const minVinylSecondsPerTurn = 0.1;
  static const maxVinylSecondsPerTurn = 4.0;

  /// Família da fonte (null = a do sistema).
  static String? fontFamily(String font) => switch (font) {
        'nunito' => 'Nunito',
        'spaceGrotesk' => 'Space Grotesk',
        'jetbrainsMono' => 'JetBrains Mono',
        'playfair' => 'Playfair Display',
        'bebas' => 'Bebas Neue',
        _ => null,
      };

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

  Duration get animationDuration => switch (animations) {
        'off' => Duration.zero,
        'fast' => const Duration(milliseconds: 200),
        _ => const Duration(milliseconds: 600),
      };

  UiPrefs copyWith({
    String? themeMode,
    String? colorSource,
    int? seed,
    String? variant,
    double? contrast,
    bool? amoled,
    Map<String, int>? colors,
    String? bodyFont,
    String? titleFont,
    double? radius,
    String? coverShape,
    String? buttonStyle,
    String? cardStyle,
    String? density,
    double? uiScale,
    String? cardSize,
    String? background,
    String? backgroundImage,
    bool clearBackgroundImage = false,
    double? backgroundDim,
    String? nowPlayingLayout,
    double? nowPlayingBlur,
    bool? vinylScratch,
    bool? vinylScratchAudio,
    double? vinylMaxSpeed,
    double? vinylSecondsPerTurn,
    double? vinylMemory,
    double? vinylGlide,
    String? vinylGlideCurve,
    String? sidebar,
    List<String>? sidebarTabs,
    List<String>? mobileTabs,
    String? navLabels,
    String? playerStyle,
    List<String>? playerButtons,
    List<String>? homeSections,
    String? transitions,
    String? animations,
    String? startPage,
    bool? showQueue,
    String? songTap,
    String? themeId,
    bool clearThemeId = false,
  }) =>
      UiPrefs(
        themeMode: themeMode ?? this.themeMode,
        colorSource: colorSource ?? this.colorSource,
        seed: seed ?? this.seed,
        variant: variant ?? this.variant,
        contrast: contrast ?? this.contrast,
        amoled: amoled ?? this.amoled,
        colors: colors ?? this.colors,
        bodyFont: bodyFont ?? this.bodyFont,
        titleFont: titleFont ?? this.titleFont,
        radius: radius ?? this.radius,
        coverShape: coverShape ?? this.coverShape,
        buttonStyle: buttonStyle ?? this.buttonStyle,
        cardStyle: cardStyle ?? this.cardStyle,
        density: density ?? this.density,
        uiScale: uiScale ?? this.uiScale,
        cardSize: cardSize ?? this.cardSize,
        background: background ?? this.background,
        backgroundImage: clearBackgroundImage ? null : (backgroundImage ?? this.backgroundImage),
        backgroundDim: backgroundDim ?? this.backgroundDim,
        nowPlayingLayout: nowPlayingLayout ?? this.nowPlayingLayout,
        nowPlayingBlur: nowPlayingBlur ?? this.nowPlayingBlur,
        vinylScratch: vinylScratch ?? this.vinylScratch,
        vinylScratchAudio: vinylScratchAudio ?? this.vinylScratchAudio,
        vinylMaxSpeed: vinylMaxSpeed ?? this.vinylMaxSpeed,
        vinylSecondsPerTurn: vinylSecondsPerTurn ?? this.vinylSecondsPerTurn,
        vinylMemory: vinylMemory ?? this.vinylMemory,
        vinylGlide: vinylGlide ?? this.vinylGlide,
        vinylGlideCurve: vinylGlideCurve ?? this.vinylGlideCurve,
        sidebar: sidebar ?? this.sidebar,
        sidebarTabs: sidebarTabs ?? this.sidebarTabs,
        mobileTabs: mobileTabs ?? this.mobileTabs,
        navLabels: navLabels ?? this.navLabels,
        playerStyle: playerStyle ?? this.playerStyle,
        playerButtons: playerButtons ?? this.playerButtons,
        homeSections: homeSections ?? this.homeSections,
        transitions: transitions ?? this.transitions,
        animations: animations ?? this.animations,
        startPage: startPage ?? this.startPage,
        showQueue: showQueue ?? this.showQueue,
        songTap: songTap ?? this.songTap,
        themeId: clearThemeId ? null : (themeId ?? this.themeId),
      );

  /// Só o tema (aparência + estrutura): o que a galeria guarda e exporta.
  Map<String, dynamic> themeJson() => {
        'themeMode': themeMode,
        'colorSource': colorSource,
        'seed': seed,
        'variant': variant,
        'contrast': contrast,
        'amoled': amoled,
        'colors': {for (final k in colorKeys) if (colors[k] != null) k: colors[k]},
        'bodyFont': bodyFont,
        'titleFont': titleFont,
        'radius': radius,
        'coverShape': coverShape,
        'buttonStyle': buttonStyle,
        'cardStyle': cardStyle,
        'density': density,
        'uiScale': uiScale,
        'cardSize': cardSize,
        'background': background,
        'backgroundImage': backgroundImage,
        'backgroundDim': backgroundDim,
        'nowPlayingLayout': nowPlayingLayout,
        'nowPlayingBlur': nowPlayingBlur,
        'vinylScratch': vinylScratch,
        'vinylScratchAudio': vinylScratchAudio,
        'vinylMaxSpeed': vinylMaxSpeed,
        'vinylSecondsPerTurn': vinylSecondsPerTurn,
        'vinylMemory': vinylMemory,
        'vinylGlide': vinylGlide,
        'vinylGlideCurve': vinylGlideCurve,
        'sidebar': sidebar,
        'sidebarTabs': sidebarTabs,
        'mobileTabs': mobileTabs,
        'navLabels': navLabels,
        'playerStyle': playerStyle,
        'playerButtons': playerButtons,
        'playerButtonsVersion': 3,
        'homeSections': homeSections,
        'transitions': transitions,
        'animations': animations,
      };

  Map<String, dynamic> toJson() => {
        ...themeJson(),
        'themeVersion': 2,
        'startPage': startPage,
        'showQueue': showQueue,
        'songTap': songTap,
        'themeId': themeId,
      };

  /// Aplica um tema (mapa de [themeJson]) mantendo o comportamento. Campos que
  /// faltam no tema voltam ao padrão; valores inválidos são ignorados.
  UiPrefs withTheme(Map<String, dynamic> theme, {String? id}) {
    final t = UiPrefs.fromJson({...theme, 'themeVersion': 2});
    return t.copyWith(startPage: startPage, showQueue: showQueue, songTap: songTap, themeId: id, clearThemeId: id == null);
  }

  /// O tema desta preferência é igual a [other] (ignora comportamento)?
  bool sameTheme(Map<String, dynamic> other) =>
      jsonEncode(themeJson()) == jsonEncode(UiPrefs.fromJson({...other, 'themeVersion': 2}).themeJson());

  factory UiPrefs.fromJson(Map<String, dynamic> j) {
    const d = UiPrefs();
    String one(String k, String def, List<String> allowed) {
      final v = j[k];
      return v is String && allowed.contains(v) ? v : def;
    }

    // Sem `as num?`: num tema escrito à mão o campo pode vir como texto, e o
    // molde estouraria em vez de cair no padrão.
    double num_(String k, double def, double min, double max) {
      final v = j[k];
      return v is num ? v.toDouble().clamp(min, max) : def;
    }
    List<String> strings(String k, List<String> def, List<String> allowed) {
      final v = j[k];
      if (v is! List) return def;
      final out = <String>[];
      for (final e in v) {
        if (e is String && allowed.contains(e) && !out.contains(e)) out.add(e);
      }
      return out;
    }

    final colors = <String, int>{};
    if (j['colors'] is Map) {
      (j['colors'] as Map).forEach((k, v) {
        if (k is String && colorKeys.contains(k) && v is int) colors[k] = v;
      });
    }
    // Zero é "sem limite" e não cabe na faixa do controle: passa direto.
    double vinylSpeed() {
      final v = j['vinylMaxSpeed'];
      if (v is! num) return d.vinylMaxSpeed;
      return v <= 0 ? 0 : v.toDouble().clamp(minVinylMaxSpeed, maxVinylMaxSpeed);
    }

    final sidebarTabs = strings('sidebarTabs', d.sidebarTabs, allTabs.where((t) => t != 'library').toList());
    final mobileTabs = strings('mobileTabs', d.mobileTabs, allTabs).take(maxMobileTabs).toList();
    final bg = j['backgroundImage'];

    return UiPrefs(
      themeMode: one('themeMode', d.themeMode, const ['system', 'light', 'dark']),
      colorSource: one('colorSource', d.colorSource, const ['cover', 'accent']),
      // Versão 1 guardava a cor livre em "customColor".
      seed: j['seed'] is int ? j['seed'] as int : (j['customColor'] is int ? j['customColor'] as int : d.seed),
      variant: one('variant', d.variant, variants),
      contrast: num_('contrast', d.contrast, -1, 1),
      amoled: j['amoled'] is bool ? j['amoled'] as bool : d.amoled,
      colors: colors,
      bodyFont: one('bodyFont', d.bodyFont, bodyFonts),
      titleFont: one('titleFont', d.titleFont, titleFonts),
      radius: num_('radius', d.radius, 0, 28),
      coverShape: one('coverShape', d.coverShape, const ['square', 'rounded', 'circle']),
      buttonStyle: one('buttonStyle', d.buttonStyle, const ['filled', 'tonal', 'outlined']),
      cardStyle: one('cardStyle', d.cardStyle, const ['flat', 'elevated', 'outlined']),
      density: one('density', d.density, const ['auto', 'compact', 'standard', 'comfortable']),
      uiScale: num_('uiScale', d.uiScale, 0.8, 1.5),
      cardSize: one('cardSize', d.cardSize, const ['small', 'medium', 'large']),
      background: one('background', d.background, const ['solid', 'gradient', 'cover', 'image']),
      // Só um nome de arquivo (nunca um caminho vindo de um tema importado).
      backgroundImage: bg is String && RegExp(r'^[\w-][\w.-]{0,79}$').hasMatch(bg) ? bg : null,
      backgroundDim: num_('backgroundDim', d.backgroundDim, 0, 1),
      nowPlayingLayout: one('nowPlayingLayout', d.nowPlayingLayout, const ['side', 'lyrics', 'minimal', 'vinyl']),
      nowPlayingBlur: num_('nowPlayingBlur', d.nowPlayingBlur, 0, 1),
      vinylScratch: j['vinylScratch'] is bool ? j['vinylScratch'] as bool : d.vinylScratch,
      vinylScratchAudio: j['vinylScratchAudio'] is bool ? j['vinylScratchAudio'] as bool : d.vinylScratchAudio,
      vinylMaxSpeed: vinylSpeed(),
      vinylSecondsPerTurn: num_('vinylSecondsPerTurn', d.vinylSecondsPerTurn, minVinylSecondsPerTurn, maxVinylSecondsPerTurn),
      vinylMemory: num_('vinylMemory', d.vinylMemory, 0, 600),
      vinylGlide: num_('vinylGlide', d.vinylGlide, 0, maxVinylGlide),
      vinylGlideCurve: one('vinylGlideCurve', d.vinylGlideCurve, glideCurves),
      sidebar: one('sidebar', d.sidebar, const ['auto', 'expanded', 'rail']),
      sidebarTabs: sidebarTabs.isEmpty ? d.sidebarTabs : sidebarTabs,
      mobileTabs: mobileTabs.length < 2 ? d.mobileTabs : mobileTabs,
      navLabels: one('navLabels', d.navLabels, const ['auto', 'all', 'selected', 'none']),
      playerStyle: one('playerStyle', d.playerStyle, const ['docked', 'floating']),
      playerButtons: _withNewButtons(strings('playerButtons', d.playerButtons, allPlayerButtons), j),
      homeSections: strings('homeSections', d.homeSections, allHomeSections),
      transitions: one('transitions', d.transitions, const ['default', 'fade', 'slide', 'none']),
      animations: one('animations', d.animations, const ['normal', 'fast', 'off']),
      startPage: j['startPage'] is String ? j['startPage'] as String : d.startPage,
      showQueue: j['showQueue'] is bool ? j['showQueue'] as bool : d.showQueue,
      songTap: one('songTap', d.songTap, const ['playFromHere', 'playOne', 'enqueue']),
      themeId: j['themeId'] is String ? j['themeId'] as String : null,
    );
  }

  /// Botões que surgiram depois de a lista ter sido salva entram no lugar
  /// padrão (quem tirou um botão depois disso não o vê voltar).
  static List<String> _withNewButtons(List<String> buttons, Map<String, dynamic> j) {
    final version = j['playerButtonsVersion'] as int? ?? 1;
    if (j['playerButtons'] is! List) return buttons;
    final out = List.of(buttons);
    void add(String b, String before) {
      if (out.contains(b)) return;
      final at = out.indexOf(before);
      out.insert(at >= 0 ? at : (out.contains('volume') ? out.indexOf('volume') : out.length), b);
    }

    if (version < 2) add('devices', 'mini');
    if (version < 3) add('sleep', 'devices');
    return out;
  }

  static const _key = 'ui';

  /// Versão 1 (e perfis exportados nela): modo, cor, cor da capa e escala
  /// ficavam nas configurações gerais ([old]); junta ao mapa da aparência.
  static Map<String, dynamic> mergeLegacy(Map<String, dynamic> ui, Map old) => {
        ...ui,
        if (old['themeMode'] is String) 'themeMode': old['themeMode'],
        if (ui['customColor'] is! int && old['seedColor'] is int) 'seed': old['seedColor'],
        if (old['dynamicColorFromCover'] is bool) 'colorSource': old['dynamicColorFromCover'] == true ? 'cover' : 'accent',
        if (old['uiScale'] is num) 'uiScale': old['uiScale'],
      };

  /// Carrega; na primeira vez depois da versão 2, traz das configurações
  /// antigas o modo claro/escuro, a cor, a cor da capa e a escala.
  static UiPrefs load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    Map<String, dynamic> j = {};
    try {
      if (raw != null) j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {}
    if (j['themeVersion'] != 2) {
      try {
        j = mergeLegacy(j, jsonDecode(prefs.getString('settings') ?? '{}') as Map);
      } catch (_) {}
      final migrated = UiPrefs.fromJson(j);
      migrated.save(prefs);
      return migrated;
    }
    return UiPrefs.fromJson(j);
  }

  Future<void> save(SharedPreferences prefs) => prefs.setString(_key, jsonEncode(toJson()));
}
