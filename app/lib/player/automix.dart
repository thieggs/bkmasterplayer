import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/settings.dart';
import '../src/rust/api/engine.dart' as engine;

/// Copia os modelos de análise (assets) para uma pasta do app, que o motor
/// lê direto do disco (no Android os assets ficam dentro do APK).
Future<Directory> prepareModels() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/models');
  await dir.create(recursive: true);
  for (final name in ['mel_spectrogram.onnx', 'beat_this_small.onnx']) {
    final file = File('${dir.path}/$name');
    final data = await rootBundle.load('assets/models/$name');
    if (!await file.exists() || await file.length() != data.lengthInBytes) {
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    }
  }
  return dir;
}

engine.AutomixConfig automixConfig(AppSettings s) => engine.AutomixConfig(
      style: switch (s.automixStyle) {
        MixStyleSetting.auto => engine.AutomixStyle.auto,
        MixStyleSetting.bassSwap => engine.AutomixStyle.bassSwap,
        MixStyleSetting.blend => engine.AutomixStyle.blend,
        MixStyleSetting.filter => engine.AutomixStyle.filter,
        MixStyleSetting.echo => engine.AutomixStyle.echo,
        MixStyleSetting.cut => engine.AutomixStyle.cut,
      },
      maxTempoChange: s.automixMaxTempo / 100,
      preferredBars: s.automixBars,
      minBars: 4,
      maxSeconds: s.automixMaxSeconds,
      unclearSeconds: s.automixUnclearSeconds,
      harmonic: s.automixHarmonic,
      tempoRampBars: s.automixRampBars,
      trimSilence: s.automixTrimSilence,
    );

/// Resolve "automático" pela potência do aparelho (e se o completo foi baixado).
Future<String> resolveModel(AppSettings s) async {
  switch (s.analysisModel) {
    case AnalysisModelSetting.small:
      return 'small';
    case AnalysisModelSetting.full:
      return 'full';
    case AnalysisModelSetting.auto:
      final p = await engine.playerDeviceProfile();
      return p.recommendedModel == 'full' && p.fullModelDownloaded ? 'full' : 'small';
  }
}

Future<void> applyAutomix(AppSettings s) async {
  engine.playerSetAutomix(config: automixConfig(s));
  await engine.playerSetAnalysisModel(model: await resolveModel(s));
}
