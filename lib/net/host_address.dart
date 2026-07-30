import 'websocket_transport.dart' show kDefaultPort;

/// Turns whatever the joiner gave us into a WebSocket URI.
///
/// Accepts the full QR payload (`ws://192.168.1.42:8080`), a typed `host:port`,
/// or a bare IP — typing an address by hand is the fallback when a camera is
/// unavailable or the QR will not focus, so it should be forgiving.
Uri? parseHostAddress(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;

  if (!text.contains('://')) text = 'ws://$text';

  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'ws' && uri.scheme != 'wss') return null;

  return uri.hasPort ? uri : uri.replace(port: kDefaultPort);
}
