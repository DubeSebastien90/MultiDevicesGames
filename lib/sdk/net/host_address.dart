import 'discovery.dart' show isValidJoinCode;
import 'websocket_transport.dart' show kDefaultPort;

class HostTarget {
  const HostTarget(this.uri, this.code);

  final Uri uri;

  final String? code;
}

HostTarget? parseHostTarget(String input) {
  final uri = parseHostAddress(input);
  if (uri == null) return null;

  final fragment = uri.fragment;
  final code = isValidJoinCode(fragment) ? fragment : null;

  return HostTarget(uri.removeFragment(), code);
}

Uri? parseHostAddress(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;

  if (!text.contains('://')) text = 'ws://$text';

  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'ws' && uri.scheme != 'wss') return null;

  return uri.hasPort ? uri : uri.replace(port: kDefaultPort);
}
