import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/app_controller.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/ui/lobby_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The lobby is a screen that holds still on any phone with the room, and
/// scrolls as a whole on one without. How it lays out on real screens is worth
/// pinning down, and the only way to know is to host a table and draw it.
void main() {
  Future<AppController> hosting(WidgetTester tester, double w, double h) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final controller = AppController();
    await tester.runAsync(() async {
      await controller.startHost(
        const DeviceMetrics(
          activePxWidth: 1080,
          activePxHeight: 2400,
          widthMm: 68.58,
          heightMm: 152.4,
          bezelMm: 3,
          devicePixelRatio: 3,
          label: 'test',
        ),
        name: 'table',
      );
      for (var i = 0; i < 50 && controller.client?.myColor == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    addTearDown(() => tester.runAsync(() async => controller.leave()));
    await tester.pumpWidget(
      MaterialApp(home: LobbyView(controller: controller)),
    );
    await tester.pump();
    return controller;
  }

  /// Every character's tile, grouped into the rows the picker laid them in.
  (Rect, List<List<Rect>>) picker(WidgetTester tester) {
    final card = find
        .ancestor(
          of: find.text('Pick your bubble'),
          matching: find.byType(DecoratedBox),
        )
        .last;
    final rows = <double, List<Rect>>{};
    for (final c in PlayerPalette.all) {
      // The tile's slot, outside its tilt: mine is turned and scaled a little,
      // which is decoration rather than layout.
      final r = tester.getRect(find.byKey(ValueKey('character-${c.id}')));
      rows.putIfAbsent(r.center.dy.roundToDouble(), () => []).add(r);
    }
    return (tester.getRect(card), rows.values.toList());
  }

  for (final (w, h, name) in [
    (320.0, 568.0, 'a first-generation iPhone SE'),
    (360.0, 640.0, 'a small Android'),
    (375.0, 667.0, 'an iPhone 8'),
    (390.0, 844.0, 'an iPhone 14'),
    (428.0, 926.0, 'an iPhone 14 Plus'),
  ]) {
    testWidgets('on $name the characters are two rows of four, centred', (
      tester,
    ) async {
      await hosting(tester, w, h);
      final (card, rows) = picker(tester);

      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row, hasLength(4));
        final left = row.map((r) => r.left).reduce((a, b) => a < b ? a : b);
        final right = row.map((r) => r.right).reduce((a, b) => a > b ? a : b);
        expect(
          left - card.left,
          closeTo(card.right - right, 2),
          reason: 'a row is off to one side',
        );
      }
      // Square, and big enough to be somebody — even on the narrowest phone.
      for (final tile in rows.expand((r) => r)) {
        expect(tile.width, closeTo(tile.height, 0.5));
        expect(tile.width, greaterThanOrEqualTo(44));
      }

      // Nothing overflows on any of them: the short ones scroll instead.
      expect(tester.takeException(), isNull, reason: 'overflowed on $name');
    });
  }
}
