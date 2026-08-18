/// Discovery over UDP broadcast: the original transport, and the only one that
/// works on Android with no extra permission.
///
/// A host shouts a small JSON beacon onto the subnet once a second; phones on
/// the "join" screen listen for it and build a live list.
///
/// **The iOS caveat this file cannot fix.** Since iOS 14, sending or receiving
/// broadcast and multicast UDP requires the `com.apple.developer.networking
/// .multicast` entitlement, which Apple grants only on request. Without it the
/// sends here are refused and the list stays empty on iPhone. That is not a bug
/// to chase: every failure path below is written to fail quietly and leave
/// hosting and joining working through the QR code and the typed address. A
/// Bonjour transport, which iOS allows without any entitlement, is the way to
/// fill that list — see [GameFinder] for where it would plug in.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'discovery.dart';

/// Fixed UDP port both sides bind. Separate from the WebSocket port so the
/// beacon keeps working while the game socket is busy.
const int kDiscoveryPort = 41234;

/// How often a host re-announces itself.
const Duration kBeaconInterval = Duration(seconds: 1);

/// Drop a game from the list if we have not heard from it in this long. Four
/// missed beacons — long enough to survive a dropped packet, short enough that
/// a closed game disappears while you are still looking at the screen.
///
/// Note this is a UDP-shaped idea: it exists because a broadcast that stops
/// says nothing. A transport that is told when a service goes away has no use
/// for it, which is why it lives here and not in the contract.
const Duration kBeaconTimeout = Duration(seconds: 4);

/// Host side: announces the game until disposed.
///
/// Every failure mode here is non-fatal. On iOS 14+ broadcasting needs the
/// multicast entitlement, and on locked-down networks the packets go nowhere —
/// in both cases hosting must still work, with the QR and typed address as the
/// way in. [failure] records why, so the lobby can say so out loud.
class UdpGameAdvertiser implements GameAdvertiser {
  UdpGameAdvertiser({
    required this.id,
    required this.name,
    required this.address,
    this.port = kDiscoveryPort,
  });

  final String id;
  final String name;

  /// The WebSocket address joiners should use.
  final Uri address;
  final int port;

  RawDatagramSocket? _socket;
  Timer? _timer;
  int _players = 0;
  bool _open = true;
  List<String> _rejoinable = const [];
  int _consecutiveFailures = 0;

  /// Non-null when discovery could not start. Hosting is unaffected.
  @override
  String? get failure => _failure;
  String? _failure;

  bool get running => _socket != null;

  /// Give up after this many refusals in a row. A flapping interface deserves
  /// another go; an OS that will never allow broadcast deserves silence rather
  /// than an error every second for the rest of the session.
  static const int _maxConsecutiveFailures = 3;

  @override
  Future<void> start() async {
    try {
      final socket = await _bind(port);
      socket.broadcastEnabled = true;
      _socket = socket;
      // Learn the subnet broadcast addresses; the first datagram goes out on
      // 255.255.255.255 regardless, so this never delays anything.
      unawaited(_refreshLocalIPs());
      // Answer probes immediately: a joiner opening the list should not wait
      // out our next scheduled beacon before seeing the game.
      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          final dg = socket.receive();
          if (dg == null) return;
          if (_isProbe(dg.data)) _send();
        },
        // A refused send does NOT throw at the call site — the OS error is
        // reported here, asynchronously, well after `send` has returned. This
        // handler is the only thing standing between "this network will not
        // carry our beacon" and an unhandled exception that takes the host
        // down with it.
        onError: _handleSocketError,
        cancelOnError: false,
      );
      _timer = Timer.periodic(kBeaconInterval, (_) => _send());
      _send();
    } on Object catch (e) {
      _failure = '$e';
    }
  }

  void _handleSocketError(Object error) {
    _consecutiveFailures++;
    if (_consecutiveFailures < _maxConsecutiveFailures) return;
    _failure = '$error';
    // Stop beaconing, keep the socket: hosting carries on, the lobby says the
    // game could not be announced, and the QR does the job instead.
    _timer?.cancel();
    _timer = null;
  }

  /// Keeps the advertised player count and joinability current.
  @override
  void update({int? players, bool? open, List<String>? rejoinable}) {
    if (players != null) _players = players;
    if (open != null) _open = open;
    if (rejoinable != null) _rejoinable = rejoinable;
  }

  void _send() {
    final socket = _socket;
    if (socket == null) return;
    final beacon = GameBeacon(
      id: id,
      name: name,
      uri: address,
      players: _players,
      rejoinable: _rejoinable,
      open: _open,
      seenAt: DateTime.now(),
    );
    final bytes = utf8.encode(jsonEncode(beacon.toJson()));
    _sendToBroadcastTargets(socket, bytes, port);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// Joiner side: a live list of games heard on this network.
///
/// Purely passive. Listening costs nothing and tells the hosts nothing, apart
/// from the single probe sent at startup to skip the first beacon interval.
class UdpGameFinder extends GameFinder {
  UdpGameFinder({this.port = kDiscoveryPort});

  final int port;

  RawDatagramSocket? _socket;
  Timer? _prune;
  final _byId = <String, GameBeacon>{};

  /// Non-null when we could not listen at all — the UI should then point at
  /// the QR and typed-address fallbacks rather than spinning forever.
  @override
  String? get failure => _failure;
  String? _failure;

  /// Set when the outgoing probe was refused. Diagnostic only: listening is
  /// the half that matters, and it may well still be working.
  String? get probeFailure => _probeFailure;
  String? _probeFailure;

  /// Games heard recently, most players first, then alphabetical so the list
  /// does not reshuffle itself under the user's thumb every second.
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
      final socket = await _bind(port);
      socket.broadcastEnabled = true;
      _socket = socket;
      // Learn the subnet broadcast addresses; the first datagram goes out on
      // 255.255.255.255 regardless, so this never delays anything.
      unawaited(_refreshLocalIPs());
      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          final dg = socket.receive();
          if (dg == null) return;
          final beacon = GameBeacon.tryParse(dg.data);
          if (beacon == null) return;
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
        },
        // A refused probe arrives here rather than at the call site, and it is
        // not fatal: a machine that may not transmit can still hear beacons.
        // Recorded, never surfaced as "cannot search the network".
        onError: (Object e) => _probeFailure = '$e',
        cancelOnError: false,
      );
      _probe();
      _prune = Timer.periodic(kBeaconInterval, (_) => _pruneStale());
    } on Object catch (e) {
      _failure = '$e';
      notifyListeners();
    }
  }

  /// Asks any host within earshot to beacon right now.
  ///
  /// Entirely optional. If the probe cannot go out we simply wait for the next
  /// scheduled beacon — *receiving* is the half that matters here, and it can
  /// work fine on a machine that is not allowed to transmit.
  void _probe() {
    final socket = _socket;
    if (socket == null) return;
    _sendToBroadcastTargets(
      socket,
      utf8.encode(jsonEncode({'app': kBeaconMagic, 'probe': true})),
      port,
    );
  }

  /// Re-probe, for a pull-to-refresh or a "not seeing it?" tap.
  @override
  void refresh() {
    _pruneStale();
    _probe();
  }

  void _pruneStale() {
    final cutoff = DateTime.now().subtract(kBeaconTimeout);
    final before = _byId.length;
    _byId.removeWhere((_, b) => b.seenAt.isBefore(cutoff));
    if (_byId.length != before) notifyListeners();
  }

  @override
  void dispose() {
    _prune?.cancel();
    _socket?.close();
    _socket = null;
    super.dispose();
  }
}

