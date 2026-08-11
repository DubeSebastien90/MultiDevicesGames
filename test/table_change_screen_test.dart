import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/model/table_change.dart';
import 'package:multiscreen_slingshot/sdk/ui/table_change_screen.dart';

/// The bug this screen exists for was that the message went nowhere: the host
/// wrote it down and no widget ever read it. So the test is about what reaches
/// the glass, and about the one distinction that changes what a player does
/// next — carry on, or go back.
void main() {
  var dismissed = 0;
  setUp(() => dismissed = 0);

  Future<void> show(
    WidgetTester tester,
    TableChange change, {
    bool host = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: TableChangeScreen(
        change: change,
        onDismiss: host ? () => dismissed++ : null,
      ),
    ),
  );

  testWidgets('a reshuffle says where the table is going', (tester) async {
    await show(
      tester,
      const TableChange(who: 'AngryHippo left', nextGame: 'Guacamole'),
    );

    expect(find.text('AngryHippo left'), findsOneWidget);
    expect(find.text('Guacamole'), findsOneWidget);
    expect(find.text('Go to next game'), findsOneWidget);
    expect(find.text('Back to the lobby'), findsNothing);
  });

  testWidgets('a dead end offers the menu and promises no game', (tester) async {
    // No `nextGame`, so there must be no next-game panel to read: a player told
    // the round is over and shown a game title in the same breath has been told
    // two different things.
    await show(tester, const TableChange(who: 'AngryHippo left'));

    expect(find.text('AngryHippo left'), findsOneWidget);
    expect(find.text('Back to the lobby'), findsOneWidget);
    expect(find.text('NEXT GAME'), findsNothing);
    expect(find.text('Go to next game'), findsNothing);
  });

  testWidgets('only the host is offered the way out', (tester) async {
    // Everybody reads it; one person acts on it. A joiner with its own button
    // would move its own screen on while the rest of the table sat on the old
    // one — and the host is the only device that can actually change what is
    // being played.
    await show(
      tester,
      const TableChange(who: 'AngryHippo left', nextGame: 'Guacamole'),
      host: false,
    );

    expect(find.text('AngryHippo left'), findsOneWidget,
        reason: 'a joiner was left guessing why its board moved');
    expect(find.text('Go to next game'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Waiting for the host…'), findsOneWidget);
  });

  testWidgets('the button is the way out', (tester) async {
    await show(
      tester,
      const TableChange(who: 'AngryHippo left', nextGame: 'Guacamole'),
    );

    await tester.tap(find.text('Go to next game'));
    expect(dismissed, 1);
  });

  testWidgets('it fills the screen rather than sitting in a corner', (
    tester,
  ) async {
    // It was a banner, and a banner is exactly what it must not be: it appears
    // while people have a finger on the confirm ring, and the thing it says is
    // that the ring no longer means anything.
    await show(
      tester,
      const TableChange(who: 'AngryHippo left', nextGame: 'Guacamole'),
    );

    expect(find.byType(Scaffold), findsOneWidget);
    final size = tester.getSize(find.byType(Scaffold));
    expect(size, tester.view.physicalSize / tester.view.devicePixelRatio);
  });
}
