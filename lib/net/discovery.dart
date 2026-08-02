/// LAN game discovery over UDP broadcast.
///
/// A host shouts a small JSON beacon onto the subnet once a second; phones on
/// the "join" screen listen for it and build a live list. Nothing connects — a
/// listener is a passive receiver, which is the whole point: you can see who is
/// hosting before committing to anything.
///
/// The beacon carries the game *name* and address, never the join code. The
/// name is how a human recognises the right game; the code is the secret that
/// proves they were invited, and it is checked by the host on the WebSocket
/// (see `HostSession`), not out here where anyone with a packet sniffer sits.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Fixed UDP port both sides bind. Separate from the WebSocket port so the
/// beacon keeps working while the game socket is busy.
const int kDiscoveryPort = 41234;

/// How often a host re-announces itself.
const Duration kBeaconInterval = Duration(seconds: 1);

/// Drop a game from the list if we have not heard from it in this long. Four
/// missed beacons — long enough to survive a dropped packet, short enough that
/// a closed game disappears while you are still looking at the screen.
const Duration kBeaconTimeout = Duration(seconds: 4);

/// Marks our datagrams so we ignore whatever else is broadcasting on this port.
const String _magic = 'mss1';

/// A fresh 5-digit join code. Leading zeros are kept, so all 100 000 are usable
/// and the code always looks the same length on screen.
String generateJoinCode([Random? random]) {
  final r = random ?? Random.secure();
  return r.nextInt(100000).toString().padLeft(5, '0');
}

/// True if [input] could be a join code — exactly five digits.
bool isValidJoinCode(String input) => RegExp(r'^\d{5}$').hasMatch(input);

/// One host heard on the network.
@immutable
class GameBeacon {
  const GameBeacon({
    required this.id,
    required this.name,
    required this.uri,
    required this.players,
    required this.open,
    required this.seenAt,
  });

  /// Stable per-host-session id. Keyed on this rather than the address so a
  /// host that changes IP mid-lobby does not appear twice.
  final String id;

  /// What the host called the game. Display only, and untrusted — see [name]'s
  /// sanitising in [tryParse].
  final String name;

  /// Where to connect once the joiner has the code.
  final Uri uri;

  final int players;

  /// False once the game has left the lobby; still listed, but not joinable.
  final bool open;

  final DateTime seenAt;

  Map<String, dynamic> toJson() => {
    'app': _magic,
    'id': id,
    'name': name,
    'ws': uri.toString(),
    'players': players,
    'open': open,
  };

  /// Parses a received datagram, or returns null for anything unrecognised.
  ///
  /// Every field is treated as hostile: this arrives from an unauthenticated
  /// stranger on the network and goes straight into a list widget.
  static GameBeacon? tryParse(List<int> data, {DateTime? now}) {
    if (data.length > 2048) return null;
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['app'] != _magic) return null;
      if (decoded['probe'] == true) return null;

      final id = decoded['id'];
      final ws = decoded['ws'];
      if (id is! String || id.isEmpty || id.length > 64) return null;
      if (ws is! String) return null;

      final uri = Uri.tryParse(ws);
      if (uri == null || uri.host.isEmpty) return null;
      if (uri.scheme != 'ws' && uri.scheme != 'wss') return null;

      var name = (decoded['name'] as String?) ?? 'Game';
      // Strip control characters and cap the length so a malicious beacon
      // cannot draw newlines or a wall of text into the join list.
      name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
      if (name.isEmpty) name = 'Game';
      if (name.length > 40) name = name.substring(0, 40);

      return GameBeacon(
        id: id,
        name: name,
        uri: uri,
        players: ((decoded['players'] as num?)?.toInt() ?? 0).clamp(0, 99),
        open: decoded['open'] as bool? ?? true,
        seenAt: now ?? DateTime.now(),
      );
    } on Object {
      return null;
    }
  }
}

/// Host side: announces the game until disposed.
///
/// Every failure mode here is non-fatal. On iOS 14+ broadcasting needs the
/// multicast entitlement, and on locked-down networks the packets go nowhere —
/// in both cases hosting must still work, with the QR and typed address as the
/// way in. [failure] records why, so the lobby can say so out loud.
class DiscoveryBroadcaster {
  DiscoveryBroadcaster({
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
  int _consecutiveFailures = 0;

  /// Non-null when discovery could not start. Hosting is unaffected.
  String? get failure => _failure;
  String? _failure;

  bool get running => _socket != null;

  /// Give up after this many refusals in a row. A flapping interface deserves
  /// another go; an OS that will never allow broadcast deserves silence rather
  /// than an error every second for the rest of the session.
  static const int _maxConsecutiveFailures = 3;

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
  void update({int? players, bool? open}) {
    if (players != null) _players = players;
    if (open != null) _open = open;
  }

  void _send() {
    final socket = _socket;
    if (socket == null) return;
    final beacon = GameBeacon(
      id: id,
      name: name,
      uri: address,
      players: _players,
      open: _open,
      seenAt: DateTime.now(),
    );
    final bytes = utf8.encode(jsonEncode(beacon.toJson()));
    _sendToBroadcastTargets(socket, bytes, port);
  }

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
class DiscoveryListener extends ChangeNotifier {
  DiscoveryListener({this.port = kDiscoveryPort});

  final int port;

  RawDatagramSocket? _socket;
  Timer? _prune;
  final _byId = <String, GameBeacon>{};

  /// Non-null when we could not listen at all — the UI should then point at
  /// the QR and typed-address fallbacks rather than spinning forever.
  String? get failure => _failure;
  String? _failure;

  /// Set when the outgoing probe was refused. Diagnostic only: listening is
  /// the half that matters, and it may well still be working.
  String? get probeFailure => _probeFailure;
  String? _probeFailure;

  /// Games heard recently, most players first, then alphabetical so the list
  /// does not reshuffle itself under the user's thumb every second.
  List<GameBeacon> get games {
    final list = _byId.values.toList()
      ..sort((a, b) {
        final byOpen = (b.open ? 1 : 0).compareTo(a.open ? 1 : 0);
        if (byOpen != 0) return byOpen;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return List.unmodifiable(list);
  }

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
      utf8.encode(jsonEncode({'app': _magic, 'probe': true})),
      port,
    );
  }

  /// Re-probe, for a pull-to-refresh or a "not seeing it?" tap.
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
        decoded['app'] == _magic &&
        decoded['probe'] == true;
  } on Object {
    return false;
  }
}
