import 'package:flutter/foundation.dart';

/// The handful of numbers the platform itself owns.
///
/// Everything else that used to live beside these was a *game's* tuning — how
/// hard a bird flies, how fast balls fall — and now lives with its game. What is
/// left is the stuff a game cannot change without breaking the seam for
/// everyone else.
class PlatformConfig {
  const PlatformConfig._();

  /// Whether to show the developer chrome laid over a running game: the phone
  /// badge, restart, debug and leave.
  ///
  /// Off in a release build. Those controls are for whoever is working on the
  /// platform, and a table of people playing should see the game and nothing
  /// else — a stray tap on Leave mid-round is not a feature.
  static const bool showDevChrome = !kReleaseMode;

  /// World units per millimetre, shared by every phone and every game.
  ///
  /// 0.1 means **1 world unit = 1 cm**, which puts a two-phone board at roughly
  /// 32 x 7 units — comfortably inside the 0.1..10 range Box2D is tuned for.
  static const double mmToWorld = 0.1;

  /// Physics steps per second. Fixed, so a simulation is deterministic and
  /// snapshot timestamps land on exact multiples of the step — the client
  /// interpolator gets an evenly spaced timeline to walk along.
  static const int simHz = 60;

  /// Snapshots per second. Matching [simHz] keeps clients from ever having to
  /// extrapolate far, which matters most exactly at the seam.
  static const int broadcastHz = 60;

  /// How long a sound takes to go quiet when its round ends.
  ///
  /// Not zero: a round ending cuts every sound the round started, and a music
  /// bed stopping dead is heard as a fault. Short enough that the results
  /// screen is not waiting for it.
  static const Duration roundEndFade = Duration(milliseconds: 250);
}
