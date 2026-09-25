import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/audio/game_audio.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/audio/sounds.dart';
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
    Widget? footer,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HoldToConfirm(
            confirmed: confirmed,
            onConfirmed: onConfirmed,
            content: const Text('the board'),
            footer: footer,
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

  testWidgets('a new round can be confirmed again', (tester) async {
    // Flutter reuses this State between rounds. "Ready" latched and never let
    // go, so the second round opened already claiming to be confirmed *and*
    // refusing to be held — the host waited for an answer the phone had no way
    // to give, and everyone sat on the placement screen.
    var calls = 0;
    await mount(tester, onConfirmed: () => calls++, confirmed: true);
    expect(find.text('Ready'), findsOne);

    // The host resets every confirmation when the next round is set up.
    await mount(tester, onConfirmed: () => calls++);
    expect(find.text('Hold to confirm position'), findsOne,
        reason: 'a fresh round is not already confirmed');
    expect(find.text('Ready'), findsNothing);

    // And the hold works again.
    final finger = await tester.startGesture(const Offset(200, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(calls, 1);
    expect(find.text('Ready'), findsOne);

    await finger.up();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the content is shown beside the ring', (tester) async {
    await mount(tester, onConfirmed: () {});
    expect(find.text('the board'), findsOne);
  });

  // The other half of the footer rule: everything that is *not* a button holds,
  // including the picture itself. Pressed by widget rather than by coordinate,
  // because the point is that the picture does not take the press.
  testWidgets('pressing the picture itself still holds', (tester) async {
    var calls = 0;
    await mount(
      tester,
      onConfirmed: () => calls++,
      footer: const Text('phone 2'),
    );

    final finger = await tester.startGesture(
      tester.getCenter(find.text('the board')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(calls, 1, reason: 'the board swallowed the press');
    await finger.up();
    await tester.pump(const Duration(seconds: 3));
  });

  // The footer holds buttons — the legend chips that make a neighbour's phone
  // speak — and the hold listens for a finger anywhere inside itself. If those
  // buttons were inside it, every tap would fill the ring a little, and enough
  // impatient taps would confirm a position nobody confirmed.
  testWidgets('tapping the footer never fills the ring', (tester) async {
    var calls = 0;
    var taps = 0;
    await mount(
      tester,
      onConfirmed: () => calls++,
      footer: Builder(
        builder: (context) => GestureDetector(
          onTap: () => taps++,
          child: const Text('phone 2'),
        ),
      ),
    );

    for (var i = 0; i < 12; i++) {
      await tester.tap(find.text('phone 2'));
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(taps, 12, reason: 'the chip itself must still be tappable');
    expect(calls, 0, reason: 'a dozen taps on a chip confirmed the placement');
    expect(find.text('Ready'), findsNothing);
  });

  group('the gauge sound', () {
    Future<_HeardAudio> mountHeard(WidgetTester tester) async {
      final audio = _HeardAudio();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HoldToConfirm(
            onConfirmed: () {},
            content: const Text('the board'),
            audio: audio,
          ),
        ),
      ));
      return audio;
    }

    // Frame by frame, as a phone would: one long pump is one animation tick,
    // and would sound one step instead of the climb.
    Future<void> frames(WidgetTester tester, Duration total) async {
      const frame = Duration(milliseconds: 16);
      for (var t = Duration.zero; t < total; t += frame) {
        await tester.pump(frame);
      }
    }

    testWidgets('a full hold climbs every step once, lowest first',
        (tester) async {
      final audio = await mountHeard(tester);

      final finger = await tester.startGesture(const Offset(200, 300));
      await tester.pump();
      await frames(tester, const Duration(milliseconds: 1100));
      await finger.up();
      await frames(tester, const Duration(seconds: 3));

      expect(audio.played, Sounds.holdSteps);
    });

    testWidgets('a slip picks the climb up where the ring is', (tester) async {
      final audio = await mountHeard(tester);

      final finger = await tester.startGesture(const Offset(200, 300));
      await tester.pump();
      await frames(tester, const Duration(milliseconds: 600));
      await finger.up();
      await tester.pump();
      await frames(tester, const Duration(milliseconds: 300));

      final beforeSlip = audio.played.length;
      expect(audio.played, Sounds.holdSteps.take(beforeSlip),
          reason: 'draining must be silent');

      final again = await tester.startGesture(const Offset(200, 300));
      await tester.pump();
      await frames(tester, const Duration(milliseconds: 1000));
      await again.up();

      final after = audio.played.skip(beforeSlip).toList();
      expect(after, isNotEmpty);
      expect(after.first, isNot(Sounds.holdSteps.first),
          reason: 'a resumed hold replayed the bottom of the gauge');
      expect(after.last, Sounds.holdSteps.last);
      final order = [for (final c in after) Sounds.holdSteps.indexOf(c)];
      expect(order, [...order]..sort(), reason: 'the climb went down');
    });
  });
}

class _HeardAudio implements LocalAudio {
  final played = <SoundCue>[];

  @override
  SoundHandle play(SoundCue cue, {bool loop = false, double volume = 1.0}) {
    played.add(cue);
    return SoundHandle.none;
  }

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) {}
}
