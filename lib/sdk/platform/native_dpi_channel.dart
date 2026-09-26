import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../model/device_metrics.dart';

/// Reads physical panel DPI from native platform code and returns a
/// [DeviceMetrics]. Falls back to [DeviceMetrics.estimate] on any failure,
/// so callers are never exposed to a channel exception.
class NativeDpiChannel {
  /// Shared with [NameDropSupport], which asks the same native handler a
  /// different question. Named rather than repeated so the two cannot drift.
  static const channelName = 'com.multidevicesgames/display_metrics';

  static const _channel = MethodChannel(channelName);

  static Future<DeviceMetrics> detect({
    required Size physicalPx,
    required double devicePixelRatio,
    required TargetPlatform platform,
  }) async {
    // Normalise to portrait so the channel result and the estimate use the
    // same orientation convention.
    final px = Size(
      math.min(physicalPx.width, physicalPx.height),
      math.max(physicalPx.width, physicalPx.height),
    );
    try {
      final raw = await _channel.invokeMethod<Map>('getPhysicalScreenInfo');
      if (raw != null) {
        final info = Map<String, dynamic>.from(raw);
        if (info['trusted'] == true) {
          final xdpi = (info['xdpi'] as num).toDouble();
          final ydpi = (info['ydpi'] as num).toDouble();
          // Only the density comes from native. The pixel dimensions are the
          // surface Flutter actually draws on, never the panel's: every layout
          // is placed in these pixels, so the moment they disagree with the
          // canvas — a window kept off the notch, split screen, a system bar
          // that would not hide — anything at the far edge is drawn off the
          // glass. That was the bottom edge stripe vanishing on a Galaxy A20,
          // measuring 1560px tall and drawing in 1507.
          final wPx = px.width;
          final hPx = px.height;
          return DeviceMetrics(
            activePxWidth: wPx,
            activePxHeight: hPx,
            widthMm: wPx / xdpi * 25.4,
            heightMm: hPx / ydpi * 25.4,
            bezelMm: DeviceMetrics.defaultBezelMm(platform),
            devicePixelRatio: devicePixelRatio,
          );
        }
      }
    } catch (_) {
      // MissingPluginException, PlatformException, cast errors — all handled
      // by falling through to the Flutter density-bucket estimate below.
    }
    return DeviceMetrics.estimate(
      physicalPx: px,
      devicePixelRatio: devicePixelRatio,
      platform: platform,
    );
  }
}
