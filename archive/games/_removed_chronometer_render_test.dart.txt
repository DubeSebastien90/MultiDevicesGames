import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/chronometer/chronometer_config.dart';
import 'package:multiscreen_slingshot/games/chronometer/chronometer_game.dart';
import 'package:multiscreen_slingshot/games/chronometer/chronometer_sim.dart';
import 'package:multiscreen_slingshot/games/chronometer/chronometer_view.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/view.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// Does the thing actually put pixels on a screen?
///
/// The rest of the suite drives the sim and never paints, which is most of what
/// matters — but it would pass just as happily against a view that drew nothing
/// at all. This one renders every phase to a real image and looks at what came
/// out.
///
/// Deliberately not a golden test. Goldens on a game whose whole look is
/// gradients and eased animation are a bitmap that has to be regenerated every
/// time a radius is nudged, and they fail on any machine whose text rasterises
/// half a pixel differently. What is checked here is the thing that actually
/// goes wrong: a phase that renders nothing, a shape that overflows the screen,
/// text that is not really text.
PhoneSpec phone(String id, PlayerColor c) => PhoneSpec(
      phoneId: id,
      label: 'phone $id',
      widthMm: 68.58,
      heightMm: 152.4,
      bezelMm: 3,
      dpi: 400,
      devicePixelRatio: 3,
      activePxWidth: 1080,
      activePxHeight: 2400,
      color: c,
    );

