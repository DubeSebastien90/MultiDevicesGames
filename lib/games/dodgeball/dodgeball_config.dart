import '../../sdk/audio/sound_cue.dart';

/// Tunables for the Dodgeball game.
class DodgeballConfig {
  const DodgeballConfig._();

  // -- movement ---------------------------------------------------------------
  static const double moveSpeed = 8.0; // cm/s
  static const double characterRadius = 0.5; // cm

  // -- dash -------------------------------------------------------------------
  static const double dashSpeed = 28.0; // cm/s (burst speed)
  static const double dashDuration = 0.15; // seconds
  static const double dashCooldown = 2.5; // seconds
  static const double dashInvincibility = 0.2; // seconds (i-frames during dash)

  // -- balls ------------------------------------------------------------------
  static const double ballRadius = 0.3; // cm
  static const double ballBaseSpeed = 5.0; // cm/s
  static const double ballSpeedIncrement = 0.4; // cm/s added per spawn
  static const double ballMaxSpeed = 20.0; // cm/s
  static const double ballSpawnInterval = 3.0; // seconds between spawns
  static const double ballSpawnIntervalMin = 1.0; // minimum interval
  static const double ballSpawnIntervalDecay = 0.92; // multiplier each spawn
  static const int ballMaxCount = 20;

  // -- falling ----------------------------------------------------------------
  /// How long the round keeps running after the last player but one goes out.
  ///
  /// The round is decided the instant it happens; this is only the phase
  /// waiting, so the burst that says *how* it was decided plays to somebody —
  /// the same second Arena holds for.
  static const double deathShowSeconds = 1.0;

  /// The burst itself: a ring of round bits of the player's own colour, thrown
  /// outwards and slowing as they fade. Arena's numbers, so going out looks
  /// the same in both games.
  static const int deathParticles = 16;
  static const double deathBurstSeconds = 1.0;

  /// How fast the fastest bits leave, in world units per second.
  static const double deathBurstSpeed = 7.0;

  /// The size of a bit, as a fraction of the body it came out of.
  static const double deathParticleScale = 0.22;

  // -- sound ------------------------------------------------------------------
  //
  // Each plays on one phone only: the dash on the dasher's, the bounce on the
  // screen the ball bounced on — so a bounce is heard from where it happened.
  // Leveled copies of audio-src/originals/games/dodgeball/.

  static const woosh = SoundCue.asset('assets/games/dodgeball/woosh.wav');
  static const boing = SoundCue.asset('assets/games/dodgeball/boing.wav');

  /// Under the rest: with a table full of balls the bounces are constant, and
  /// at full level they bury the dash and the knock-outs.
  static const double boingVolume = 0.6;

  // -- getting started --------------------------------------------------------
  /// The three lines of the briefing, and how long each one holds the screen.
  ///
  /// The last one has nothing to demonstrate — it is the object of the game,
  /// not a control — so it plays over the player walking back from the dash
  /// the line before it. A line with a still screen under it reads as the
  /// game having stopped.
  static const List<String> briefingLines = [
    'Drag to move',
    'Tap to dash',
    'Do NOT get hit',
  ];

  static const double briefingStepSeconds = 2.2;
  static const double briefingSeconds = briefingStepSeconds * 3;

  /// When in a step the demonstration begins — the ball appears, and a moment
  /// later the player gets out of its way. Not at nought: the line wants
  /// reading before the thing it names happens.
  static const double briefingDemoAt = 0.5; // seconds into the step

  /// How long the demonstration ball takes to reach the player, and how long
  /// the player leaves it before dashing. The gap between them is the whole
  /// lesson: the dash comes *late*, when the ball is nearly there.
  static const double demoBallTravel = 1.0; // seconds
  static const double demoDashAt = 0.62; // seconds after the ball appears

  /// How far out the demonstration ball starts, as a multiple of the player's
  /// own radius. Far enough to be seen arriving, near enough to stay on one
  /// screen.
  static const double demoBallDistance = 9.0;

  /// The fades at either end of the demonstration ball's life.
  static const double demoFadeIn = 0.22; // seconds
  static const double demoFadeOut = 0.3; // seconds

  /// How fast a player turns back to the way they started, once they have
  /// walked home during the count.
  static const double homeTurnSpeed = 6.0; // rad/s

  /// The whole count: three digits of a second each, then GO.
  ///
  /// The round starts when GO *leaves*, which is what the extra [goSeconds] on
  /// the end buys. Counting straight to zero meant the last thing on screen
  /// was a nought — held for the handful of frames between the clock running
  /// out and the phase changing, which reads as a stutter rather than a start.
  static const double countdownSeconds = 3.6;

  /// How long GO holds the screen at the end of the count.
  static const double goSeconds = 0.6;

  // -- gesture thresholds -----------------------------------------------------
  static const double minMoveDistance = 0.8; // cm
  static const int tapMaxMs = 250;

  // -- joystick ---------------------------------------------------------------
  /// Full tilt: the distance from the anchor at which the player runs at
  /// [moveSpeed], and where the drawn knob stops following the finger. Pushing
  /// further still steers — it just cannot go faster or look more pushed.
  static const double joystickRadius = 1.65; // cm

  static const double joystickKnobRadius = 0.56; // cm

  /// Faint throughout: the stick sits under the finger, over a floor with
  /// balls crossing it, and it is feedback rather than furniture.
  static const int joystickWellAlpha = 24;
  static const int joystickRingAlpha = 70;
  static const int joystickDeadZoneAlpha = 45;
  static const int joystickKnobAlpha = 130;

  /// How hard the stick is pushed, from a finger [distance] out of the anchor:
  /// 0 inside the dead zone, 1 at [joystickRadius] and beyond.
  ///
  /// The ramp starts where the dead zone ends rather than at the anchor, so
  /// the first distance that moves a player at all moves them slowly. A jump
  /// straight to half speed the instant the dead zone is crossed is the thing
  /// that makes an analogue stick feel like a digital one.
  ///
  /// The dash ignores this: a dash is a fixed burst, and a nudged stick that
  /// dashed a short way would make the one escape in the game unreliable.
  static double moveScaleFor(double distance) {
    if (distance <= minMoveDistance) return 0;
    final span = joystickRadius - minMoveDistance;
    if (span <= 0) return 1;
    final t = (distance - minMoveDistance) / span;
    return t < 1 ? t : 1;
  }

  // -- player colours (ARGB ints) ---------------------------------------------
  static const List<int> playerColors = [
    0xFFE63946, // red
    0xFF457B9D, // blue
    0xFF2A9D8F, // teal
    0xFFE9C46A, // yellow
    0xFFF4A261, // orange
    0xFF6A0572, // purple
    0xFF1D3557, // navy
    0xFF8AC926, // lime
  ];
}
