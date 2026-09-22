import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_game.dart';
import 'package:multiscreen_slingshot/sdk/client/interruption_watcher.dart';
import 'package:multiscreen_slingshot/sdk/host/name_drop_detector.dart';
import 'package:multiscreen_slingshot/sdk/layout/layouts.dart';
import 'package:multiscreen_slingshot/sdk/layout/name_drop_optimizer.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/name_drop_status.dart';
import 'package:multiscreen_slingshot/sdk/ui/name_drop_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

PhoneSpec spec(String id, double widthMm) => PhoneSpec(
  phoneId: id,
  label: 'phone $id',
  widthMm: widthMm,
  heightMm: widthMm * 2400 / 1080,
  bezelMm: 3,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: 1080,
  activePxHeight: 2400,
);

void main() {
  group('the stored answer', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts out unanswered', () async {
      expect(await NameDropPref.load(), NameDropStatus.waiting);
    });

    for (final status in NameDropStatus.values) {
      test('survives a round trip as $status', () async {
        await NameDropPref.save(status);
        expect(await NameDropPref.load(), status);
      });
    }

    // The two answered states each suppress the notice for good, so guessing
    // one of them from a value we cannot read is a permanent silence bought
    // with a coin flip. Asking once more is the harmless way to be wrong.
    test('reads an unrecognised value as unanswered', () async {
      SharedPreferences.setMockInitialValues({'nameDropStatus': 'yes'});
      expect(await NameDropPref.load(), NameDropStatus.waiting);
    });

    test('is stored by name, so reordering the enum cannot rewrite it',
        () async {
      await NameDropPref.save(NameDropStatus.declined);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('nameDropStatus'), 'declined');
    });
  });

  group('which pairs are still dangerous', () {
    test('a stack the optimizer can fix leaves none', () {
      final lobby = LobbyInfo([spec('p1', 60), spec('p2', 74)]);
      // Phones stacked in a column, casings touching — the arrangement this
      // whole subsystem exists for. Asked of the platform directly rather than
      // borrowed from whichever game happens to lay phones out that way.
      final plan = Layouts.column(
        lobby.phones,
        sort: PhoneSort.largestLast,
        align: CrossAlign.center,
        gap: Gaps.casingsTouching,
      );
      final fixed = NameDropOptimizer.optimize(plan, lobby);

      expect(NameDropOptimizer.dangerousPairs(plan, lobby), isNotEmpty,
          reason: 'the raw plan faces both phones the same way — this is the '
              'arrangement the optimizer exists to fix');
      expect(NameDropOptimizer.dangerousPairs(fixed, lobby), isEmpty,
          reason: 'turning one phone around put the two tops apart, so there '
              'is nothing left for the runtime detector to watch for');
    });

    test('pairs read the same from either end', () {
      expect(NameDropOptimizer.pairKey('p1', 'p2'),
          NameDropOptimizer.pairKey('p2', 'p1'));
    });

    // A ring of phones around a table never puts two tops together, so a game
    // built that way should hand the detector nothing at all.
    test('a ring leaves none', () {
      final lobby = LobbyInfo([
        for (var i = 1; i <= 4; i++) spec('p$i', 68),
      ]);
      final plan = const HotPotatoGame().planBoard(lobby);
      expect(
        NameDropOptimizer.dangerousPairs(
          NameDropOptimizer.optimize(plan, lobby),
          lobby,
        ),
        isEmpty,
      );
    });
  });

  group('deciding it was NameDrop', () {
    const pair = ('p1', 'p2');
    final dangerous = {pair};

    test('one phone on its own is never enough', () {
      final detector = NameDropDetector();
      // Whatever a single phone reports, and however often, the answer stays
      // no: this is the case a stray home-indicator swipe produces all
      // evening, and it is the reason single-device detection was never on
      // the table.
      for (var i = 0; i < 5; i++) {
        expect(
          detector.report('p1', const Duration(milliseconds: 900), dangerous),
          isNull,
        );
      }
    });

    test('two phones at the same moment is', () {
      final detector = NameDropDetector();
      expect(detector.report('p1', const Duration(seconds: 1), dangerous),
          isNull);
      expect(detector.report('p2', const Duration(seconds: 1), dangerous),
          pair);
    });

    // The two people dismiss the card at their own speed, so the reports reach
    // the host many seconds apart. What has to line up is when the two
    // interruptions *began*, which is the whole reason the wire carries an age
    // rather than a timestamp — the phones share no clock to stamp one with.
    test('still counts when one player sat looking at the card', () {
      var now = Duration.zero;
      final detector = NameDropDetector(clock: () => now);

      // Both cards appeared at t=10s. p1 swipes it away a second later.
      now = const Duration(seconds: 11);
      expect(detector.report('p1', const Duration(seconds: 1), dangerous),
          isNull);

      // p2 stares at it for nine, and reports at t=19 an interruption that
      // began nine seconds ago — the same instant p1's did.
      now = const Duration(seconds: 19);
      expect(detector.report('p2', const Duration(seconds: 9), dangerous),
          pair);
    });

    test('forgets a report nobody ever matched', () {
      var now = Duration.zero;
      final detector = NameDropDetector(clock: () => now);

      expect(detector.report('p1', const Duration(seconds: 1), dangerous),
          isNull);
      // Well past the memory window, so this is a new event that happens to
      // involve the same two phones, not a partner for the old one.
      now = const Duration(seconds: 90);
      expect(detector.report('p2', const Duration(seconds: 1), dangerous),
          isNull);
    });

    test('two phones that are not a dangerous pair is not', () {
      final detector = NameDropDetector();
      expect(detector.report('p1', const Duration(seconds: 1), const {}),
          isNull);
      expect(detector.report('p2', const Duration(seconds: 1), const {}),
          isNull);
    });

    test('two interruptions that began minutes apart is not', () {
      final detector = NameDropDetector();
      expect(detector.report('p1', const Duration(seconds: 1), dangerous),
          isNull);
      // Began 20 seconds before p1's did.
      expect(detector.report('p2', const Duration(seconds: 21), dangerous),
          isNull);
    });

    test('a nonsense age is ignored', () {
      final detector = NameDropDetector();
      expect(detector.report('p1', const Duration(seconds: 1), dangerous),
          isNull);
      expect(detector.report('p2', const Duration(hours: 3), dangerous),
          isNull);
      expect(detector.report('p2', const Duration(seconds: -5), dangerous),
          isNull);
    });

    test('one event is only raised once', () {
      final detector = NameDropDetector();
      detector.report('p1', const Duration(seconds: 1), dangerous);
      expect(detector.report('p2', const Duration(seconds: 1), dangerous),
          pair);
      // Both entries were spent, so a third report has nothing to pair with.
      expect(detector.report('p1', const Duration(seconds: 1), dangerous),
          isNull);
    });

    test('rearranging the table forgets what was pending', () {
      final detector = NameDropDetector();
      detector.report('p1', const Duration(seconds: 1), dangerous);
      detector.clear();
      expect(detector.report('p2', const Duration(seconds: 1), dangerous),
          isNull);
    });
  });

  group('the notice', () {
    /// Puts the sheet on screen and hands back whatever it answers.
    Future<NameDropStatus?> show(WidgetTester tester) async {
      NameDropStatus? answer;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await showNameDropNotice(context),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('names the setting the way Settings does', (tester) async {
      await show(tester);
      expect(find.textContaining('Bringing Devices Together'), findsWidgets);
    });

    testWidgets('taking their word for it closes it', (tester) async {
      await show(tester);
      await tester.tap(find.text('Already done'));
      await tester.pumpAndSettle();
      expect(find.text('Already done'), findsNothing);
    });

    testWidgets('so does declining', (tester) async {
      await show(tester);
      await tester.tap(find.text('No thanks'));
      await tester.pumpAndSettle();
      expect(find.text('No thanks'), findsNothing);
    });

    // The one button that cannot do the obvious thing: no public API opens
    // General → AirDrop, and the scheme that does is one Apple rejects apps
    // for. So it explains the path instead, and the walk ends in the answer.
    testWidgets('walking through it ends the question', (tester) async {
      await show(tester);
      await tester.tap(find.text('How?'));
      await tester.pumpAndSettle();

      // Both halves of it: a picture of where to tap, and the word to look
      // for on the screen in that picture. The two answer different questions
      // — where, and what — and a walkthrough with only one of them sends
      // somebody who has drifted a screen away back to the start.
      expect(find.byType(Image), findsNWidgets(4));
      expect(find.textContaining('Settings'), findsWidgets);
      expect(find.textContaining('AirDrop'), findsWidgets);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('How?'), findsNothing);
    });

    // Somebody who opened the instructions, got lost and came back has not
    // told us anything, and the honest record of that is the unanswered
    // question they were already looking at.
    testWidgets('backing out of it lands back on the question',
        (tester) async {
      await show(tester);
      await tester.tap(find.text('How?'));
      await tester.pumpAndSettle();

      // The flow's own back pill, not Material's: `pageBack` hunts for an
      // AppBar back button, and this screen wears a coral pill instead.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('How?'), findsOneWidget);
      expect(find.text('Already done'), findsOneWidget);
    });
  });

  group('what counts as an interruption', () {
    late List<Duration> reported;
    late InterruptionWatcher watcher;

    setUp(() {
      reported = [];
      watcher = InterruptionWatcher(reported.add);
    });

    // The dominant false positive: phones lie flat on a table with people
    // reaching over them, and a half-completed home-indicator swipe resigns
    // active and snaps straight back.
    test('a flicker is not', () {
      watcher.didChangeAppLifecycleState(AppLifecycleState.inactive);
      watcher.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(reported, isEmpty);
    });

    test('leaving the app is not, however long it lasts', () async {
      watcher.didChangeAppLifecycleState(AppLifecycleState.inactive);
      watcher.didChangeAppLifecycleState(AppLifecycleState.hidden);
      watcher.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      // The trip back passes through inactive a second time, which must not
      // look like a fresh interruption.
      watcher.didChangeAppLifecycleState(AppLifecycleState.inactive);
      watcher.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(reported, isEmpty);
    });

    test('something covering the screen for a while is', () async {
      watcher.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      watcher.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(reported, hasLength(1));
      expect(reported.single, greaterThanOrEqualTo(
          const Duration(milliseconds: 500)));
    });

    test('a second one is judged on its own', () async {
      watcher.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      watcher.didChangeAppLifecycleState(AppLifecycleState.resumed);

      watcher.didChangeAppLifecycleState(AppLifecycleState.inactive);
      watcher.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(reported, hasLength(1),
          reason: 'the clock has to be let go of after each one, or every '
              'flicker inherits the last real interruption’s length');
    });
  });
}
