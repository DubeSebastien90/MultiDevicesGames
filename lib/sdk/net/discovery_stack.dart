library;

import 'package:flutter/foundation.dart';

import 'bonjour_discovery.dart';
import 'composite_discovery.dart';
import 'discovery.dart';
import 'udp_discovery.dart';

bool get bonjourWorthRunning =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.android;

GameAdvertiser createGameAdvertiser({
  required String id,
  required String name,
  required Uri address,
}) {
  final udp = UdpGameAdvertiser(id: id, name: name, address: address);
  if (!bonjourWorthRunning) return udp;
  return CompositeGameAdvertiser([
    udp,
    BonjourGameAdvertiser(id: id, name: name, address: address),
  ]);
}

GameFinder createGameFinder() {
  final udp = UdpGameFinder();
  if (!bonjourWorthRunning) return udp;
  return CompositeGameFinder([udp, BonjourGameFinder()]);
}
