/// One phone's standing.
class ScoreEntry {
  const ScoreEntry({
    required this.phoneId,
    required this.label,
    required this.total,
    required this.roundDelta,
  });

  final String phoneId;
  final String label;

  /// Running total for the whole session.
  final int total;

  /// How much that total has moved since the current round began.
  final int roundDelta;

  Map<String, dynamic> toJson() => {
    'phoneId': phoneId,
    'label': label,
    'total': total,
    'delta': roundDelta,
  };

  static ScoreEntry fromJson(Map<String, dynamic> j) => ScoreEntry(
    phoneId: j['phoneId'] as String,
    label: (j['label'] as String?) ?? j['phoneId'] as String,
    total: (j['total'] as num).toInt(),
    roundDelta: (j['delta'] as num?)?.toInt() ?? 0,
  );
}

/// Read-only standings, as a [GameView] and the platform screens see them.
class ScoreView {
  const ScoreView(this._entries);

  final List<ScoreEntry> _entries;

  int operator [](String phoneId) => entryFor(phoneId)?.total ?? 0;

  int roundDelta(String phoneId) => entryFor(phoneId)?.roundDelta ?? 0;

  ScoreEntry? entryFor(String phoneId) {
    for (final e in _entries) {
      if (e.phoneId == phoneId) return e;
    }
    return null;
  }

  /// Highest first. Ties keep their relative order, so the list does not
  /// reshuffle itself while nobody is scoring.
  List<ScoreEntry> get ranked {
    final list = List.of(_entries)
      ..sort((a, b) => b.total.compareTo(a.total));
    return List.unmodifiable(list);
  }

  /// The single phone in front, or null when nobody is clearly ahead.
  ScoreEntry? get leader {
    final list = ranked;
    if (list.isEmpty) return null;
    if (list.length > 1 && list[0].total == list[1].total) return null;
    return list.first.total == 0 ? null : list.first;
  }

  /// False while every score is still zero, which is how the platform knows to
  /// hide standings entirely for a co-operative game.
  bool get isUsed => _entries.any((e) => e.total != 0);

  List<Map<String, dynamic>> toJson() => [
    for (final e in _entries) e.toJson(),
  ];

  static ScoreView fromJson(List<dynamic> json) => ScoreView([
    for (final e in json) ScoreEntry.fromJson(e as Map<String, dynamic>),
  ]);

  static const empty = ScoreView([]);
}

/// The session scoreboard. Lives on the host, survives every round.
///
/// Score belongs to the lobby, not to a game: a table can play five minigames
/// and still know who is winning. A game reads it and adds to it; the platform
/// owns everything else — showing it, resetting it, and snapshotting totals at
/// the start of each round so [ScoreView.roundDelta] is free.
///
/// Only the host writes, and only from inside `step` or `onTouch`, for exactly
/// the same reason nothing else in the world has two writers.
class Scoreboard {
  final _totals = <String, int>{};
  final _labels = <String, String>{};
  final _roundStart = <String, int>{};

  /// Called by the platform when a phone joins, so it appears at zero rather
  /// than materialising the first time it scores.
  void register(String phoneId, String label) {
    _totals.putIfAbsent(phoneId, () => 0);
    _roundStart.putIfAbsent(phoneId, () => 0);
    _labels[phoneId] = label;
  }

  int operator [](String phoneId) => _totals[phoneId] ?? 0;

  int roundDelta(String phoneId) =>
      (_totals[phoneId] ?? 0) - (_roundStart[phoneId] ?? 0);

  /// The usual way to score. [points] may be negative.
  void award(String phoneId, int points) {
    if (points == 0) return;
    _totals[phoneId] = (_totals[phoneId] ?? 0) + points;
  }

  void setTo(String phoneId, int value) => _totals[phoneId] = value;

  /// Co-operative scoring: the table did a thing, everyone gets the points.
  void awardAll(int points) {
    if (points == 0) return;
    for (final id in _totals.keys) {
      _totals[id] = (_totals[id] ?? 0) + points;
    }
  }

  /// Platform-called at the start of a round; nothing else should touch it.
  void beginRound() {
    _roundStart
      ..clear()
      ..addAll(_totals);
  }

  /// The host's "clear the board" action.
  void resetAll() {
    for (final id in _totals.keys.toList()) {
      _totals[id] = 0;
    }
    beginRound();
  }

  ScoreView get view => ScoreView([
    for (final id in _totals.keys)
      ScoreEntry(
        phoneId: id,
        label: _labels[id] ?? id,
        total: _totals[id] ?? 0,
        roundDelta: roundDelta(id),
      ),
  ]);

  bool get isUsed => _totals.values.any((v) => v != 0);
}
