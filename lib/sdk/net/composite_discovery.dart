/// Running more than one discovery transport at once, and showing one list.
///
/// The two transports fail on different networks, which is the argument for
/// having both rather than choosing. UDP broadcast is refused outright on iOS
/// without the multicast entitlement, and plenty of routers drop directed
/// broadcast while carrying mDNS happily; equally, some corporate and guest
/// networks filter mDNS while letting broadcast through. Listening both ways
/// turns two partial answers into one.
///
/// Merging is free because [GameBeacon.id] was already the identity — it was
/// chosen so a host that changes IP mid-lobby would not appear twice, and the
/// same property means a game heard over both transports appears once.
library;

import 'dart:async';

import 'discovery.dart';

/// Advertises through several transports at once.
///
/// [failure] is reported only when **every** transport failed. One working
/// announcement is a game that can be found, and telling the host their game
/// could not be announced because one of two routes was refused would be a lie
/// the lobby then repeats to the user.
class CompositeGameAdvertiser implements GameAdvertiser {
  CompositeGameAdvertiser(this.transports);

  final List<GameAdvertiser> transports;

  @override
  Future<void> start() async {
    await Future.wait(transports.map((t) => t.start()));
  }

  @override
  void update({int? players, bool? open, List<String>? rejoinable}) {
    for (final transport in transports) {
      transport.update(players: players, open: open, rejoinable: rejoinable);
    }
  }

  @override
  String? get failure {
    final failures = transports.map((t) => t.failure).nonNulls.toList();
    if (failures.length < transports.length) return null;
    return failures.join('; ');
  }

  @override
  void dispose() {
    for (final transport in transports) {
      transport.dispose();
    }
  }
}

/// One list, fed by several finders.
///
/// Deliberately not a [GameBeacon] cache of its own: each source keeps its own
/// bookkeeping — the UDP finder times sightings out, the Bonjour finder is told
/// when a service goes away — and this reads across them on demand. That way a
/// game disappearing from one source disappears here too, without this class
/// having to model expiry a second time and get it subtly different.
class CompositeGameFinder extends GameFinder {
  CompositeGameFinder(this.sources) {
    for (final source in sources) {
      source.addListener(notifyListeners);
    }
  }

  final List<GameFinder> sources;

  @override
  Future<void> start() async {
    await Future.wait(sources.map((s) => s.start()));
    notifyListeners();
  }

  /// The union, keyed by [GameBeacon.id], most recently heard wins.
  ///
  /// Two transports carrying the same game will disagree about the details for
  /// a moment — the Bonjour advertiser deliberately lets a stale player count
  /// ride rather than republish for it, so its copy is often the older one.
  /// Taking the freshest sighting resolves that the way a human would expect.
  @override
  List<GameBeacon> get games {
    final merged = <String, GameBeacon>{};
    for (final source in sources) {
      for (final beacon in source.games) {
        final existing = merged[beacon.id];
        if (existing == null || beacon.seenAt.isAfter(existing.seenAt)) {
          merged[beacon.id] = beacon;
        }
      }
    }
    final list = merged.values.toList()
      ..sort((a, b) {
        final byOpen = (b.open ? 1 : 0).compareTo(a.open ? 1 : 0);
        if (byOpen != 0) return byOpen;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return List.unmodifiable(list);
  }

  @override
  void refresh() {
    for (final source in sources) {
      source.refresh();
    }
  }

  /// Non-null only when nothing is looking.
  ///
  /// This is what the join sheet turns into "we cannot search this network", so
  /// it has to mean that. On an iPhone the UDP source fails every time and the
  /// Bonjour one carries the list — saying discovery had failed there would be
  /// wrong, and would point people at the QR code they do not need.
  @override
  String? get failure {
    final failures = sources.map((s) => s.failure).nonNulls.toList();
    if (failures.length < sources.length) return null;
    return failures.join('; ');
  }

  @override
  void dispose() {
    for (final source in sources) {
      source.removeListener(notifyListeners);
      source.dispose();
    }
    super.dispose();
  }
}
