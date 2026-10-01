library;

import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import 'discovery.dart';

const String kBonjourServiceType = '_bubblegames._tcp';

const Duration _kRepublishDebounce = Duration(seconds: 1);

class BonjourGameAdvertiser implements GameAdvertiser {
  BonjourGameAdvertiser({
    required this.id,
    required this.name,
    required this.address,
  });

  final String id;
  final String name;

  final Uri address;

  BonsoirBroadcast? _broadcast;
  Timer? _debounce;
  bool _disposed = false;

  Future<void> _work = Future<void>.value();

  int _players = 0;
  bool _open = true;
  List<String> _rejoinable = const [];

  @override
  String? get failure => _failure;
  String? _failure;

  @override
  Future<void> start() => _work = _work.then((_) => _publish());

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
      } catch (_) {}
      if (_disposed) return;
      await _publish();
    });
  }

  Future<void> _publish() async {
    if (_disposed) return;
    try {
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
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

    _work = _work.then((_) async {
      final broadcast = _broadcast;
      _broadcast = null;
      try {
        await broadcast?.stop();
      } catch (_) {}
    });
  }
}

class BonjourGameFinder extends GameFinder {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;

  final _byId = <String, GameBeacon>{};

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

  bool _disposed = false;

  @override
  Future<void> start() async {
    try {
      final discovery = BonsoirDiscovery(type: kBonjourServiceType);
      await discovery.initialize();

      if (_disposed) {
        await _stopQuietly(discovery);
        return;
      }
      _discovery = discovery;
      _sub = discovery.eventStream?.listen(
        _onEvent,
        onError: (Object e) {
          _failure = '$e';
          if (!_disposed) notifyListeners();
        },
        cancelOnError: false,
      );
      await discovery.start();

      if (_disposed) await _stopQuietly(discovery);
    } on Object catch (e) {
      _failure = '$e';
      if (!_disposed) notifyListeners();
    }
  }

  static Future<void> _stopQuietly(BonsoirDiscovery discovery) async {
    try {
      await discovery.stop();
    } catch (_) {}
  }

  void _onEvent(BonsoirDiscoveryEvent event) {
    if (_disposed) return;
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        final discovery = _discovery;
        if (discovery != null) {
          event.service.resolve(discovery.serviceResolver);
        }
      case BonsoirDiscoveryServiceResolvedEvent():
        _upsert(event.service);
      case BonsoirDiscoveryServiceUpdatedEvent():
        _upsert(event.service);
      case BonsoirDiscoveryServiceLostEvent():
        _remove(event.service);
      default:
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

  @override
  void refresh() {}

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    final discovery = _discovery;
    if (discovery != null) unawaited(_stopQuietly(discovery));
    _discovery = null;
    super.dispose();
  }
}
