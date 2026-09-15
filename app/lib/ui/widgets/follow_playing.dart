import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../player/player_controller.dart';

/// Faz uma lista acompanhar a música que está tocando: quando ela troca, a
/// lista rola até a nova (um pouco abaixo do topo, com a anterior à vista).
///
/// Não briga com a pessoa: se ela rolou a lista há pouco ([pause]), fica onde
/// está; com [onlyIfVisible], só segue quando a música anterior estava na tela
/// (quem foi olhar outra parte da lista não é puxado de volta).
class PlayingFollower {
  PlayingFollower({this.onlyIfVisible = false, this.pause = const Duration(seconds: 6)});

  final bool onlyIfVisible;
  final Duration pause;
  final controller = ScrollController();
  final _keys = <int, GlobalKey>{};
  DateTime _userAt = DateTime.fromMillisecondsSinceEpoch(0);
  int? _index;

  /// Onde a música tocando fica na tela (0 = topo, 1 = embaixo).
  static const alignment = 0.2;

  /// Chave da linha [i] (listas em que cada linha tem a sua; ver [scrollToRow]).
  GlobalKey keyFor(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  /// Para um `NotificationListener<ScrollNotification>` em volta da lista.
  bool onNotification(ScrollNotification n) {
    if (n is UserScrollNotification && n.direction != ScrollDirection.idle) _userAt = DateTime.now();
    return false;
  }

  void dispose() => controller.dispose();

  /// A cada build: [index] é a posição da música tocando nesta lista (null =
  /// ela não está aqui). [showOnOpen]: na primeira vez já rola até ela.
  /// [scroll] faz a rolagem (ex.: [scrollToRow] ou uma conta por altura fixa).
  void update(int? index, {bool showOnOpen = false, required void Function(int index, {required bool animate}) scroll}) {
    final prev = _index;
    _index = index;
    if (index == null || index == prev) return;
    if (prev == null && !showOnOpen) return;
    // Visível agora, com o layout do quadro anterior (antes de a lista mudar).
    final wasVisible = prev == null || !onlyIfVisible || _rowVisible(prev);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_index != index || !controller.hasClients) return;
      if (prev != null && DateTime.now().difference(_userAt) < pause) return;
      if (!wasVisible) return;
      scroll(index, animate: prev != null);
    });
  }

  bool _rowVisible(int i) {
    final ctx = _keys[i]?.currentContext;
    final box = ctx?.findRenderObject();
    if (ctx == null || box is! RenderBox || !box.attached) return false;
    final scrollBox = Scrollable.maybeOf(ctx)?.context.findRenderObject();
    if (scrollBox is! RenderBox) return false;
    final top = box.localToGlobal(Offset.zero, ancestor: scrollBox).dy;
    return top + box.size.height > 0 && top < scrollBox.size.height;
  }

  /// Rola até a linha [i] usando as chaves de [keyFor]. Se ela ainda não foi
  /// montada (longe da tela), estima pela altura de uma linha que foi e acerta
  /// quando chegar perto.
  void scrollToRow(int i, {required bool animate, bool refine = true}) {
    if (!controller.hasClients) return;
    final pos = controller.position;
    double? target;
    final ctx = _keys[i]?.currentContext;
    final box = ctx?.findRenderObject();
    if (box is RenderBox && box.attached) {
      target = RenderAbstractViewport.of(box).getOffsetToReveal(box, alignment).offset;
    } else {
      for (final e in _keys.entries) {
        final other = e.value.currentContext?.findRenderObject();
        if (other is RenderBox && other.attached) {
          final base = RenderAbstractViewport.of(other).getOffsetToReveal(other, alignment).offset;
          target = base + (i - e.key) * other.size.height;
          break;
        }
      }
    }
    if (target == null) return;
    target = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() < 2) return;
    final estimated = !(box is RenderBox && box.attached);
    void again() {
      if (refine && estimated && _index == i) scrollToRow(i, animate: false, refine: false);
    }

    if (animate) {
      controller.animateTo(target, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic).then((_) => again());
    } else {
      controller.jumpTo(target);
      WidgetsBinding.instance.addPostFrameCallback((_) => again());
    }
  }

  /// Rola até a linha [i] de uma lista com todas as linhas da mesma altura e
  /// sem nada antes delas (a altura sai do tamanho total do conteúdo).
  void scrollToFixedRow(int i, int count, {required bool animate}) {
    if (!controller.hasClients || count == 0) return;
    final pos = controller.position;
    final extent = (pos.maxScrollExtent + pos.viewportDimension) / count;
    final target = (i * extent - alignment * (pos.viewportDimension - extent)).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() < 2) return;
    if (animate) {
      controller.animateTo(target, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    } else {
      controller.jumpTo(target);
    }
  }
}

/// Página com uma lista de músicas (álbum, playlist) que acompanha a que está
/// tocando: se ela é uma destas e troca enquanto a anterior está na tela, a
/// lista rola até a nova. O [builder] monta a lista com `follow.controller` e
/// cada música dentro de `KeyedSubtree(key: follow.keyFor(i), …)`.
class FollowPlayingScope extends ConsumerStatefulWidget {
  const FollowPlayingScope({super.key, required this.songs, required this.builder});

  final List<Song> songs;
  final Widget Function(BuildContext context, PlayingFollower follow) builder;

  @override
  ConsumerState<FollowPlayingScope> createState() => _FollowPlayingScopeState();
}

class _FollowPlayingScopeState extends ConsumerState<FollowPlayingScope> {
  final _follow = PlayingFollower(onlyIfVisible: true);

  @override
  void dispose() {
    _follow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentId = ref.watch(playerProvider.select((s) => s.current?.song.id));
    final i = currentId == null ? -1 : widget.songs.indexWhere((s) => s.id == currentId);
    _follow.update(i < 0 ? null : i, scroll: _follow.scrollToRow);
    return NotificationListener<ScrollNotification>(
      onNotification: _follow.onNotification,
      child: widget.builder(context, _follow),
    );
  }
}
