class TableChange {
  const TableChange({required this.who, this.nextGame});

  final String who;

  final String? nextGame;

  bool get carriesOn => nextGame != null;

  Map<String, Object?> toJson() => {
    'who': who,
    if (nextGame != null) 'nextGame': nextGame,
  };

  static TableChange? fromJson(Object? json) {
    if (json is! Map) return null;
    final who = json['who'];
    if (who is! String) return null;
    return TableChange(who: who, nextGame: json['nextGame'] as String?);
  }

  @override
  String toString() =>
      'TableChange($who${nextGame == null ? '' : ' → $nextGame'})';
}
