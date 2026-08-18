import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:multiscreen_slingshot/sdk/app_controller.dart';
import 'package:multiscreen_slingshot/sdk/model/age_band.dart';
import 'package:multiscreen_slingshot/sdk/model/player_name.dart';
import 'package:multiscreen_slingshot/sdk/ui/role_screen.dart';

/// What the lobby screen will and will not let a name become.
///
/// Both names on this screen leave the device in clear — the player name inside
/// the metrics a client sends its host, the game name on a broadcast beacon —
/// so "is there a text field here" is not a cosmetic question and is worth
/// asserting rather than eyeballing.
void main() {
  Future<void> pumpRole(WidgetTester tester, AgeBand band) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RoleScreen(controller: AppController(), ageBand: band),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an adult gets a field to type in', (tester) async {
    SharedPreferences.setMockInitialValues({'player_name': 'Sebastien'});
    await pumpRole(tester, AgeBand.adult);

    expect(find.widgetWithText(TextField, 'Sebastien'), findsOneWidget);
  });

  testWidgets('a child gets a name and no way to type one', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpRole(tester, AgeBand.child);

    // Nothing on the lobby screen accepts free text at all.
    expect(find.byType(TextField), findsNothing);

    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
    expect(shown.any(PlayerNames.isGenerated), isTrue);
  });

  testWidgets('a typed name already on the phone is replaced for a child',
      (tester) async {
    // The upgrade path, and the shared-phone path: a real name can be sitting
    // in storage before this device is known to belong to a child.
    SharedPreferences.setMockInitialValues({'player_name': 'Sebastien Dube'});
    await pumpRole(tester, AgeBand.child);

    expect(find.textContaining('Sebastien'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('player_name')!;
    expect(PlayerNames.isGenerated(stored), isTrue);
  });

  testWidgets('an adult keeps the name they typed', (tester) async {
    SharedPreferences.setMockInitialValues({'player_name': 'Sebastien Dube'});
    await pumpRole(tester, AgeBand.adult);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('player_name'), 'Sebastien Dube');
  });

  testWidgets('the game is named after whoever is hosting', (tester) async {
    SharedPreferences.setMockInitialValues({'player_name': 'Sebastien'});
    await pumpRole(tester, AgeBand.adult);

    await tester.tap(find.text('Host a game'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, "Sebastien's board"), findsOneWidget);
  });

  testWidgets('a child cannot rename the game either', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpRole(tester, AgeBand.child);

    await tester.tap(find.text('Host a game'));
    await tester.pumpAndSettle();

    expect(find.text('Name your game'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining("'s board"), findsOneWidget);
  });
}
