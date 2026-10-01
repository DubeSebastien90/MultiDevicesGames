import 'dart:math' as math;

import '../model/device_metrics.dart';
import '../model/player_color.dart';

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
    this.color,
  });

  final String phoneId;

  final String label;

  final PlayerColor? color;

  final double widthMm;
  final double heightMm;

  final double bezelMm;

  final double dpi;
  final double devicePixelRatio;
  final double activePxWidth;
  final double activePxHeight;

  double get areaMm2 => widthMm * heightMm;

  double footprintWidthMm(int quarterTurns) =>
      quarterTurns.isOdd ? heightMm : widthMm;

  double footprintHeightMm(int quarterTurns) =>
      quarterTurns.isOdd ? widthMm : heightMm;

  double footprintPxWidth(int quarterTurns) =>
      quarterTurns.isOdd ? activePxHeight : activePxWidth;

  double footprintPxHeight(int quarterTurns) =>
      quarterTurns.isOdd ? activePxWidth : activePxHeight;

  double get diagonalMm => math.sqrt(widthMm * widthMm + heightMm * heightMm);

  static PhoneSpec fromMetrics(
    String phoneId,
    DeviceMetrics metrics, {
    PlayerColor? color,
  }) => PhoneSpec(
    phoneId: phoneId,
    label: metrics.label,
    color: color,
    widthMm: metrics.widthMm,
    heightMm: metrics.widthMm * metrics.activePxHeight / metrics.activePxWidth,
    bezelMm: metrics.bezelMm,
    dpi: metrics.dpi,
    devicePixelRatio: metrics.devicePixelRatio,
    activePxWidth: metrics.activePxWidth,
    activePxHeight: metrics.activePxHeight,
  );
}

class LobbyInfo {
  const LobbyInfo(this.phones);

  final List<PhoneSpec> phones;

  int get phoneCount => phones.length;

  PhoneSpec? byId(String phoneId) {
    for (final p in phones) {
      if (p.phoneId == phoneId) return p;
    }
    return null;
  }

  List<PhoneSpec> get seated => [
    for (final p in phones)
      if (p.color != null) p,
  ];
}
