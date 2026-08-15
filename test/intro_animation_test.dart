import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/model/coverage_map.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/model/phone_layout.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/model/world_rect.dart';
import 'package:multiscreen_slingshot/sdk/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/sdk/net/protocol.dart';
import 'package:multiscreen_slingshot/sdk/ui/intro_animation.dart';

/// The curtain between the lobby and the first board of a run.
///
/// Two things are worth pinning. It falls **once per run** — a run that plays
/// four games plays one intro, not four. And it **never strands a phone**: the
/// Rive runtime is not available in a test (there is no native library behind
/// it), which is exactly the condition a phone with a broken install would be
/// in, and the table still has to get to the placement screen.
void main() {
  late LoopbackPair pair;
  late ClientSession client;

  setUp(() async {
    pair = LoopbackPair();
    client = ClientSession(
      transport: pair.transport,
      metrics: DeviceMetrics(
        activePxWidth: 1080,
        activePxHeight: 2400,
        widthMm: 68.58,
        heightMm: 152.4,
        bezelMm: 3,
        devicePixelRatio: 3,
        label: 'test phone',
      ),
    );
    await client.connect();
  });

  tearDown(() async {
    client.dispose();
    await pair.dispose();
  });

  /// A layout, the way the host sends one. [intro] is what the Play button adds
  /// to the first board of a run and to no other.
  void sendLayout({required bool intro}) {
    const board = WorldRect(0, 0, 30, 10);
    pair.peer.send({
      'type': HostMsg.layout,
      ...const PhoneLayout(
        phoneId: 'p1',
        index: 0,
        total: 1,
        worldCenterX: 5,
        worldCenterY: 5,
        mmToWorld: 0.1,
        dpi: 400,
        devicePixelRatio: 3,
        activePxWidth: 1080,
        activePxHeight: 2400,
        board: board,
        placement: '',
      ).toJson(),
      'coverage': const CoverageMap(screens: [], board: board).toJson(),
      'slices': [
        PhoneSlice(
          'p1',
          const ScreenRect(
            centerX: 5,
            centerY: 5,
            width: 6,
            height: 13,
            turnRadians: 0,
          ),
          label: 'test phone',
          color: PlayerPalette.green,
        ).toJson(),
      ],
      if (intro) 'intro': true,
    });
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('the first board of a run carries the curtain', () async {
    sendLayout(intro: true);
    await settle();

    expect(client.phase, ClientPhase.placing);
    expect(client.showIntro, isTrue);
  });

  test('the next game in the same run does not', () async {
    sendLayout(intro: true);
    await settle();
    client.introFinished();

    // Game two. The table has already seen it; playing it again between every
    // round would turn a flourish into a wait.
    sendLayout(intro: false);
    await settle();
    expect(client.showIntro, isFalse);
  });

  test('lifting the curtain is local and idempotent', () async {
    sendLayout(intro: true);
    await settle();

    var notifications = 0;
    client.addListener(() => notifications++);

    client.introFinished();
    expect(client.showIntro, isFalse);
    expect(notifications, 1);

    // A second call — a stray timer, a rebuild — must not announce a change
    // that did not happen.
    client.introFinished();
    expect(notifications, 1);
  });

  testWidgets('with no Rive runtime the curtain lifts itself', (tester) async {
    // There is no native Rive library in a test, so `available` is false —
    // the same state a phone whose install is broken would be in. The point is
    // that such a phone reaches the board rather than sitting on black while
    // everyone else plays.
    expect(IntroAnimation.available, isFalse);

    var done = false;
    await tester.pumpWidget(
      MaterialApp(home: IntroAnimation(onDone: () => done = true)),
    );
    await tester.pump();

    expect(done, isTrue, reason: 'a phone was left behind the curtain');
  });

  testWidgets('the net catches a curtain that never reports itself done', (
    tester,
  ) async {
    // The animation normally decides its own length by signalling
    // `EyesOpenDone`. If that never arrives — a file that will not load, an
    // event renamed in the editor, a state machine that never settles — the
    // phone still has to reach the board. This is that guarantee, and it is
    // the same class of failure that once left a phone on a screen that never
    // appeared.
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: IntroAnimation(
          duration: const Duration(seconds: 2),
          onDone: () => done = true,
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 3));
    expect(done, isTrue);
  });

  test('the names in the code are the names in the file', () {
    // Five strings have to match what the artist typed in the Rive editor, and
    // not one of them fails loudly: a wrong state machine name throws where it
    // is caught, a wrong event name simply never arrives, and a wrong property
    // name leaves every player the same colour. Pinned here so a rename shows
    // up as a failed test rather than as a curtain nobody can explain.
    expect(IntroAnimation.stateMachine, 'SM1');
    expect(IntroAnimation.startTrigger, 'startGame');
    expect(IntroAnimation.doneEvent, 'EyesOpenDone');
    expect(IntroAnimation.viewModel, 'PersoVM');
    expect(IntroAnimation.colorProperty, 'skinColor');
    expect(IntroAnimation.asset, endsWith('startanimationColors.riv'));
  });

  testWidgets('a colour it cannot apply is not a round it cannot play', (
    tester,
  ) async {
    // There is no Rive runtime here, so nothing can be coloured. The curtain
    // still has to lift — the colour is the flourish, not the mechanism.
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: IntroAnimation(
          playerColor: PlayerPalette.purple.value,
          onDone: () => done = true,
        ),
      ),
    );
    await tester.pump();

    expect(done, isTrue);
  });
}
