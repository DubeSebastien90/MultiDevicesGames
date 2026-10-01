class ScoreEntry {
  const ScoreEntry({
    required this.phoneId,
    required this.label,
    required this.total,
    required this.roundDelta,
  });

  final String phoneId;
  final String label;

  final int total;

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

  List<ScoreEntry> get ranked {
    final list = List.of(_entries)..sort((a, b) => b.total.compareTo(a.total));
    return List.unmodifiable(list);
  }

  ScoreEntry? get leader {
    final list = ranked;
    if (list.isEmpty) return null;
    if (list.length > 1 && list[0].total == list[1].total) return null;
    return list.first.total == 0 ? null : list.first;
  }

  bool get isUsed => _entries.any((e) => e.total != 0);

  List<Map<String, dynamic>> toJson() => [for (final e in _entries) e.toJson()];

  static ScoreView fromJson(List<dynamic> json) => ScoreView([
    for (final e in json) ScoreEntry.fromJson(e as Map<String, dynamic>),
  ]);

  static const empty = ScoreView([]);
}

class Scoreboard {
  final _totals = <String, int>{};
  final _labels = <String, String>{};
  final _roundStart = <String, int>{};

  void register(String phoneId, String label) {
    _totals.putIfAbsent(phoneId, () => 0);
    _roundStart.putIfAbsent(phoneId, () => 0);
    _labels[phoneId] = label;
  }

  int operator [](String phoneId) => _totals[phoneId] ?? 0;

  int roundDelta(String phoneId) =>
      (_totals[phoneId] ?? 0) - (_roundStart[phoneId] ?? 0);

  void award(String phoneId, int points) {
    if (points == 0) return;
    _totals[phoneId] = (_totals[phoneId] ?? 0) + points;
  }

  void setTo(String phoneId, int value) => _totals[phoneId] = value;

  static const int pointsPerGame = 100;

  static double ladder(int place, int count, {int max = pointsPerGame}) =>
      count < 2 ? 0 : max * (count - place) / (count - 1);

  static Map<String, int> placements(
    List<Set<String>> tiers, {
    int max = pointsPerGame,
  }) {
    final count = tiers.fold<int>(0, (n, t) => n + t.length);
    final paid = <String, int>{};
    var place = 1;
    for (final tier in tiers) {
      if (tier.isEmpty) continue;
      var sum = 0.0;
      for (var i = 0; i < tier.length; i++) {
        sum += ladder(place + i, count, max: max);
      }
      final points = (sum / tier.length).round();
      for (final id in tier) {
        paid[id] = points;
      }
      place += tier.length;
    }
    return paid;
  }

  Map<String, int> awardPlacements(
    List<Set<String>> tiers, {
    int max = pointsPerGame,
  }) {
    final paid = placements(tiers, max: max);
    paid.forEach(award);
    return paid;
  }

  static List<Set<String>> tiersBy(Map<String, num> values) {
    final byValue = <num, Set<String>>{};
    for (final e in values.entries) {
      byValue.putIfAbsent(e.value, () => {}).add(e.key);
    }
    final keys = byValue.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final k in keys) byValue[k]!];
  }

  void awardAll(int points) {
    if (points == 0) return;
    for (final id in _totals.keys) {
      _totals[id] = (_totals[id] ?? 0) + points;
    }
  }

  void beginRound() {
    _roundStart
      ..clear()
      ..addAll(_totals);
  }

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
