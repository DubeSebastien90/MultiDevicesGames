import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../model/device_metrics.dart';

class NativeDpiChannel {
  static const channelName = 'com.multidevicesgames/display_metrics';

  static const _channel = MethodChannel(channelName);

  static Future<DeviceMetrics> detect({
    required Size physicalPx,
    required double devicePixelRatio,
    required TargetPlatform platform,
  }) async {
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
    } catch (_) {}
    return DeviceMetrics.estimate(
      physicalPx: px,
      devicePixelRatio: devicePixelRatio,
      platform: platform,
    );
  }
}
