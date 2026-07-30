/// Networking boundary.
///
/// Game code never touches a socket. v1 implements these with QR + LAN
/// WebSockets; a cloud lobby, hotspot or Nearby/Multipeer can be dropped in
/// later by adding an implementation and nothing else.
library;

import 'dart:async';

/// The client side of a connection: one phone talking to the host.
abstract class Transport {
  Future<void> connect();
  void send(Map<String, dynamic> message);
  Stream<Map<String, dynamic>> get onMessage;
  Future<void> dispose();
}

/// The host's handle on one connected phone.
abstract class PeerLink {
  /// Human-readable origin, e.g. `192.168.1.42` or `this device`.
  String get debugName;
  Stream<Map<String, dynamic>> get onMessage;
  void send(Map<String, dynamic> message);
  Future<void> close();
}

/// The host side: accepts [PeerLink]s.
abstract class HostTransport {
  /// Starts listening and returns the address joiners should use.
  Future<Uri> start();
  Stream<PeerLink> get onPeer;
  Future<void> dispose();
}

/// A broadcast stream that holds events until somebody is listening.
///
/// A plain broadcast controller drops anything added before the first
/// subscription, which loses the handshake: the host sends `welcome` the instant
/// a peer attaches, often before the client has finished wiring up its listener.
/// The symptom is a session that connects and then just sits there. Queueing
/// removes that whole class of ordering bug.
class QueuedBroadcast<T> {
  QueuedBroadcast() {
    _controller = StreamController<T>.broadcast(onListen: _onFirstListen);
  }

  late final StreamController<T> _controller;
  final _pending = <T>[];
  bool _flushed = false;

  Stream<T> get stream => _controller.stream;
  bool get isClosed => _isClosed;
  bool _isClosed = false;

  void add(T event) {
    if (_isClosed) return;
    if (_flushed) {
      _controller.add(event);
    } else {
      _pending.add(event);
    }
  }

  void addError(Object error) {
    if (!_isClosed) _controller.addError(error);
  }

  void _onFirstListen() {
    if (_flushed) return;
    _flushed = true;
    // Deferred: adding events from inside onListen is not safe.
    scheduleMicrotask(() {
      for (final e in _pending) {
        if (!_isClosed) _controller.add(e);
      }
      _pending.clear();
    });
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _pending.clear();
    await _controller.close();
  }
}
