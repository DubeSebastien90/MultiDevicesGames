library;

import 'dart:async';

abstract class Transport {
  Future<void> connect();
  void send(Map<String, dynamic> message);
  Stream<Map<String, dynamic>> get onMessage;
  Future<void> dispose();
}

abstract class PeerLink {
  String get debugName;
  Stream<Map<String, dynamic>> get onMessage;
  void send(Map<String, dynamic> message);
  Future<void> close();
}

abstract class HostTransport {
  Future<Uri> start();
  Stream<PeerLink> get onPeer;
  Future<void> dispose();
}

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
