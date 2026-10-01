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

  final double fromHz;
  final double toHz;

  final Duration glide;

  final double volume;
  final double toVolume;

  double _progress(double elapsedMs) {
    final total = glide.inMicroseconds / 1000;
    if (total <= 0) return 1;
    return (elapsedMs / total).clamp(0.0, 1.0);
  }

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
