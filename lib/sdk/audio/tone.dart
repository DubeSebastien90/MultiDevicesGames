/// A sound made rather than played: a pure tone whose pitch and volume glide.
///
/// Everything in `sounds.dart` is a recording, and a recording's pitch is
/// fixed — the one thing it cannot do is rise smoothly for as long as a game
/// likes. A tone is synthesised on the phone, so its frequency is just a
/// number, moved every frame. That is what a kettle climbing toward the bang
/// needs, and a stepped set of recordings only ever approximated.
///
/// **The glide is described, not driven.** The host says where the tone starts,
/// where it ends and how long it takes; each phone then moves it frame by frame
/// on its own clock. Nothing is sent per frame, so a glide is as smooth on a
/// phone with a bad connection as on the host.
library;

import 'dart:math' as math;

class Tone {
  const Tone({
    required this.fromHz,
    double? toHz,
    this.glide = Duration.zero,
    this.volume = 1.0,
    double? toVolume,
  }) : toHz = toHz ?? fromHz,
       toVolume = toVolume ?? volume;

  /// Pitch at the start and at the end of [glide], in Hz. Held at [toHz]
  /// afterwards, for as long as nobody stops it.
  final double fromHz;
  final double toHz;

  /// Zero for a steady tone.
  final Duration glide;

  /// Loudness at the start and the end, 0 to 1. A tone is a full-scale sine,
  /// so this is much lower than a recording's volume would be for the same
  /// perceived level — see the game's own config for the numbers it uses.
  final double volume;
  final double toVolume;

  /// How far through [glide] a tone is after [elapsedMs], 0 to 1.
  double _progress(double elapsedMs) {
    final total = glide.inMicroseconds / 1000;
    if (total <= 0) return 1;
    return (elapsedMs / total).clamp(0.0, 1.0);
  }

  /// Pitch after [elapsedMs]. Exponential, not linear: the ear hears equal
  /// *ratios* as equal steps, so a linear glide in Hz would seem to rush at the
  /// bottom and crawl at the top.
  double hzAt(double elapsedMs) =>
      fromHz * math.pow(toHz / fromHz, _progress(elapsedMs));

  double volumeAt(double elapsedMs) =>
      volume + (toVolume - volume) * _progress(elapsedMs);

  Map<String, dynamic> toJson() => {
    'hz': fromHz,
    if (toHz != fromHz) 'toHz': toHz,
    if (glide > Duration.zero) 'glideMs': glide.inMilliseconds,
    'vol': volume,
    if (toVolume != volume) 'toVol': toVolume,
  };

  static Tone fromJson(Map<String, dynamic> j) => Tone(
    fromHz: (j['hz'] as num).toDouble(),
    toHz: (j['toHz'] as num?)?.toDouble(),
    glide: Duration(milliseconds: (j['glideMs'] as num?)?.toInt() ?? 0),
    volume: (j['vol'] as num?)?.toDouble() ?? 1.0,
    toVolume: (j['toVol'] as num?)?.toDouble(),
  );

  @override
  String toString() =>
      'Tone(${fromHz.round()}→${toHz.round()}Hz over ${glide.inMilliseconds}ms)';
}
