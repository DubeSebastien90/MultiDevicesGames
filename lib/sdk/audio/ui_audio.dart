library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'game_audio.dart';
import 'sounds.dart';

class UiAudio {
  const UiAudio._();

  static LocalAudio speaker = const SilentLocalAudio();

  static final _random = math.Random();

  static void buttonPress() {
    final cues = Sounds.buttonPress;
    speaker.play(cues[_random.nextInt(cues.length)]);
  }
}

VoidCallback? withButtonSound(VoidCallback? action) {
  if (action == null) return null;
  return () {
    UiAudio.buttonPress();
    action();
  };
}
