import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'transport.dart';

const int kDefaultPort = 8080;

class WebSocketHostTransport implements HostTransport {
  WebSocketHostTransport({this.port = kDefaultPort});

  final int port;

  HttpServer? _server;
  final _peers = StreamController<PeerLink>.broadcast();
  final _links = <_WebSocketPeerLink>[];

  Uri? get address => _address;
  Uri? _address;

  @override
  Stream<PeerLink> get onPeer => _peers.stream;

  @override
  Future<Uri> start() async {
    HttpServer? bound;
    var lastError = Object();

    for (var p = port; p < port + 10; p++) {
      try {
        bound = await HttpServer.bind(
          InternetAddress.anyIPv4,
          p,
          shared: false,
        );
        break;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    if (bound == null) {
      throw StateError(
        'Could not bind a port in $port..${port + 9}: $lastError',
      );
    }
    _server = bound;

    final ips = await localIPv4Addresses();
    _address = Uri.parse(
      'ws://${ips.isEmpty ? '127.0.0.1' : ips.first}:${bound.port}',
    );

    bound.listen((HttpRequest req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.text
          ..write('MultiDevicesGame host — connect a WebSocket here');
        await req.response.close();
        return;
      }
      try {
        final socket = await WebSocketTransformer.upgrade(req);
        final link = _WebSocketPeerLink(
          socket,
          req.connectionInfo?.remoteAddress.address ?? 'unknown',
        );
        _links.add(link);
        link.onClosed.then((_) => _links.remove(link));
        _peers.add(link);
      } catch (_) {}
    }, onError: (Object _) {});

    return _address!;
  }

  @override
  Future<void> dispose() async {
    for (final l in List.of(_links)) {
      await l.close();
    }
    _links.clear();
    await _server?.close(force: true);
    _server = null;
    await _peers.close();
  }
}

class _WebSocketPeerLink implements PeerLink {
  _WebSocketPeerLink(this._socket, this._remote) {
    _socket.listen(
      (dynamic raw) {
        if (raw is! String) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) _messages.add(decoded);
        } catch (_) {}
      },
      onDone: _handleClosed,
      onError: (Object _) => _handleClosed(),
      cancelOnError: true,
    );
  }

  final WebSocket _socket;
  final String _remote;
  final _messages = QueuedBroadcast<Map<String, dynamic>>();
  final _closed = Completer<void>();

  Future<void> get onClosed => _closed.future;

  void _handleClosed() {
    if (!_closed.isCompleted) _closed.complete();
    if (!_messages.isClosed) _messages.close();
  }

  @override
  String get debugName => _remote;

  @override
  Stream<Map<String, dynamic>> get onMessage => _messages.stream;

  @override
  void send(Map<String, dynamic> message) {
    if (_socket.readyState != WebSocket.open) return;
    _socket.add(jsonEncode(message));
  }

  @override
  Future<void> close() async {
    _handleClosed();
    await _socket.close();
  }
}

class WebSocketTransport implements Transport {
  WebSocketTransport(this.uri);

  final Uri uri;

  WebSocket? _socket;
  final _messages = QueuedBroadcast<Map<String, dynamic>>();

  @override
  Stream<Map<String, dynamic>> get onMessage => _messages.stream;

  @override
  Future<void> connect() async {
    final socket = await WebSocket.connect(
      uri.toString(),
    ).timeout(const Duration(seconds: 6));
    _socket = socket;
    socket.listen(
      (dynamic raw) {
        if (raw is! String) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) _messages.add(decoded);
        } catch (_) {}
      },
      onDone: () {
        if (!_messages.isClosed) _messages.close();
      },
      onError: (Object e) {
        if (!_messages.isClosed) _messages.addError(e);
      },
    );
  }

  @override
  void send(Map<String, dynamic> message) {
    final s = _socket;
    if (s == null || s.readyState != WebSocket.open) return;
    s.add(jsonEncode(message));
  }

  @override
  Future<void> dispose() async {
    await _socket?.close();
    _socket = null;
    if (!_messages.isClosed) await _messages.close();
  }
}

Future<List<String>> localIPv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    final addresses = <String>[
      for (final i in interfaces)
        for (final a in i.addresses) a.address,
    ];
    addresses.sort((a, b) {
      final rank = _privateRank(b).compareTo(_privateRank(a));
      return rank != 0 ? rank : a.compareTo(b);
    });
    return addresses;
  } on Object {
    return const [];
  }
}

int _privateRank(String ip) {
  if (ip.startsWith('192.168.')) return 3;
  if (ip.startsWith('10.')) return 2;
  final m = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
  if (m != null) {
    final second = int.tryParse(m.group(1)!) ?? 0;
    if (second >= 16 && second <= 31) return 2;
  }
  if (ip.startsWith('169.254.')) return -1;
  return 0;
}
