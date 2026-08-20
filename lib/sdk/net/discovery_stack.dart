/// Which discovery transports this device runs, and the only place that decides.
///
/// Both call sites — the host starting a beacon, the join sheet opening a list
/// — come through here, so the answer to "how does a game get found" is written
/// down once instead of being spread across the two screens that care.
library;

import 'package:flutter/foundation.dart';

import 'bonjour_discovery.dart';
import 'composite_discovery.dart';
import 'discovery.dart';
import 'udp_discovery.dart';

/// Whether to run Bonjour alongside UDP broadcast on this device.
///
/// Apple platforms only, and for two separate reasons rather than one.
///
/// On iOS it is not an optimisation, it is the only transport that works:
/// broadcast is refused without the multicast entitlement, so without this the
/// join list is simply always empty on iPhone.
///
/// Everywhere else it would be redundant at best. Android's UDP path works
/// today with permissions the app already holds, and `bonsoir` documents that
/// service attributes — which is where the whole beacon lives — "don't work on
/// Android 6.0 and below". Adding a second transport that carries no payload on
/// old handsets, to duplicate a first one that works, is how you acquire a bug
/// report you cannot reproduce.
bool get bonjourWorthRunning =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Announces a game through every transport this device can use.
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

/// Looks for games through every transport this device can use.
GameFinder createGameFinder() {
  final udp = UdpGameFinder();
  if (!bonjourWorthRunning) return udp;
  return CompositeGameFinder([udp, BonjourGameFinder()]);
}
