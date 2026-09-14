import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'jam_core.dart';

/// Permissões da Jam por Bluetooth/Wi-Fi Direct (Android). Sem o transporte
/// Nearby (desktop), a Jam usa só a rede local e não precisa de nada.
Future<void> ensureJamPermissions() async {
  if (!Platform.isAndroid || jamNearby == null) return;
  int sdk = 33;
  try {
    sdk = await const MethodChannel('bkplayer/system').invokeMethod<int>('sdkInt') ?? 33;
  } catch (_) {}
  await [
    if (sdk >= 31) ...[Permission.bluetoothScan, Permission.bluetoothAdvertise, Permission.bluetoothConnect],
    if (sdk >= 33) Permission.nearbyWifiDevices,
    // Até o Android 12 a busca por Bluetooth exige localização.
    if (sdk < 33) Permission.locationWhenInUse,
    Permission.notification,
  ].request();
}
