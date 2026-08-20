/// What a game looks like from across the room, and the two jobs discovery has.
///
/// A host announces that it is hosting; phones on the "join" screen build a
/// live list of what they can hear. Nothing connects while looking — you can
/// see who is hosting before committing to anything.
///
/// This file is deliberately transport-free. It holds the vocabulary both sides
/// agree on ([GameBeacon]) and the two contracts ([GameAdvertiser],
/// [GameFinder]), and says nothing about how a beacon actually crosses the
/// room. The UDP broadcast implementation lives in `udp_discovery.dart`;
/// splitting them is what lets a second implementation — Bonjour/mDNS, which
/// iOS allows without the multicast entitlement that broadcast requires — sit
/// beside it rather than replace it.
///
/// The beacon carries the game *name* and address, never the join code. The
/// name is how a human recognises the right game; the code is the secret that
/// proves they were invited, and it is checked by the host on the WebSocket
/// (see `HostSession`), not out here where anyone with a packet sniffer sits.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Marks our datagrams so we ignore whatever else is broadcasting on this port.
///
/// Public rather than private only because [GameBeacon]'s codec and the UDP
/// transport that carries it now live in different files and must agree on it.
const String kBeaconMagic = 'mss1';

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
    this.rejoinable = const [],
  });

  /// Stable per-host-session id. Keyed on this rather than the address so a
  /// host that changes IP mid-lobby does not appear twice.
  ///
  /// This is also what lets two transports run at once without showing the
  /// same table twice: a game heard over both UDP and mDNS arrives under one
  /// id, and the second sighting simply refreshes the first.
  final String id;

  /// What the host called the game. Display only, and untrusted — see [name]'s
  /// sanitising in [tryParse].
  final String name;

  /// Where to connect once the joiner has the code.
  final Uri uri;

  final int players;

  /// False once the game has left the lobby; still listed, but not joinable.
  final bool open;

  /// Fingerprints of the seats sitting empty in this game.
  ///
  /// A phone finds its own here — see [DeviceIdentity.fingerprint] — and knows
  /// it can walk back into a round already under way. Everyone else reads a
  /// list of numbers that means nothing to them.
  final List<String> rejoinable;

  final DateTime seenAt;

  /// The UDP wire format: one JSON object per datagram.
  ///
  /// A Bonjour transport would not send this as bytes — the same keys become
  /// TXT record attributes on the advertised service — but keeping one set of
  /// key names means a beacon means the same thing whichever way it arrived.
  Map<String, dynamic> toJson() => {
    'app': kBeaconMagic,
    'id': id,
    'name': name,
    'ws': uri.toString(),
    'players': players,
    'open': open,
    if (rejoinable.isNotEmpty) 'rejoin': rejoinable,
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
      return _fromMap(decoded, now: now);
    } on Object {
      return null;
    }
  }

  /// The same beacon, arriving as a Bonjour TXT record instead of a datagram.
  ///
  /// TXT values are strings and only strings, so the three fields that are not
  /// strings are widened here and everything else falls through to exactly the
  /// checks [tryParse] applies. That reuse is the point: this input is every bit
  /// as hostile as a datagram — anyone on the network can advertise a service —
  /// and it would be a poor trade to gain a transport and lose the sanitising.
  static GameBeacon? tryFromAttributes(
    Map<String, String> attributes, {
    DateTime? now,
  }) {
    try {
      final rejoin = attributes['rejoin'];
      return _fromMap({
        ...attributes,
        'players': int.tryParse(attributes['players'] ?? '') ?? 0,
        // Absent reads as open, matching the datagram default. Only an explicit
        // '0' closes a game.
        'open': attributes['open'] != '0',
        if (rejoin != null) 'rejoin': rejoin.split(','),
      }, now: now);
    } on Object {
      return null;
    }
  }

  /// The one set of guards, whichever way the beacon arrived.
  static GameBeacon? _fromMap(Map<String, dynamic> decoded, {DateTime? now}) {
    try {
      if (decoded['app'] != kBeaconMagic) return null;
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
        // Hostile like everything else here: a stranger's datagram, capped and
        // filtered to plain hex so nothing odd reaches a comparison.
        rejoinable: [
          for (final f in (decoded['rejoin'] as List?) ?? const [])
            if (f is String && RegExp(r'^[0-9a-f]{1,32}$').hasMatch(f)) f,
        ].take(16).toList(),
        seenAt: now ?? DateTime.now(),
      );
    } on Object {
      return null;
    }
  }
}

/// Host side: tells the network this game exists, until disposed.
///
/// **Failure is never fatal, and implementations must guarantee that.** A phone
/// can be on a network that drops broadcasts, or on an iOS build without the
/// multicast entitlement, and hosting has to work anyway — the QR code and the
/// typed address are the way in when this is silent. So [start] does not throw
/// on a network it cannot announce onto; it records why in [failure] and the
/// lobby says so out loud.
abstract class GameAdvertiser {
  /// Begins announcing. Completes even when announcing turns out to be
  /// impossible — check [failure] rather than catching.
  Future<void> start();

  /// Keeps the advertised details current. Called when something a joiner can
  /// see actually changes, not on a timer, so an implementation that has to pay
  /// to publish a change is not paying every second.
  void update({int? players, bool? open, List<String>? rejoinable});

  /// Non-null when the game could not be announced. Hosting is unaffected.
  String? get failure;

  void dispose();
}

/// Joiner side: a live list of the games within earshot.
///
/// Purely passive from the user's point of view — appearing on this list costs
/// a host nothing and tells it nothing about who is looking.
///
/// A [ChangeNotifier] because the join sheet rebuilds off it directly, and
/// because implementations differ in *when* they learn things: a UDP listener
/// hears a datagram on a timer, an mDNS browser is pushed an event. Both just
/// notify.
abstract class GameFinder extends ChangeNotifier {
  /// Begins looking. Like [GameAdvertiser.start], completes rather than throws
  /// when the network will not allow it, and reports through [failure].
  Future<void> start();

  /// Games heard recently, joinable ones first, then alphabetical so the list
  /// does not reshuffle itself under the user's thumb every second.
  List<GameBeacon> get games;

  /// For a pull-to-refresh or a "not seeing it?" tap. Implementations that are
  /// pushed their updates may reasonably do very little here.
  void refresh();

  /// Non-null when we could not look at all — the UI should then point at the
  /// QR and typed-address fallbacks rather than spinning forever.
  String? get failure;
}
