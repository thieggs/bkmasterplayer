import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../l10n/l10n.dart';

const eqBands = ['31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

/// Presets (dB por banda, 31 Hz → 16 kHz).
const eqPresets = <String, List<double>>{
  'flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  'bass': [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
  'treble': [0, 0, 0, 0, 0, 1, 2, 4, 5, 6],
  'vocal': [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1],
  'rock': [5, 4, 2, -1, -2, -1, 2, 3, 4, 4],
  'pop': [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2],
  'electronic': [5, 4, 1, 0, -2, 1, 0, 1, 4, 5],
  'jazz': [3, 2, 1, 2, -1, -1, 0, 1, 2, 3],
  'classical': [4, 3, 2, 1, -1, -1, 0, 2, 3, 4],
  'loudness': [6, 4, 0, 0, -2, 0, -1, 0, 5, 3],
  'headphones': [3, 2, 1, 0, -1, 0, 1, 2, 3, 2],
};

String presetName(BuildContext context, String key) {
  final l = context.l10n;
  return switch (key) {
    'flat' => l.eqFlat,
    'bass' => l.eqBass,
    'treble' => l.eqTreble,
    'vocal' => l.eqVocal,
    'rock' => 'Rock',
    'pop' => 'Pop',
    'electronic' => l.eqElectronic,
    'jazz' => 'Jazz',
    'classical' => l.eqClassical,
    'loudness' => l.eqLoudness,
    'headphones' => l.eqHeadphones,
    _ => l.eqCustom,
  };
}

class EqualizerPage extends ConsumerWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;
    final on = s.eqEnabled;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text(l10n.equalizer, style: theme.textTheme.headlineMedium)),
            Switch(value: on, onChanged: (v) => set((x) => x.copyWith(eqEnabled: v))),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in eqPresets.entries)
              ChoiceChip(
                label: Text(presetName(context, e.key)),
                selected: s.eqPreset == e.key,
                onSelected: on ? (_) => set((x) => x.copyWith(eqGains: List.of(e.value), eqPreset: e.key)) : null,
              ),
            if (s.eqPreset == 'custom') ChoiceChip(label: Text(l10n.eqCustom), selected: true, onSelected: null),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 280,
          child: Row(
            children: [
              for (var i = 0; i < 10; i++)
                Expanded(
                  child: Column(
                    children: [
                      Text('${s.eqGains[i] > 0 ? '+' : ''}${s.eqGains[i].toStringAsFixed(0)}', style: theme.textTheme.labelSmall),
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            value: s.eqGains[i].clamp(-12, 12),
                            min: -12,
                            max: 12,
                            divisions: 24,
                            onChanged: on
                                ? (v) {
                                    final g = List.of(s.eqGains)..[i] = v;
                                    set((x) => x.copyWith(eqGains: g, eqPreset: 'custom'));
                                  }
                                : null,
                          ),
                        ),
                      ),
                      Text(eqBands[i], style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          enabled: on,
          title: Text(l10n.preamp),
          subtitle: Slider(
            value: s.eqPreamp.clamp(-12, 12),
            min: -12,
            max: 12,
            divisions: 24,
            label: '${s.eqPreamp > 0 ? '+' : ''}${s.eqPreamp.toStringAsFixed(0)} dB',
            onChanged: on ? (v) => set((x) => x.copyWith(eqPreamp: v)) : null,
          ),
          trailing: Text('${s.eqPreamp > 0 ? '+' : ''}${s.eqPreamp.toStringAsFixed(0)} dB'),
        ),
        Text(l10n.eqHint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
