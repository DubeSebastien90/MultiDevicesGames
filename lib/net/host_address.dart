import 'discovery.dart' show isValidJoinCode;
import 'websocket_transport.dart' show kDefaultPort;

/// Where to connect, plus the code to get in once there.
class HostTarget {
  const HostTarget(this.uri, this.code);

  /// Always fragment-free — `WebSocket.connect` gets a bare `ws://host:port`.
  final Uri uri;

  /// The 5-digit code, when the source carried one (a QR does; a hand-typed
  /// address usually does not, and the joiner is asked for it separately).
  final String? code;
}

/// Turns whatever the joiner gave us into an address and, if present, a code.
///
/// Accepts the full QR payload (`ws://192.168.1.42:8080#48213`), the same
/// without a code, a typed `host:port`, or a bare IP — typing an address by
/// hand is the fallback when a camera is unavailable or the QR will not focus,
/// so it should be forgiving.
HostTarget? parseHostTarget(String input) {
  final uri = parseHostAddress(input);
  if (uri == null) return null;

  // The code rides in the fragment: scanning the host's QR means you were
  // physically in front of the screen, which is the same proof the code asks
  // for — so a scan should not then demand you type it.
  final fragment = uri.fragment;
  final code = isValidJoinCode(fragment) ? fragment : null;

  return HostTarget(uri.removeFragment(), code);
}

/// Parses the address half only. Kept separate because the QR payload and a
/// hand-typed address share this leniency but differ in what else they carry.
Uri? parseHostAddress(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;

  if (!text.contains('://')) text = 'ws://$text';

  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'ws' && uri.scheme != 'wss') return null;

  return uri.hasPort ? uri : uri.replace(port: kDefaultPort);
}
