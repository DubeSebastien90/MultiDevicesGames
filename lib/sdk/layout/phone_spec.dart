import 'dart:math' as math;

import '../model/device_metrics.dart';
import '../model/player_color.dart';

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
    this.color,
  });

  /// Platform-assigned, stable for this connection: 'p1'.
  final String phoneId;

  /// Human name, for diagrams and standings: 'Pixel 7'.
  final String label;

  /// Who is sitting here, as a colour. Null only in the moment between a phone
  /// connecting and the host seating it, and on a board built from bare metrics
  /// in a test.
  final PlayerColor? color;

  /// The lit area as the device itself is held: **portrait**, so width is the
  /// short edge and height is the long one.
  ///
  /// This is the panel, not the placement. How the phone lies on the table is
  /// the game's decision, expressed as `quarterTurns` on its placement — see
  /// [footprintWidthMm].
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

  /// How much board this screen covers once turned [quarterTurns] steps.
  /// An odd number of turns swaps the two.
  double footprintWidthMm(int quarterTurns) =>
      quarterTurns.isOdd ? heightMm : widthMm;

  double footprintHeightMm(int quarterTurns) =>
      quarterTurns.isOdd ? widthMm : heightMm;

  /// The same swap for pixels, which is what the rotated surface reports and
  /// therefore what the world transform has to be built from.
  double footprintPxWidth(int quarterTurns) =>
      quarterTurns.isOdd ? activePxHeight : activePxWidth;

  double footprintPxHeight(int quarterTurns) =>
      quarterTurns.isOdd ? activePxWidth : activePxHeight;

  /// Handy for "biggest screen", which is usually what a game means by "best".
  double get diagonalMm =>
      math.sqrt(widthMm * widthMm + heightMm * heightMm);

  static PhoneSpec fromMetrics(
    String phoneId,
    DeviceMetrics metrics, {
    PlayerColor? color,
  }) => PhoneSpec(
    phoneId: phoneId,
    label: metrics.label,
    color: color,
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

  /// Everyone who has a colour, in join order.
  ///
  /// The list a game builds its players from. Anyone unseated is left out
  /// rather than given a placeholder: a game that deals turns or spawns by
  /// colour needs every entry here to be a real, distinct player.
  List<PhoneSpec> get seated => [
    for (final p in phones)
      if (p.color != null) p,
  ];
}
