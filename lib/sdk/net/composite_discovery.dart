library;

import 'dart:async';

import 'discovery.dart';

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

class CompositeGameFinder extends GameFinder {
  CompositeGameFinder(this.sources) {
    for (final source in sources) {
      source.addListener(notifyListeners);
    }
  }

  final List<GameFinder> sources;
  bool _disposed = false;

  @override
  Future<void> start() async {
    await Future.wait(sources.map((s) => s.start()));

    if (!_disposed) notifyListeners();
  }

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

  @override
  String? get failure {
    final failures = sources.map((s) => s.failure).nonNulls.toList();
    if (failures.length < sources.length) return null;
    return failures.join('; ');
  }

  @override
  void dispose() {
    _disposed = true;
    for (final source in sources) {
      source.removeListener(notifyListeners);
      source.dispose();
    }
    super.dispose();
  }
}
