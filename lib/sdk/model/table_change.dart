/// The table changed shape mid-setup: somebody arrived, or somebody left.
///
/// Kept as two fields rather than one finished sentence because the two cases
/// end differently and the screen saying so needs to know which it is. A player
/// leaving might mean *the next game instead*, or it might mean *there is
/// nothing left this table can play* — same event, and the only two ways out of
/// it are opposites: carry on, or go back to the menu.
///
/// It is also the reason this is not folded into the host's `warning`. That one
/// carries developer diagnostics — a game naming phones that are not here, a
/// board that wants re-calibrating — and those belong in a banner somebody can
/// ignore. This one stops the table, because every phone on it is about to be
/// asked to move.
class TableChange {
  const TableChange({required this.who, this.nextGame});

  /// What happened, in the third person: `'AngryHippo left'`.
  ///
  /// Phrased by the host, which is the only side that knows the player's name —
  /// a joiner sees phone numbers.
  final String who;

  /// The game the table is heading into, or null when the playlist has run out
  /// of games this many phones can play.
  final String? nextGame;

  /// Whether there is anywhere to go but back.
  bool get carriesOn => nextGame != null;

  Map<String, Object?> toJson() => {
    'who': who,
    if (nextGame != null) 'nextGame': nextGame,
  };

  /// Null in, null out — the field is absent from the wire whenever nothing has
  /// happened, which is nearly always.
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
