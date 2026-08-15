import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/slingshot/slingshot_view.dart';
import 'package:multiscreen_slingshot/sdk/contract/view.dart';
import 'package:multiscreen_slingshot/sdk/model/coverage_map.dart';
import 'package:multiscreen_slingshot/sdk/model/phone_layout.dart';
import 'package:multiscreen_slingshot/sdk/model/player.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/model/world_rect.dart';
import 'package:multiscreen_slingshot/sdk/render/player_art.dart';

/// Artwork must never decide whether a game starts.
///
/// Slingshot used to rasterise thirty Lottie frames inside `GameView.load()`,
/// which the client awaits before it has anything to draw. That took real time,
/// and on some machines intermittently never finished — leaving that phone on a
/// screen that never appeared while everyone else played.
///
/// The Lottie sprite is gone and the bird is now the host's face, from the SDK,
/// but the contract it was written to defend has not changed and neither has
/// the way it is proved: `load()` must come back while the picture is still
/// decoding, and every draw before then must still paint something.
ViewContext contextWith({String? host}) => ViewContext(
  phoneId: 'p1',
  board: const WorldRect(0, 0, 30, 10),
  roster: Roster(
    const [
      Player(phoneId: 'p1', color: PlayerPalette.green, label: 'host phone'),
      Player(phoneId: 'p2', color: PlayerPalette.orange, label: 'other'),
    ],
    hostPhoneId: host,
  ),
);

void main() {
  testWidgets('a view is ready before its artwork is', (tester) async {
    final view = SlingshotView(contextWith(host: 'p1'));

    // The sharp end of the fix. `load()` is what the client awaits before it
    // has anything to draw, so it must come back *while the picture is still
    // decoding* — not after. Timing bounds were no use here: the load usually
    // finishes quickly, and the failure was intermittent. This is structural,
    // and fails outright if load() ever waits again.
    await view.load();

    expect(
      PlayerArt.of(PlayerPalette.green, PlayerArtSlot.face).isLoaded,
      isFalse,
      reason: 'load() must start the artwork, not wait for it',
    );

    view.dispose();
  });

  test('the ammunition is whoever is hosting', () {
    // Not the first seat and not board order — a host that drops out and comes
    // back does not reclaim either.
    expect(contextWith(host: 'p2').roster.host?.label, 'other');
    expect(contextWith(host: 'p1').roster.host?.label, 'host phone');
  });

  testWidgets('a table with no host still draws a bird', (tester) async {
    // Before anybody is seated there is no face to fire, and the round must
    // still render — the plain circle ShapeView would have drawn.
    final view = SlingshotView(contextWith());
    await view.load();
    expect(view.context.roster.host, isNull);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    expect(
      () => view.render(canvas, _frame()),
      returnsNormally,
      reason: 'a missing host must not take the round down',
    );
    recorder.endRecording();
  });
}

/// The barest frame a view can be asked to draw: no entities, no state.
Frame _frame() => const Frame(
  entities: {},
  sharedState: {},
  scores: ScoreView.empty,
  timeMs: 0,
  dt: 0.016,
  me: PhoneLayout(
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
    board: WorldRect(0, 0, 30, 10),
    placement: '',
  ),
  board: WorldRect(0, 0, 30, 10),
  coverage: CoverageMap(screens: [], board: WorldRect(0, 0, 30, 10)),
);
