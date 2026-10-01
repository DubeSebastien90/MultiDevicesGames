import 'dart:async';

import 'transport.dart';

class LoopbackPair {
  LoopbackPair() {
    transport = _LoopbackTransport(_toHost, _toClient);
    peer = _LoopbackPeerLink(_toClient, _toHost);
  }

  final _toHost = QueuedBroadcast<Map<String, dynamic>>();
  final _toClient = QueuedBroadcast<Map<String, dynamic>>();

  late final Transport transport;

  late final PeerLink peer;

  Future<void> dispose() async {
    if (!_toHost.isClosed) await _toHost.close();
    if (!_toClient.isClosed) await _toClient.close();
  }
}

class _LoopbackTransport implements Transport {
  _LoopbackTransport(this._out, this._in);

  final QueuedBroadcast<Map<String, dynamic>> _out;
  final QueuedBroadcast<Map<String, dynamic>> _in;

  @override
  Future<void> connect() async {}

  @override
  Stream<Map<String, dynamic>> get onMessage => _in.stream;

  @override
  void send(Map<String, dynamic> message) {
    if (!_out.isClosed) _out.add(message);
  }

  @override
  Future<void> dispose() async {}
}

class _LoopbackPeerLink implements PeerLink {
  _LoopbackPeerLink(this._out, this._in);

  final QueuedBroadcast<Map<String, dynamic>> _out;
  final QueuedBroadcast<Map<String, dynamic>> _in;

  @override
  String get debugName => 'this device';

  @override
  Stream<Map<String, dynamic>> get onMessage => _in.stream;

  @override
  void send(Map<String, dynamic> message) {
    if (!_out.isClosed) _out.add(message);
  }

  @override
  Future<void> close() async {}
}
