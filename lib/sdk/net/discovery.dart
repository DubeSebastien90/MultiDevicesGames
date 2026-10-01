library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

const String kBeaconMagic = 'mss1';

String generateJoinCode([Random? random]) {
  final r = random ?? Random.secure();
  return r.nextInt(100000).toString().padLeft(5, '0');
}

bool isValidJoinCode(String input) => RegExp(r'^\d{5}$').hasMatch(input);

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

  final String id;

  final String name;

  final Uri uri;

  final int players;

  final bool open;

  final List<String> rejoinable;

  final DateTime seenAt;

  Map<String, dynamic> toJson() => {
    'app': kBeaconMagic,
    'id': id,
    'name': name,
    'ws': uri.toString(),
    'players': players,
    'open': open,
    if (rejoinable.isNotEmpty) 'rejoin': rejoinable,
  };

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

  static GameBeacon? tryFromAttributes(
    Map<String, String> attributes, {
    DateTime? now,
  }) {
    try {
      final rejoin = attributes['rejoin'];
      return _fromMap({
        ...attributes,
        'players': int.tryParse(attributes['players'] ?? '') ?? 0,
        'open': attributes['open'] != '0',
        if (rejoin != null) 'rejoin': rejoin.split(','),
      }, now: now);
    } on Object {
      return null;
    }
  }

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

      name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
      if (name.isEmpty) name = 'Game';
      if (name.length > 40) name = name.substring(0, 40);

      return GameBeacon(
        id: id,
        name: name,
        uri: uri,
        players: ((decoded['players'] as num?)?.toInt() ?? 0).clamp(0, 99),
        open: decoded['open'] as bool? ?? true,
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

abstract class GameAdvertiser {
  Future<void> start();

  void update({int? players, bool? open, List<String>? rejoinable});

  String? get failure;

  void dispose();
}

abstract class GameFinder extends ChangeNotifier {
  Future<void> start();

  List<GameBeacon> get games;

  void refresh();

  String? get failure;
}
