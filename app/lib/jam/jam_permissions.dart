import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'jam_core.dart';
import 'jam_nearby.dart';

/// Permissões da Jam por Bluetooth/Wi-Fi Direct (Android). Sem o transporte
/// Nearby (desktop, ou celular sem Play Services), a Jam usa só a rede local e
/// não precisa de nada — a não ser que [bluetooth] (a chave do Bluetooth sem
/// Play Services) esteja ligada.
Future<void> ensureJamPermissions({bool bluetooth = false}) async {
  if (!Platform.isAndroid || (jamNearby == null && !bluetooth)) return;
  int sdk = 33;
  try {
    sdk = await const MethodChannel('bkplayer/system').invokeMethod<int>('sdkInt') ?? 33;
  } catch (_) {}
  await [
    if (sdk >= 31) ...[Permission.bluetoothScan, Permission.bluetoothAdvertise, Permission.bluetoothConnect],
    if (sdk >= 33) Permission.nearbyWifiDevices,
    // O Nearby do Google exige localização em qualquer versão: sem ela a
    // busca falha com MISSING_PERMISSION_ACCESS_COARSE_LOCATION (visto no
    // Android 16 do M35) e não acha ninguém.
    Permission.locationWhenInUse,
    Permission.notification,
  ].request();
}

/// Liga/desliga o aviso de Jam por perto (pede as permissões ao ligar).
Future<void> setJamNearbyAlerts(bool on) async {
  if (!Platform.isAndroid || jamNearby == null) return;
  if (on) await ensureJamPermissions();
  await NearbyJam.setBeaconScan(on);
}
