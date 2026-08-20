import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:multiscreen_slingshot/sdk/model/age_band.dart';
import 'package:multiscreen_slingshot/sdk/model/player_name.dart';
import 'package:multiscreen_slingshot/sdk/ui/age_gate_screen.dart';

void main() {
  group('classify', () {
    final now = DateTime(2026, 6, 15);

    test('comfortably under is a child', () {
      expect(
        AgeGatePref.classify(birthYear: 2020, birthMonth: 3, now: now),
        AgeBand.child,
      );
    });

    test('comfortably over is an adult', () {
      expect(
        AgeGatePref.classify(birthYear: 1990, birthMonth: 3, now: now),
        AgeBand.adult,
      );
    });

    test('the year the birthday has already passed in', () {
      // Born May 2013, so thirteen since last month.
      expect(
        AgeGatePref.classify(birthYear: 2013, birthMonth: 5, now: now),
        AgeBand.adult,
      );
    });

    test('the birthday month itself rounds down', () {
      // Born June 2013 and it is June: twelve or thirteen depending on a day
      // nobody was asked for. The ambiguous case is the guarded one.
      expect(
        AgeGatePref.classify(birthYear: 2013, birthMonth: 6, now: now),
        AgeBand.child,
      );
    });

    test('one month short of the birthday', () {
      expect(
        AgeGatePref.classify(birthYear: 2013, birthMonth: 7, now: now),
        AgeBand.child,
      );
    });
  });

  group('isPlausible', () {
    final now = DateTime(2026, 6, 15);

    test('rejects the future', () {
      expect(
        AgeGatePref.isPlausible(birthYear: 2027, birthMonth: 1, now: now),
        isFalse,
      );
      expect(
        AgeGatePref.isPlausible(birthYear: 2026, birthMonth: 9, now: now),
        isFalse,
      );
    });

    test('rejects nonsense months and the distant past', () {
      expect(
        AgeGatePref.isPlausible(birthYear: 2000, birthMonth: 13, now: now),
        isFalse,
      );
      expect(
        AgeGatePref.isPlausible(birthYear: 1800, birthMonth: 6, now: now),
        isFalse,
      );
    });

    test('accepts a date a child would give', () {
      // The typo filter must not double as an age check, or the error message
      // becomes the announcement of the threshold.
      expect(
        AgeGatePref.isPlausible(birthYear: 2020, birthMonth: 6, now: now),
        isTrue,
      );
    });
  });

  group('storage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('nothing stored means the question has not been asked', () async {
      expect(await AgeGatePref.load(), AgeBand.unknown);
    });

    test('a saved band survives', () async {
      await AgeGatePref.save(AgeBand.adult);
      expect(await AgeGatePref.load(), AgeBand.adult);
    });

    test('the date itself is never written', () async {
      await AgeGatePref.save(
        AgeGatePref.classify(
          birthYear: 1987,
          birthMonth: 4,
          now: DateTime(2026, 6, 15),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getKeys().map((k) => '$k=${prefs.get(k)}').join(',');
      expect(stored, isNot(contains('1987')));
      expect(stored, isNot(contains('4')));
    });

    test('child cannot be overwritten by adult', () async {
      await AgeGatePref.save(AgeBand.child);
      await AgeGatePref.save(AgeBand.adult);
      expect(await AgeGatePref.load(), AgeBand.child);
    });

    test('unknown is not a savable state', () async {
      await AgeGatePref.save(AgeBand.adult);
      await AgeGatePref.save(AgeBand.unknown);
      expect(await AgeGatePref.load(), AgeBand.adult);
    });

    test('an unrecognised stored value asks again', () async {
      SharedPreferences.setMockInitialValues({'ageBand': 'grown-up'});
      expect(await AgeGatePref.load(), AgeBand.unknown);
    });
  });

  group('isGenerated', () {
    test('accepts what random() makes', () {
      for (var i = 0; i < 200; i++) {
        expect(PlayerNames.isGenerated(PlayerNames.random()), isTrue);
      }
    });

    test('rejects a typed name, including one wearing a generated one', () {
      expect(PlayerNames.isGenerated('Sebastien'), isFalse);
      expect(PlayerNames.isGenerated('SpicyYak Smith'), isFalse);
      expect(PlayerNames.isGenerated('Spicy Yak'), isFalse);
      expect(PlayerNames.isGenerated(''), isFalse);
    });
  });

  group('AgeGate', () {
    Widget gate() => MaterialApp(
          home: AgeGate(
            builder: (_, band) => Text('through:$band'),
          ),
        );

    testWidgets('asks on a fresh install and blocks what is behind it',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(gate());
      await tester.pumpAndSettle();

      expect(find.text('When were you born?'), findsOneWidget);
      expect(find.textContaining('through:'), findsNothing);
    });

    testWidgets('does not ask twice', (tester) async {
      SharedPreferences.setMockInitialValues({'ageBand': 'adult'});
      await tester.pumpWidget(gate());
      await tester.pumpAndSettle();

      expect(find.text('When were you born?'), findsNothing);
      expect(find.text('through:AgeBand.adult'), findsOneWidget);
    });

    testWidgets('names no threshold anywhere on the screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(gate());
      await tester.pumpAndSettle();

      final words = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(words, isNot(contains('13')));
      expect(words.toLowerCase(), isNot(contains('age')));
      expect(words.toLowerCase(), isNot(contains('old')));
      expect(words.toLowerCase(), isNot(contains('adult')));
      expect(words.toLowerCase(), isNot(contains('child')));
    });

    testWidgets('will not continue on an empty answer', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(gate());
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('a young answer passes through silently', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(gate());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('March').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2020');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Straight through, with nothing said about why.
      expect(find.text('through:AgeBand.child'), findsOneWidget);
      expect(await AgeGatePref.load(), AgeBand.child);
    });
  });
}
