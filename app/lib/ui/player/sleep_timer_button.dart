import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../../player/sleep_timer.dart';

String _clock(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Botão do timer para dormir: lua cheia quando ligado, com o tempo que falta.
class SleepTimerButton extends ConsumerStatefulWidget {
  const SleepTimerButton({super.key});

  @override
  ConsumerState<SleepTimerButton> createState() => _SleepTimerButtonState();
}

class _SleepTimerButtonState extends ConsumerState<SleepTimerButton> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final st = ref.watch(sleepTimerProvider);
    // Relógio da contagem só enquanto ligado.
    if (st.active && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!st.active && _tick != null) {
      _tick?.cancel();
      _tick = null;
    }
    final left = ref.read(sleepTimerProvider.notifier).remaining();
    final label = !st.active
        ? l10n.sleepTimer
        : st.endOfTrack
            ? l10n.sleepTimerEndOfTrackActive
            : l10n.sleepTimerActive(_clock(left ?? Duration.zero));
    final color = st.active ? Theme.of(context).colorScheme.primary : null;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showSleepTimerSheet(context),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(st.active ? Icons.bedtime : Icons.bedtime_outlined, color: color),
                if (st.active && !st.endOfTrack && left != null) ...[
                  const SizedBox(width: 4),
                  Text(_clock(left),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opções do timer: minutos prontos, fim da música, mais 10 min, desligar.
Future<void> showSleepTimerSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final l10n = context.l10n;
        final st = ref.watch(sleepTimerProvider);
        final timer = ref.read(sleepTimerProvider.notifier);
        final hasTrack = ref.watch(playerProvider.select((s) => s.current != null));
        void pick(VoidCallback f) {
          f();
          Navigator.pop(context);
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(l10n.sleepTimer, style: Theme.of(context).textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(l10n.sleepTimerHint, style: Theme.of(context).textTheme.bodySmall),
              ),
              if (st.active) ...[
                ListTile(
                  leading: const Icon(Icons.more_time),
                  title: Text(l10n.sleepTimerAdd10),
                  onTap: () => pick(() => timer.extend(const Duration(minutes: 10))),
                ),
                ListTile(
                  leading: const Icon(Icons.timer_off_outlined),
                  title: Text(l10n.sleepTimerOff),
                  onTap: () => pick(timer.cancel),
                ),
                const Divider(),
              ],
              for (final m in const [15, 30, 45, 60, 90])
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(l10n.sleepTimerMinutes(m)),
                  onTap: () => pick(() => timer.start(Duration(minutes: m))),
                ),
              ListTile(
                leading: const Icon(Icons.last_page),
                title: Text(l10n.sleepTimerEndOfTrack),
                enabled: hasTrack,
                onTap: () => pick(timer.startEndOfTrack),
              ),
            ],
          ),
        );
      }),
    );