/// Sends one datagram to every address worth trying.
///
/// `255.255.255.255` is the obvious one, but plenty of networks and stacks drop
/// it while happily carrying a subnet-directed broadcast like `192.168.1.255`.
/// Dart does not expose interface netmasks, so the subnet targets are derived
/// by assuming a /24 — wrong for an unusual netmask, harmless when it is (the
/// datagram simply goes nowhere), and right on essentially every home network.
///
/// Failures are not reported here at all. A refused send surfaces asynchronously
/// on the socket's own stream, which is where both sides handle it.
void _sendToBroadcastTargets(RawDatagramSocket socket, List<int> bytes,
    int port) {
  for (final target in _broadcastTargets) {
    try {
      socket.send(bytes, target, port);
    } on Object {
      // Keep going: one dead interface must not stop the others.
    }
  }
}

/// Cached because it hits the interface list, and it changes rarely.
List<InternetAddress> get _broadcastTargets {
  final now = DateTime.now();
  final cached = _cachedTargets;
  if (cached != null &&
      now.difference(_targetsComputedAt) < const Duration(seconds: 30)) {
    return cached;
  }
  final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
  for (final ip in _lastKnownLocalIPv4) {
    final parts = ip.split('.');
    if (parts.length != 4) continue;
    try {
      targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
    } on Object {
      // Not a usable address; skip it.
    }
  }
  _cachedTargets = targets;
  _targetsComputedAt = now;
  return targets;
}

List<InternetAddress>? _cachedTargets;
DateTime _targetsComputedAt = DateTime.fromMillisecondsSinceEpoch(0);

/// Local IPv4 addresses, refreshed in the background so building the target
/// list never blocks a beacon.
List<String> _lastKnownLocalIPv4 = const [];
bool _refreshingIPs = false;

Future<void> _refreshLocalIPs() async {
  if (_refreshingIPs) return;
  _refreshingIPs = true;
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    _lastKnownLocalIPv4 = [
      for (final i in interfaces)
        for (final a in i.addresses) a.address,
    ];
    _cachedTargets = null; // Recompute with the fresh list.
  } on Object {
    // Keep whatever we had; the limited broadcast address still works.
  } finally {
    _refreshingIPs = false;
  }
}

/// Binds the shared discovery port.
///
/// Host and joiner both want it, and on a single device (or one desktop running
/// two copies while you test) they have to coexist — hence reusePort.
///
/// Windows does not implement the option: it logs a line to stderr, ignores it,
/// and binds anyway, which is why that message shows up in dev runs and is
/// nothing to chase. Platforms that refuse harder throw, and get a plain bind.
Future<RawDatagramSocket> _bind(int port) async {
  try {
    return await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
      reusePort: true,
    );
  } on Object {
    return RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
  }
}

bool _isProbe(List<int> data) {
  if (data.length > 512) return false;
  try {
    final decoded = jsonDecode(utf8.decode(data));
    return decoded is Map<String, dynamic> &&
        decoded['app'] == kBeaconMagic &&
        decoded['probe'] == true;
  } on Object {
    return false;
  }
}
