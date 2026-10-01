library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'discovery.dart';

const int kDiscoveryPort = 41234;

const Duration kBeaconInterval = Duration(seconds: 1);

const Duration kBeaconTimeout = Duration(seconds: 4);

class UdpGameAdvertiser implements GameAdvertiser {
  UdpGameAdvertiser({
    required this.id,
    required this.name,
    required this.address,
    this.port = kDiscoveryPort,
  });

  final String id;
  final String name;

  final Uri address;
  final int port;

  RawDatagramSocket? _socket;
  Timer? _timer;
  int _players = 0;
  bool _open = true;
  List<String> _rejoinable = const [];
  bool _disposed = false;

  int _consecutiveFailures = 0;

  int _sentLastBeacon = 0;
  int _refusedLastBeacon = 0;

  @override
  String? get failure => _failure;
  String? _failure;

  bool get running => _socket != null;

  static const int _maxConsecutiveFailures = 3;

  @override
  Future<void> start() async {
    try {
      final socket = await _bind(port);

      if (_disposed) {
        socket.close();
        return;
      }
      socket.broadcastEnabled = true;
      _socket = socket;

      unawaited(_refreshLocalIPs());

      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          final dg = socket.receive();
          if (dg == null) return;
          if (_isProbe(dg.data)) _send();
        },
        onError: _handleSocketError,
        cancelOnError: false,
      );
      _timer = Timer.periodic(kBeaconInterval, (_) {
        if (_judgeLastBeacon()) _send();
      });
      _send();
    } on Object catch (e) {
      _failure = '$e';
    }
  }

  void _handleSocketError(Object error) {
    _refusedLastBeacon++;
    _lastError = error;
  }

  Object? _lastError;

  bool _judgeLastBeacon() {
    final wentNowhere = _refusedLastBeacon >= _sentLastBeacon;
    _consecutiveFailures = wentNowhere ? _consecutiveFailures + 1 : 0;
    _sentLastBeacon = 0;
    _refusedLastBeacon = 0;
    if (_consecutiveFailures < _maxConsecutiveFailures) return true;
    _failure = '${_lastError ?? 'every broadcast was refused'}';
    _timer?.cancel();
    _timer = null;
    return false;
  }

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
    _sentLastBeacon += _sendToBroadcastTargets(socket, bytes, port);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

class UdpGameFinder extends GameFinder {
  UdpGameFinder({this.port = kDiscoveryPort});

  final int port;

  RawDatagramSocket? _socket;
  Timer? _prune;
  final _byId = <String, GameBeacon>{};
  bool _disposed = false;

  @override
  String? get failure => _failure;
  String? _failure;

  String? get probeFailure => _probeFailure;
  String? _probeFailure;

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

      if (_disposed) {
        socket.close();
        return;
      }
      socket.broadcastEnabled = true;
      _socket = socket;

      unawaited(_refreshLocalIPs());
      socket.listen(
        (event) {
          if (event != RawSocketEvent.read || _disposed) return;
          final dg = socket.receive();
          if (dg == null) return;
          final beacon = GameBeacon.tryParse(dg.data);
          if (beacon == null) return;
          final previous = _byId[beacon.id];
          _byId[beacon.id] = beacon;

          if (previous == null ||
              previous.name != beacon.name ||
              previous.players != beacon.players ||
              previous.open != beacon.open ||
              previous.uri != beacon.uri) {
            notifyListeners();
          }
        },
        onError: (Object e) => _probeFailure = '$e',
        cancelOnError: false,
      );
      _probe();
      _prune = Timer.periodic(kBeaconInterval, (_) => _pruneStale());
    } on Object catch (e) {
      _failure = '$e';
      if (!_disposed) notifyListeners();
    }
  }

  void _probe() {
    final socket = _socket;
    if (socket == null) return;
    _sendToBroadcastTargets(
      socket,
      utf8.encode(jsonEncode({'app': kBeaconMagic, 'probe': true})),
      port,
    );
  }

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
    _disposed = true;
    _prune?.cancel();
    _socket?.close();
    _socket = null;
    super.dispose();
  }
}

int _sendToBroadcastTargets(
  RawDatagramSocket socket,
  List<int> bytes,
  int port,
) {
  var sent = 0;
  for (final target in _broadcastTargets) {
    try {
      socket.send(bytes, target, port);
      sent++;
    } catch (_) {}
  }
  return sent;
}

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
    } catch (_) {}
  }
  _cachedTargets = targets;
  _targetsComputedAt = now;
  return targets;
}

List<InternetAddress>? _cachedTargets;
DateTime _targetsComputedAt = DateTime.fromMillisecondsSinceEpoch(0);

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
    _cachedTargets = null;
  } catch (_) {
  } finally {
    _refreshingIPs = false;
  }
}

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
