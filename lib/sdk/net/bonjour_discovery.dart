/// Discovery over Bonjour/mDNS: the transport iOS will actually run.
///
/// UDP broadcast is refused on iOS 14+ without the
/// `com.apple.developer.networking.multicast` entitlement, which Apple grants
/// only on request. Bonjour goes through the system's own mDNS responder, so it
/// needs no entitlement at all — just `NSBonjourServices` in `Info.plist`
/// naming [kBonjourServiceType], and the `NSLocalNetworkUsageDescription` the
/// app already carries.
///
/// **The constraint that shapes this file: a TXT record cannot be edited in
/// place.** Neither `bonsoir` nor any other wrapper exposes one, because the
/// platform APIs underneath do not — `BonsoirBroadcast.service` is `final`, and
/// changing what is advertised means stopping the broadcast and starting
/// another. Every republish makes the game blink out of and back into the join
/// lists watching it, which is worst precisely when players are arriving. So
/// [BonjourGameAdvertiser] republishes only for the things worth a blink, and
/// lets the rest ride along — see [update].
library;

import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import 'discovery.dart';

/// The service type this app advertises and browses for.
///
/// `_tcp` rather than `_udp` because the thing being advertised is the
/// WebSocket a joiner will connect to; the mDNS traffic that carries the
/// advertisement is the responder's business, not ours.
///
/// **Must match `NSBonjourServices` in `ios/Runner/Info.plist` exactly.** iOS 14+
/// will not browse a type the app did not declare, and it fails by finding
/// nothing rather than by complaining.
const String kBonjourServiceType = '_bubblegames._tcp';

/// How long to sit on a republish, gathering any others that follow it.
///
/// Seats fill in bursts — a table of six joins over a few seconds — and each
/// one that changes something republishable would otherwise be its own blink.
const Duration _kRepublishDebounce = Duration(seconds: 1);

/// Host side: advertises the game as a Bonjour service.
class BonjourGameAdvertiser implements GameAdvertiser {
  BonjourGameAdvertiser({
    required this.id,
    required this.name,
    required this.address,
  });

  final String id;
  final String name;

  /// The WebSocket address joiners should use. Also the source of the port the
  /// service is advertised on.
  final Uri address;

  BonsoirBroadcast? _broadcast;
  Timer? _debounce;
  bool _disposed = false;

  /// Guards against two republishes overlapping. `stop` then `start` is two
  /// awaits long, and a second update landing in the middle would leave two
  /// broadcasts alive advertising different things.
  Future<void> _work = Future<void>.value();

  int _players = 0;
  bool _open = true;
  List<String> _rejoinable = const [];

  @override
  String? get failure => _failure;
  String? _failure;

  @override
  Future<void> start() => _work = _work.then((_) => _publish());

  /// Records the new state, and republishes only when it is worth a blink.
  ///
  /// [players] alone never triggers one. It is a number in a list, it changes
  /// every time somebody sits down, and it costs a visible flicker to correct —
  /// so it waits and rides along on the next republish that happens for another
  /// reason. [open] going false happens once, when the game leaves the lobby,
  /// and a game that stops being joinable arguably *should* visibly change.
  /// [rejoinable] changes when somebody drops, which is rare and is the whole
  /// mechanism by which they get their seat back.
  @override
  void update({int? players, bool? open, List<String>? rejoinable}) {
    if (players != null) _players = players;

    var worthABlink = false;
    if (open != null && open != _open) {
      _open = open;
      worthABlink = true;
    }
    if (rejoinable != null && !_sameSeats(rejoinable, _rejoinable)) {
      _rejoinable = rejoinable;
      worthABlink = true;
    }
    if (!worthABlink || _disposed) return;

    _debounce?.cancel();
    _debounce = Timer(_kRepublishDebounce, _republish);
  }

