/// How the phones are physically laid out on the table.
///
/// Each minigame declares the arrangement it is designed for, because the shape
/// of the board *is* the game: a slingshot needs a long horizontal runway, and
/// balls need somewhere to fall from. The transform maths does not care — a
/// phone's offset is already a full (x, y) — so adding an arrangement is a
/// matter of choosing which axis the phones accumulate along.
enum Arrangement {
  /// Left to right, top edges aligned. A wide, short board.
  strip,

  /// Top to bottom, left edges aligned. A narrow, tall board.
  stack,
}

extension ArrangementInfo on Arrangement {
  /// True when phones accumulate along x.
  bool get isHorizontal => this == Arrangement.strip;

  String get title => switch (this) {
    Arrangement.strip => 'Side by side',
    Arrangement.stack => 'Stacked',
  };

  /// The one-line instruction a human acts on.
  String get instruction => switch (this) {
    Arrangement.strip =>
      'Lay the phones side by side in a row, short edges touching, '
          'top edges flush.',
    Arrangement.stack =>
      'Stack the phones one above the other, long edges touching, '
          'left edges flush.',
  };

  /// What "push them together" means for this arrangement, shown while placing.
  String get alignmentHint => switch (this) {
    Arrangement.strip =>
      'Push the phones together until the casings touch, with the top edges '
          'flush. The guide lines should continue straight across the gap.',
    Arrangement.stack =>
      'Push the phones together until the casings touch, with the left edges '
          'flush. The guide lines should continue straight down across the gap.',
  };

  String get wireName => name;

  static Arrangement fromWire(String? name) => switch (name) {
    'stack' => Arrangement.stack,
    _ => Arrangement.strip,
  };
}
