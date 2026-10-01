import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show TargetPlatform;

class DeviceMetrics {
  const DeviceMetrics({
    required this.activePxWidth,
    required this.activePxHeight,
    required this.widthMm,
    required this.heightMm,
    required this.bezelMm,
    required this.devicePixelRatio,
    this.label = 'phone',
  });

  final double activePxWidth;
  final double activePxHeight;

  final double widthMm;
  final double heightMm;

  final double bezelMm;

  final double devicePixelRatio;
  final String label;

  double get dpi => activePxWidth / (widthMm / 25.4);

  double get pxPerMm => activePxWidth / widthMm;

  DeviceMetrics copyWith({
    double? widthMm,
    double? heightMm,
    double? bezelMm,
    String? label,
  }) => DeviceMetrics(
    activePxWidth: activePxWidth,
    activePxHeight: activePxHeight,
    widthMm: widthMm ?? this.widthMm,
    heightMm: heightMm ?? this.heightMm,
    bezelMm: bezelMm ?? this.bezelMm,
    devicePixelRatio: devicePixelRatio,
    label: label ?? this.label,
  );

  factory DeviceMetrics.estimate({
    required Size physicalPx,
    required double devicePixelRatio,
    required TargetPlatform platform,
    String label = 'phone',
  }) {
    final estimatedDpi = _estimateDpi(devicePixelRatio, platform);
    return DeviceMetrics(
      activePxWidth: physicalPx.width,
      activePxHeight: physicalPx.height,
      widthMm: physicalPx.width / estimatedDpi * 25.4,
      heightMm: physicalPx.height / estimatedDpi * 25.4,
      bezelMm: defaultBezelMm(platform),
      devicePixelRatio: devicePixelRatio,
      label: label,
    );
  }

  static double _estimateDpi(double dpr, TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return dpr * 160;
      case TargetPlatform.iOS:
        if (dpr >= 3) return 458;
        if (dpr >= 2) return 326;
        return 163;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        return dpr * 96;
    }
  }

  static double defaultBezelMm(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 3.0;
      default:
        return 0.0;
    }
  }

  Map<String, dynamic> toJson() => {
    'activePx': {'w': activePxWidth, 'h': activePxHeight},
    'screenMm': {'w': widthMm, 'h': heightMm},
    'bezelMm': bezelMm,
    'dpi': dpi,
    'dpr': devicePixelRatio,
    'label': label,
  };

  static DeviceMetrics fromJson(Map<String, dynamic> j) {
    final px = j['activePx'] as Map<String, dynamic>;
    final mm = j['screenMm'] as Map<String, dynamic>;
    return DeviceMetrics(
      activePxWidth: (px['w'] as num).toDouble(),
      activePxHeight: (px['h'] as num).toDouble(),
      widthMm: (mm['w'] as num).toDouble(),
      heightMm: (mm['h'] as num).toDouble(),
      bezelMm: (j['bezelMm'] as num).toDouble(),
      devicePixelRatio: (j['dpr'] as num?)?.toDouble() ?? 1.0,
      label: (j['label'] as String?) ?? 'phone',
    );
  }
}
