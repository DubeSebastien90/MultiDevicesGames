import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/app_controller.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/ui/lobby_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The lobby is a screen that holds still: one column, no scrolling. So how it
/// lays out on a real phone's screen is worth pinning down, and the only way
/// to know is to host a table and draw it.
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

  /// Every character's disc, grouped into the rows the picker wrapped them in.
  (Rect, List<List<Rect>>) picker(WidgetTester tester) {
    final panel = find
        .ancestor(
          of: find.text('Select your character'),
          matching: find.byType(Container),
        )
        .first;
    final discs = find.descendant(
      of: panel,
      matching: find.byType(AnimatedContainer),
    );
    final rows = <double, List<Rect>>{};
    for (final e in discs.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      rows.putIfAbsent(r.top, () => []).add(r);
    }
    return (tester.getRect(panel), rows.values.toList());
  }

  for (final (w, h, name, fits) in [
    (320.0, 568.0, 'a first-generation iPhone SE', false),
    (360.0, 640.0, 'a small Android', false),
    (375.0, 667.0, 'an iPhone 8', true),
    (390.0, 844.0, 'an iPhone 14', true),
    (428.0, 926.0, 'an iPhone 14 Plus', true),
  ]) {
    testWidgets('on $name the characters sit centred in their panel', (
      tester,
    ) async {
      await hosting(tester, w, h);
      final (panel, rows) = picker(tester);
      expect(rows.expand((r) => r), hasLength(8));

      for (final row in rows) {
        final left = row.map((r) => r.left).reduce((a, b) => a < b ? a : b);
        final right = row.map((r) => r.right).reduce((a, b) => a > b ? a : b);
        expect(
          left - panel.left,
          closeTo(panel.right - right, 1),
          reason: 'a row of ${row.length} is off to one side',
        );
        for (final disc in row) {
          expect(disc.size, const Size(48, 48));
        }
      }

      // Whether the whole lobby fits without scrolling. It does not on the
      // two smallest screens, where the characters wrap to three rows — a
      // known limit, written down here so it is changed on purpose.
      final overflow = tester.takeException();
      if (fits) {
        expect(overflow, isNull, reason: 'the lobby no longer fits on $name');
      } else {
        expect(overflow, isNotNull);
      }
    });
  }
}