  static bool _sameSeats(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _republish() {
    _work = _work.then((_) async {
      if (_disposed) return;
      final previous = _broadcast;
      _broadcast = null;
      try {
        await previous?.stop();
      } on Object {
        // Best effort. A responder that will not let go of the old service is
        // not a reason to skip advertising the new one.
      }
      if (_disposed) return;
      await _publish();
    });
  }

  Future<void> _publish() async {
    if (_disposed) return;
    try {
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
          // The beacon id, not the game name. Bonjour service names must be
          // unique on the network and a colliding one is silently renamed to
          // "… (2)" by the responder — harmless in itself, but the real name
          // travels in the attributes where nothing can rewrite it, so there is
          // nothing to gain by risking it here.
          name: id,
          type: kBonjourServiceType,
          port: address.port,
          attributes: _attributes(),
        ),
      );
      await broadcast.initialize();
      if (_disposed) {
        await broadcast.stop();
        return;
      }
      await broadcast.start();
      _broadcast = broadcast;
      _failure = null;
    } on Object catch (e) {
      // Like the UDP advertiser: never throw. A phone that cannot advertise can
      // still host, and the QR code is the way in.
      _failure = '$e';
    }
  }

  Map<String, String> _attributes() => {
    'app': kBeaconMagic,
    'id': id,
    'name': name,
    'ws': address.toString(),
    'players': '$_players',
    'open': _open ? '1' : '0',
    if (_rejoinable.isNotEmpty) 'rejoin': _rejoinable.join(','),
  };

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    final broadcast = _broadcast;
    _broadcast = null;
    _work = _work.then((_) async {
      try {
        await broadcast?.stop();
      } on Object {
        // Nothing useful to do while tearing down.
      }
    });
  }
}

/// Joiner side: a live list built from Bonjour service events.
///
/// Push-based, unlike its UDP counterpart. There is no beacon interval to wait
/// out and no staleness to time out: the responder says when a service appears
/// and says again when it goes away, so [games] is only ever wrong for as long
/// as mDNS takes to notice — which is its job, not ours.
class BonjourGameFinder extends GameFinder {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;

  final _byId = <String, GameBeacon>{};

  /// Bonjour identifies a service by its name; we identify a game by its beacon
  /// id. They are the same string today — [BonjourGameAdvertiser] advertises
  /// under the id — but a responder that renames a colliding service breaks
  /// that, and a lost event would then remove nothing. So the mapping is
  /// remembered at resolve time rather than assumed.
  final _idByServiceName = <String, String>{};

  @override
  String? get failure => _failure;
  String? _failure;

  @override
  List<GameBeacon> get games {
    final list = _byId.values.toList()
      ..sort((a, b) {
        final byOpen = (b.open ? 1 : 0).compareTo(a.open ? 1 : 0);
        if (byOpen != 0) return byOpen;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return List.unmodifiable(list);
  }

  @override
  Future<void> start() async {
    try {
      final discovery = BonsoirDiscovery(type: kBonjourServiceType);
      await discovery.initialize();
      _discovery = discovery;
      _sub = discovery.eventStream?.listen(
        _onEvent,
        // Same reasoning as the UDP finder: a fault on the stream must not take
        // down the sheet that is listening to it.
        onError: (Object e) => _failure = '$e',
        cancelOnError: false,
      );
      await discovery.start();
    } on Object catch (e) {
      _failure = '$e';
      notifyListeners();
    }
  }

  void _onEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        // A found service carries a name and not much else. Attributes — which
        // is where the entire beacon lives — arrive only once it is resolved.
        // Read through a local: a last event can land while dispose is pulling
        // the discovery out from under us.
        final discovery = _discovery;
        if (discovery != null) {
          event.service.resolve(discovery.serviceResolver);
        }
      case BonsoirDiscoveryServiceResolvedEvent():
        _upsert(event.service);
      case BonsoirDiscoveryServiceUpdatedEvent():
        // We never publish an update ourselves — see this file's header — but
        // another implementation might, and taking one when offered costs
        // nothing.
        _upsert(event.service);
      case BonsoirDiscoveryServiceLostEvent():
        _remove(event.service);
      default:
        // bonsoir's event hierarchy is sealed but growing; an unknown event is
        // not a reason to fail.
        break;
    }
  }

  void _upsert(BonsoirService? service) {
    if (service == null) return;
    final beacon = GameBeacon.tryFromAttributes(service.attributes);
    if (beacon == null) return;

    _idByServiceName[service.name] = beacon.id;
    final previous = _byId[beacon.id];
    _byId[beacon.id] = beacon;

    // Only repaint when something a human can see actually changed.
    if (previous == null ||
        previous.name != beacon.name ||
        previous.players != beacon.players ||
        previous.open != beacon.open ||
        previous.uri != beacon.uri) {
      notifyListeners();
    }
  }

  void _remove(BonsoirService? service) {
    if (service == null) return;
    final id = _idByServiceName.remove(service.name);
    if (id == null) return;
    if (_byId.remove(id) != null) notifyListeners();
  }

  /// Nothing to do. The responder pushes; there is no probe to re-send and no
  /// staleness to sweep, so a refresh here would only mean tearing down a
  /// working browse and building it again.
  @override
  void refresh() {}

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _discovery?.stop();
    _discovery = null;
    super.dispose();
  }
}
