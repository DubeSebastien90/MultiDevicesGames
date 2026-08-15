/// Tunables for Echo.
class EchoConfig {
  const EchoConfig._();

  /// How long each seat stays lit during the reveal, at round one. Shrinks a
  /// little every level so the game gets harder to watch, not just harder to
  /// remember.
  static const double revealSecondsStart = 0.8;

  /// Never faster than this — below it a flash stops being watchable at all.
  static const double revealSecondsFloor = 0.3;

  /// How much a level shaves off the reveal, in seconds.
  static const double revealSecondsStep = 0.05;

  /// Dark gap between one seat lighting and the next during the reveal.
  static const double revealGapSeconds = 0.25;

  /// World units across. World units are centimetres, so this is a healthy
  /// fraction of a phone's width without spilling off the smallest one.
  static const double orbRadius = 1.4;

  /// Additive, for the round a phone made it to before a wrong tap put them
  /// out. Never deducted — a mistake ends your game, it does not cost you
  /// what you already earned.
  static const int pointsPerRoundSurvived = 2;

  /// On top of that, for whoever is still in when everybody else is out.
  static const int winnerBonus = 20;

  static const int colorIdle = 0xFF3A4A6B;
  static const int colorEliminated = 0xFF3A1414;

  /// One identity colour per seat, assigned in join order and kept for the
  /// whole game — cycled if there are more phones than colours.
  static const List<int> seatPalette = [
    0xFFE84855,
    0xFF3ABEFF,
    0xFFFFC93C,
    0xFF6BCB77,
    0xFFC65BCF,
    0xFFFF8C42,
    0xFF4D96FF,
    0xFFF7F1E5,
  ];
}
