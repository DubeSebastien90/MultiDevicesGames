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
/// Apple platforms and Android — every phone — for two different reasons.
///
/// On iOS it is not an optimisation, it is the only transport that works:
/// broadcast is refused without the multicast entitlement, so without this the
/// join list is simply always empty on iPhone.
///
/// On Android it is what lets an iPhone and an Android find each other at all.
/// Android's own games travel fine over UDP, but an iPhone can neither hear
/// that broadcast nor send one, so a table mixing the two needs a language both
/// speak — and Bonjour is the only one the iPhone has. UDP keeps running beside
/// it, so Android-to-Android discovery loses nothing on a network that filters
/// mDNS. `bonsoir` warns that attributes, where the whole beacon lives, do not
/// work on Android 6.0 and below; this app's minimum is Android 7 (API 24), so
/// no handset it installs on is affected.
///
/// Desktop stays on UDP alone: nobody hosts or joins a table from one outside
/// development, and there is no iPhone-shaped gap there to fill.
bool get bonjourWorthRunning =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.android;

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
