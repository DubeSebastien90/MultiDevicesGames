/// The menus' own speaker: the sound a button makes under your finger.
///
/// Separate from the session's [AudioEngine] because the menus are not inside
/// a session — the home screen, Settings and the join list exist before any
/// table does, and outlive it. Same rule as [LocalAudio] otherwise: this
/// phone's glass, this phone's speaker, nothing on the wire.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'game_audio.dart';
import 'sounds.dart';

class UiAudio {
  const UiAudio._();

  /// Silent until `main.dart` hands it a real one, so a widget test that
  /// presses a button makes no noise and needs no audio device.
  static LocalAudio speaker = const SilentLocalAudio();

  static final _random = math.Random();

  /// The button press: one of [Sounds.buttonPress] at random, so a run of
  /// taps does not sound like one sample on repeat.
  static void buttonPress() {
    final cues = Sounds.buttonPress;
    speaker.play(cues[_random.nextInt(cues.length)]);
  }
}

/// [action], with the button sound in front of it — or null, so a disabled
/// button stays disabled and silent.
VoidCallback? withButtonSound(VoidCallback? action) {
  if (action == null) return null;
  return () {
    UiAudio.buttonPress();
    action();
  };
}
