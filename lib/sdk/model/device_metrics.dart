import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show TargetPlatform;

/// What one phone reports about its own screen during calibration.
///
/// The physical size is in **millimetres**, not pixels: the whole point is that
/// two phones with different resolutions and densities produce one world with a
/// single consistent physical scale.
///
/// [widthMm]/[heightMm] are the source of truth and are user-editable, because
/// Flutter only exposes a density *bucket*, not the panel's real DPI. A guess
/// that is 8% off puts the seam ~5mm out of alignment — clearly visible. Letting
/// the player type a ruler measurement is the honest v1 answer, and it is the
/// same "human as sensor" trade the placement Confirm step already makes.
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

  /// Active screen area in *physical* pixels, in the current (landscape)
  /// orientation.
  final double activePxWidth;
  final double activePxHeight;

  /// Active screen area in millimetres, matching the pixel orientation.
  final double widthMm;
  final double heightMm;

  /// Dead casing around the active area, per edge.
  final double bezelMm;

  final double devicePixelRatio;
  final String label;

  /// Physical pixels per inch, derived from the measured size.
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

  /// Best guess from what the platform tells us. Users can correct it.
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
      bezelMm: _defaultBezelMm(platform),
      devicePixelRatio: devicePixelRatio,
      label: label,
    );
  }

  static double _estimateDpi(double dpr, TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        // Android's devicePixelRatio is the density bucket: dpi ≈ dpr * 160.
        return dpr * 160;
      case TargetPlatform.iOS:
        // Retina classes; close enough to seed the field.
        if (dpr >= 3) return 458;
        if (dpr >= 2) return 326;
        return 163;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        // Desktop scale factor sits on top of a ~96dpi baseline.
        return dpr * 96;
    }
  }

  static double _defaultBezelMm(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 3.0;
      default:
        // Desktop "phones" are windows: treat them as gapless for testing.
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
