import 'dart:math' as math;

import '../model/device_metrics.dart';

/// One connected phone, as a game needs to know it when deciding the layout.
///
/// Everything physical is in millimetres, because that is what a ruler and a
/// spec sheet give you, and because the whole point of the platform is that a
/// board is a real object on a real table.
class PhoneSpec {
  const PhoneSpec({
    required this.phoneId,
    required this.label,
    required this.widthMm,
    required this.heightMm,
    required this.bezelMm,
    required this.dpi,
    required this.devicePixelRatio,
    required this.activePxWidth,
    required this.activePxHeight,
  });

  /// Platform-assigned, stable for this connection: 'p1'.
  final String phoneId;

  /// Human name, for diagrams and standings: 'Pixel 7'.
  final String label;

  /// The lit area, landscape: width is the long edge.
  final double widthMm;
  final double heightMm;

  /// Casing edge to first lit pixel. Two phones pushed together leave
  /// `a.bezelMm + b.bezelMm` of dead space between their active areas.
  final double bezelMm;

  final double dpi;
  final double devicePixelRatio;
  final double activePxWidth;
  final double activePxHeight;

  double get areaMm2 => widthMm * heightMm;

  /// Handy for "biggest screen", which is usually what a game means by "best".
  double get diagonalMm =>
      math.sqrt(widthMm * widthMm + heightMm * heightMm);

  static PhoneSpec fromMetrics(
    String phoneId,
    DeviceMetrics metrics,
  ) => PhoneSpec(
    phoneId: phoneId,
    label: metrics.label,
    widthMm: metrics.widthMm,
    heightMm: metrics.heightMm,
    bezelMm: metrics.bezelMm,
    dpi: metrics.dpi,
    devicePixelRatio: metrics.devicePixelRatio,
    activePxWidth: metrics.activePxWidth,
    activePxHeight: metrics.activePxHeight,
  );
}

/// Everything a game is told about the table before it decides the layout.
class LobbyInfo {
  const LobbyInfo(this.phones);

  /// In join order. A game that cares about physical size should sort by it
  /// rather than trusting this order to mean anything.
  final List<PhoneSpec> phones;

  int get phoneCount => phones.length;

  PhoneSpec? byId(String phoneId) {
    for (final p in phones) {
      if (p.phoneId == phoneId) return p;
    }
    return null;
  }
}
