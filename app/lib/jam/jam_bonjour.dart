import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../connect/connect_service.dart';

/// Tipo de serviço desta Festa na rede. Tem que bater com o `NSBonjourServices`
/// do Info.plist do iOS, senão a Apple não deixa procurar.
const jamServiceType = '_bkjam._tcp';

/// Anuncia e procura Festas por Bonjour (mDNS/DNS-SD).
///
/// **Por que, já tendo o broadcast UDP:**
/// - No iPhone, broadcast cru exige a permissão de multicast, que só sai com
///   conta paga da Apple e ainda passa por análise. Bonjour com um tipo
///   declarado é liberado.
/// - Wi-Fi de hotel e de empresa costuma filtrar broadcast e deixar mDNS passar.
/// - Quem responde é o sistema operacional, não o app: o anúncio não morre
///   quando o Android manda o app para segundo plano.
///
/// O protocolo é padrão aberto (RFC 6762/6763), então iPhone, Android, Linux,
/// Windows e Mac se enxergam entre si — não é coisa da Apple.
class JamBonjour {
  BonsoirBroadcast? _anuncio;
  BonsoirDiscovery? _busca;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;

  /// Festas achadas agora, por nome do serviço.
  final _achadas = <String, LanJamOffer>{};

  /// Começa a anunciar esta Festa. Chamar de novo troca o anúncio.
  Future<void> advertise({
    required String deviceId,
    required String jamId,
    required String name,
    required int port,
  }) async {
    await stopAdvertising();
    try {
      final b = BonsoirBroadcast(
        service: BonsoirService(
          name: name.isEmpty ? 'Festa' : name,
          type: jamServiceType,
          port: port,
          // Os mesmos campos do anúncio por UDP, para os dois caminhos
          // produzirem ofertas iguais.
          attributes: {'id': deviceId, 'jid': jamId, 'n': name},
        ),
      );
      await b.initialize();
      await b.start();
      _anuncio = b;
    } catch (e) {
      debugPrint('Bonjour: não deu para anunciar: $e');
    }
  }

  Future<void> stopAdvertising() async {
    final b = _anuncio;
    _anuncio = null;
    if (b == null) return;
    try {
      await b.stop();
    } catch (_) {}
  }

  /// Procura Festas. [aoMudar] recebe a lista inteira a cada novidade.
  Future<void> discover(void Function(List<LanJamOffer>) aoMudar) async {
    if (_busca != null) return;
    try {
      final d = BonsoirDiscovery(type: jamServiceType);
      await d.initialize();
      _busca = d;
      _sub = d.eventStream?.listen((e) {
        final s = e.service;
        if (s == null) return;
        switch (e) {
          // "Achou" traz só o nome; o endereço vem no "resolveu".
          case BonsoirDiscoveryServiceFoundEvent():
            unawaited(s.resolve(d.serviceResolver));
          case BonsoirDiscoveryServiceResolvedEvent():
            final o = _paraOferta(s);
            if (o != null) {
              _achadas[s.name] = o;
              aoMudar(_achadas.values.toList());
            }
          case BonsoirDiscoveryServiceLostEvent():
            if (_achadas.remove(s.name) != null) aoMudar(_achadas.values.toList());
          default:
            break;
        }
      });
      await d.start();
    } catch (e) {
      debugPrint('Bonjour: não deu para procurar: $e');
      _busca = null;
    }
  }

  LanJamOffer? _paraOferta(BonsoirService s) {
    final host = s.hostAddresses.isNotEmpty ? s.hostAddresses.first : s.hostname;
    if (host == null || host.isEmpty) return null;
    final a = s.attributes;
    return LanJamOffer(
      deviceId: a['id'] ?? 'bonjour:${s.name}',
      jamId: a['jid'] ?? 'bonjour',
      name: a['n']?.isNotEmpty == true ? a['n']! : s.name,
      host: host,
      port: s.port,
      seen: DateTime.now(),
    );
  }

  Future<void> stopDiscovery() async {
    final d = _busca;
    _busca = null;
    await _sub?.cancel();
    _sub = null;
    _achadas.clear();
    if (d == null) return;
    try {
      await d.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stopAdvertising();
    await stopDiscovery();
  }
}