const _dt = 1 / 60;
const _w = 300;
const _h = 660;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BoardLayout board;
  late ChronometerSim sim;
  late ChronometerView view;
  late Scoreboard scores;

  setUp(() {
    final lobby = LobbyInfo([
      for (var i = 0; i < 3; i++) phone('p${i + 1}', PlayerPalette.all[i]),
    ]);
    scores = Scoreboard();
    for (final p in lobby.phones) {
      scores.register(p.phoneId, p.label);
    }
    const game = ChronometerGame();
    board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
    sim = ChronometerSim(board.contextFor(scores), random: math.Random(3));
    scores.beginRound();
    view = ChronometerView(ViewContext(phoneId: 'p1', board: board.board));
  });

  /// Paint one frame of p1's screen and hand back the pixels.
  Future<ui.Image> shoot({double timeMs = 500}) async {
    final layout = board.forPhone('p1')!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // The camera the platform would apply: fit this phone's slice to the image.
    final v = layout.viewport;
    final scale = math.min(_w / v.width, _h / v.height);
    canvas.translate(_w / 2, _h / 2);
    canvas.scale(scale);
    canvas.translate(-(v.left + v.width / 2), -(v.top + v.height / 2));

    view.render(
      canvas,
      Frame(
        entities: const {},
        sharedState: sim.sharedState,
        scores: scores.view,
        timeMs: timeMs,
        dt: _dt,
        me: layout,
        board: board.board,
        coverage: board.coverage,
      ),
    );
    return recorder.endRecording().toImage(_w, _h);
  }

  /// How many distinct colours are on screen, as a proxy for "something was
  /// drawn". A blank phase scores a handful; a real one scores hundreds.
  Future<int> paletteSize(ui.Image image) async {
    final raw = await image.toByteData();
    final seen = <int>{};
    for (var i = 0; i < raw!.lengthInBytes; i += 4) {
      seen.add(raw.getUint32(i));
    }
    return seen.length;
  }

  void runTo(String phase) {
    var guard = 0;
    while (sim.sharedState['phase'] != phase) {
      sim.step(_dt);
      if (guard++ > 60 * 120) fail('never reached $phase');
    }
  }

  group('the circle is the time', () {
    // The dial's whole claim: one full turn is the target, so where a pip sits
    // is *when* that player pressed. Checked through the public geometry the
    // view draws from rather than through pixels, because an angle is the thing
    // that is actually being asserted.
    ({Offset centre, double radius}) dialOn(double screenPx) =>
        (centre: Offset.zero, radius: screenPx);

    /// The angle of a pip, in turns clockwise from twelve o'clock.
    double turnsOf(double guess, double target) {
      final dial = dialOn(100);
      final at = ChronometerView.debugPipCentre(
        dial,
        guess,
        target + ChronometerConfig.graceSeconds,
        target,
      );
      // Back out the angle: the view measures clockwise from straight up.
      final a = math.atan2(at.dx, -at.dy);
      return (a < 0 ? a + 2 * math.pi : a) / (2 * math.pi);
    }

    test('a perfect guess lands back at twelve o clock', () {
      for (final target in [3.0, 9.0, 15.0]) {
        final turns = turnsOf(target, target);
        // Either end of the lap is the top of the dial.
        expect(math.min(turns, 1 - turns), lessThan(0.001),
            reason: 'a perfect guess on a ${target}s round is not at the top');
      }
    });

    test('half the target is half way round, whatever the target', () {
      // The bug this replaces: dividing by target-plus-grace made the same
      // fraction of the round land somewhere different every game.
      for (final target in [3.0, 9.0, 15.0]) {
        expect(turnsOf(target / 2, target), closeTo(0.5, 0.001),
            reason: 'half of ${target}s is not at six o clock');
      }
    });

    test('a quarter and three quarters sit opposite each other', () {
      expect(turnsOf(2.25, 9), closeTo(0.25, 0.001));
      expect(turnsOf(6.75, 9), closeTo(0.75, 0.001));
    });

    test('a late guess runs past the top rather than wrapping onto early', () {
      // A guess past the target keeps going into a second lap. If it wrapped it
      // would sit beside somebody who pressed far too soon, which is the one
      // reading the dial must never give.
      final dial = dialOn(100);
      final late = ChronometerView.debugPipCentre(dial, 10.5, 14.0, 9.0);
      expect(late.dx, greaterThan(0),
          reason: 'just-late belongs on the clockwise side of the notch');
    });

    test('a wildly late guess pins instead of lapping the early side', () {
      final dial = dialOn(100);
      // Target 3s with the full grace window is 8s — nearly three laps if it
      // were left unclamped.
      final pinned = ChronometerView.debugPipCentre(dial, 8.0, 8.0, 3.0);
      final capped = ChronometerView.debugPipCentre(
        dial,
        ChronometerConfig.maxLapTurns * 3.0,
        8.0,
        3.0,
      );
      expect((pinned - capped).distance, lessThan(0.01),
          reason: 'past the cap every late guess sits in the same place');
    });
  });

  group('the results belong to the phone showing them', () {
    /// Play a round where [winner] presses closest, then render [phoneId]'s
    /// results screen and hand back its pixels.
    Future<ui.Image> resultsOn(String phoneId, {required String winner}) async {
      final target = sim.targetSeconds;
      runTo(ChronoPhase.running);

      // Everybody presses, the named phone closest.
      final plan = <String, double>{
        for (final id in ['p1', 'p2', 'p3'])
          id: id == winner ? target : target - 2.5 - (id == 'p2' ? 1.0 : 0),
      };
      final order = plan.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      var now = 0.0;
      for (final e in order) {
        for (var i = 0; i < ((e.value - now) * 60).round(); i++) {
          sim.step(_dt);
        }
        now = e.value;
        sim.onTouch(TouchEvent(
            phoneId: e.key, worldX: 0, worldY: 0, phase: TouchPhase.down));
      }

      final view = ChronometerView(
        ViewContext(phoneId: phoneId, board: board.board),
      );
      final layout = board.forPhone(phoneId)!;

      // Fly the disc all the way in.
      late ui.Image out;
      for (var i = 0; i < 120; i++) {
        sim.step(_dt);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final v = layout.viewport;
        final scale = math.min(_w / v.width, _h / v.height);
        canvas.translate(_w / 2, _h / 2);
        canvas.scale(scale);
        canvas.translate(-(v.left + v.width / 2), -(v.top + v.height / 2));
        view.render(
          canvas,
          Frame(
            entities: const {},
            sharedState: sim.sharedState,
            scores: scores.view,
            timeMs: 3000 + i * 16.0,
            dt: _dt,
            me: layout,
            board: board.board,
            coverage: board.coverage,
          ),
        );
        out = await recorder.endRecording().toImage(_w, _h);
      }
      return out;
    }

    /// The colour filling the middle of the screen, as a coarse hue bucket.
    Future<(int, int, int)> middlePixel(ui.Image image) async {
      final raw = await image.toByteData();
      final i = ((_h ~/ 2) * _w + _w ~/ 2) * 4;
      return (
        raw!.getUint8(i),
        raw.getUint8(i + 1),
        raw.getUint8(i + 2),
      );
    }

    test('two phones show two different discs in the middle', () async {
      // The bug this replaces: the winner flew into the centre of *every*
      // screen, so four phones showed the same person's time and three players
      // had to hunt a list for their own.
      final onWinner = await middlePixel(await resultsOn('p2', winner: 'p2'));

      // A fresh round, same shape, rendered for a phone that lost.
      sim.reset();
      final onLoser = await middlePixel(await resultsOn('p1', winner: 'p2'));

      expect(onWinner, isNot(onLoser),
          reason: 'both phones are showing the same disc in the middle');
    });

    test('the middle of your screen is your own colour', () async {
      // p1 is Green and loses; the middle should still be green, not the
      // winner's orange.
      final (r, g, b) = await middlePixel(await resultsOn('p1', winner: 'p2'));
      expect(g, greaterThan(r),
          reason: 'the middle of p1 screen is not p1 own colour');
      expect(g, greaterThan(b));
    });
  });

  test('a turned phone draws the same picture as an unturned one', () async {
    // The star turns two of three phones by 120° and 240°, and the platform
    // camera rotates the world to match. The view undoes that when it draws, so
    // what lands on the glass has to be identical on every phone — same dial,
    // same upright text — regardless of which arm of the star it is.
    //
    // Rendered through the camera the app actually applies, angle included,
    // because the angle is the entire thing under test.
    runTo(ChronoPhase.running);

    Future<ui.Image> shootAsApp(String phoneId) async {
      final layout = board.forPhone(phoneId)!;
      final view = ChronometerView(
        ViewContext(phoneId: phoneId, board: board.board),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final scale = math.min(
        _w / (layout.halfWidth * 2),
        _h / (layout.halfHeight * 2),
      );
      canvas.translate(_w / 2, _h / 2);
      canvas.scale(scale);
      canvas.rotate(layout.turnRadians);
      canvas.translate(-layout.worldCenterX, -layout.worldCenterY);

      view.render(
        canvas,
        Frame(
          entities: const {},
          sharedState: sim.sharedState,
          scores: scores.view,
          timeMs: 2400,
          dt: _dt,
          me: layout,
          board: board.board,
          coverage: board.coverage,
        ),
      );
      return recorder.endRecording().toImage(_w, _h);
    }

    // The dial's rim, sampled where it crosses the vertical centre line. On an
    // upright dial the notch sits at the top; on a dial that kept the camera's
    // turn it would have swung a third of the way round and this row would be
    // empty background.
    Future<int> rimRowAboveCentre(ui.Image image) async {
      final raw = await image.toByteData();
      var lit = 0;
      // A band just above the middle, where the top of the ring must fall.
      for (var y = (_h * 0.30).round(); y < (_h * 0.40).round(); y++) {
        for (var x = 0; x < _w; x++) {
          final i = (y * _w + x) * 4;
          final r = raw!.getUint8(i);
          final g = raw.getUint8(i + 1);
          final b = raw.getUint8(i + 2);
          // Anything a player is drawn in, and nothing of the background.
          //
          // Not a round number picked by eye: the background is 0x0B1020,
          // which sums to 59, and the darkest swatch in the palette sums to
          // 293. Half way between the two is clear of both, and stays clear if
          // the palette is re-tuned. The previous 300 sat *above* one of the
          // swatches, so a re-coloured player simply stopped being counted.
          if (r + g + b > 150) lit++;
        }
      }
      return lit;
    }

    final upright = await rimRowAboveCentre(await shootAsApp('p1'));
    final turned = await rimRowAboveCentre(await shootAsApp('p2'));
    final alsoTurned = await rimRowAboveCentre(await shootAsApp('p3'));

    expect(board.forPhone('p2')!.turnRadians, isNot(0),
        reason: 'p2 must actually be turned or this proves nothing');

    // Within a few percent: the same rim, in the same place, on all three.
    expect((turned - upright).abs(), lessThan(upright * 0.25 + 40),
        reason: 'the turned phone is not drawing the dial where p1 does');
    expect((alsoTurned - upright).abs(), lessThan(upright * 0.25 + 40),
        reason: 'the second turned phone is off too');
  });

  test('every phase puts something on the screen', () async {
    expect(await paletteSize(await shoot()), greaterThan(50),
        reason: 'the reveal is blank');

    runTo(ChronoPhase.countdown);
    expect(await paletteSize(await shoot(timeMs: 1200)), greaterThan(50),
        reason: 'the countdown is blank');

    runTo(ChronoPhase.running);
    expect(await paletteSize(await shoot(timeMs: 2000)), greaterThan(50),
        reason: 'the running phase is blank');
  });

  test('a landed guess adds to the picture', () async {
    runTo(ChronoPhase.running);
    final before = await paletteSize(await shoot(timeMs: 2000));

    for (var i = 0; i < 120; i++) {
      sim.step(_dt);
    }
    sim.onTouch(const TouchEvent(
        phoneId: 'p1', worldX: 0, worldY: 0, phase: TouchPhase.down));

    expect(await paletteSize(await shoot(timeMs: 2600)), greaterThan(before),
        reason: 'a pip landed and nothing changed on screen');
  });

  test('the winner disc stays inside the screen once it lands', () async {
    // It grew to nearly the whole dial to be the hero of the results screen,
    // which is exactly the change that would push it off a narrow phone.
    runTo(ChronoPhase.running);
    for (final id in ['p1', 'p2', 'p3']) {
      sim.onTouch(TouchEvent(
          phoneId: id, worldX: 0, worldY: 0, phase: TouchPhase.down));
    }
    expect(sim.sharedState['phase'], ChronoPhase.results);

    // Fly it all the way in.
    for (var i = 0; i < 120; i++) {
      sim.step(_dt);
      await shoot(timeMs: 3000 + i * 16.0);
    }

    final image = await shoot(timeMs: 5000);
    final raw = await image.toByteData();

    // The disc is the brightest thing on screen. If any of it is against an
    // edge, it has overflowed.
    bool lit(int x, int y) {
      final i = (y * _w + x) * 4;
      final r = raw!.getUint8(i);
      final g = raw.getUint8(i + 1);
      final b = raw.getUint8(i + 2);
      return r + g + b > 330;
    }

    // The phone's own slice, not the whole image — the letterboxing above and
    // below it is not the game's to fill.
    final layout = board.forPhone('p1')!;
    final v = layout.viewport;
    final scale = math.min(_w / v.width, _h / v.height);
    final top = (_h / 2 - v.height * scale / 2).ceil() + 2;
    final bottom = (_h / 2 + v.height * scale / 2).floor() - 2;

    for (var y = top; y < bottom; y++) {
      expect(lit(1, y), isFalse, reason: 'the disc reaches the left edge');
      expect(lit(_w - 2, y), isFalse,
          reason: 'the disc reaches the right edge');
    }
  });

  test('the results screen is legible before the platform tears it down',
      () async {
    // The flight has to finish, and the landed disc has to still be up.
    runTo(ChronoPhase.running);
    for (final id in ['p1', 'p2', 'p3']) {
      sim.onTouch(TouchEvent(
          phoneId: id, worldX: 0, worldY: 0, phase: TouchPhase.down));
    }

    var elapsed = 0.0;
    while (sim.outcome == null) {
      sim.step(_dt);
      elapsed += _dt;
      if (elapsed > 30) fail('the round never ended');
    }

    expect(elapsed * 1000, greaterThan(ChronometerConfig.winnerFlightMs),
        reason: 'the disc was still in the air when the round ended');
  });
}
