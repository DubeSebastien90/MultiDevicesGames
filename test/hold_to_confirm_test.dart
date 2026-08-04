import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/ui/hold_to_confirm.dart';

/// The placement screen's only control. A hold rather than a button because both
/// hands are busy holding phones together, and a stray tap must not claim "I am
/// ready" — so the timing *is* the feature and is worth pinning down.
///
/// Note the bare `pump()` after every press and release: a controller's first
/// tick only sets its baseline, so without it the elapsed time is a frame short
/// and nothing ever finishes.
void main() {
  Future<void> mount(
    WidgetTester tester, {
    required VoidCallback onConfirmed,
    bool confirmed = false,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HoldToConfirm(
            confirmed: confirmed,
            onConfirmed: onConfirmed,
            content: const Text('the board'),
          ),
        ),
      ));

  testWidgets('a full second of holding confirms, once', (tester) async {
    var calls = 0;
    await mount(tester, onConfirmed: () => calls++);

    expect(find.text('Hold to confirm position'), findsOne);

    final finger = await tester.startGesture(const Offset(200, 300));
    await tester.pump();

    // Most of the way there is still not there.
    await tester.pump(const Duration(milliseconds: 850));
    expect(calls, 0, reason: 'not yet — the hold is not served');
    expect(find.text('Ready'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    expect(find.text('Ready'), findsOne);
    expect(find.text('Hold to confirm position'), findsNothing);

    // Keeping the finger down, or lifting it, cannot fire it a second time.
    await tester.pump(const Duration(seconds: 2));
    await finger.up();
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 1);
  });

  testWidgets('letting go early confirms nothing', (tester) async {
    var calls = 0;
    await mount(tester, onConfirmed: () => calls++);

    final finger = await tester.startGesture(const Offset(200, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await finger.up();

    // Well past the point where it would have completed had the lift not
    // counted.
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(calls, 0);
    expect(find.text('Hold to confirm position'), findsOne);
  });

  testWidgets('the drain is slower than the fill, so a slip is not a restart',
      (tester) async {
    var calls = 0;
    await mount(tester, onConfirmed: () => calls++);

    // Hold 700ms, slip for 300ms, then hold again for 600ms. A fresh 600ms hold
    // confirms nothing — the test above proves even 850ms does not — so if this
    // one lands, what survived the slip is what finished it.
    final first = await tester.startGesture(const Offset(200, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await first.up();

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 0);

    final second = await tester.startGesture(const Offset(200, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, 1,
        reason: 'the drained progress was still mostly there to build on');

    await second.up();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('anywhere on the screen is the target', (tester) async {
    var calls = 0;
    await mount(tester, onConfirmed: () => calls++);

    // Not on the ring, not on the diagram — the corner.
    final finger = await tester.startGesture(const Offset(12, 14));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(calls, 1);

    await finger.up();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('already confirmed elsewhere shows Ready without a hold',
      (tester) async {
    var calls = 0;
    await mount(tester, onConfirmed: () => calls++, confirmed: true);

    expect(find.text('Ready'), findsOne);
    expect(calls, 0, reason: 'it was already true; nothing new to report');

    // And holding it again does not re-report.
    final finger = await tester.startGesture(const Offset(200, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await finger.up();
    expect(calls, 0);
  });

  testWidgets('the content is shown beside the ring', (tester) async {
    await mount(tester, onConfirmed: () {});
    expect(find.text('the board'), findsOne);
  });
}
