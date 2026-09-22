import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/ui/lobby_view.dart';

/// Reset throws away every score in the lobby and there is nothing to undo it
/// with, so the question it asks first is the whole of the safety on it.
///
/// The real dialog, driven through the real function the lobby calls — which
/// is why that function answers rather than acts: a question can be put to a
/// test, a host and a socket cannot.
void main() {
  /// A screen with one button on it, which asks and remembers the answer.
  Future<List<bool?>> ask(WidgetTester tester) async {
    final answers = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async =>
                    answers.add(await confirmResetScores(context)),
                child: const Text('reset'),
              ),
            ),
          ),
        ),
      ),
    );
    return answers;
  }

  testWidgets('it asks, in words somebody can answer', (tester) async {
    final answers = await ask(tester);

    await tester.tap(find.text('reset'));
    await tester.pumpAndSettle();

    expect(find.text('Reset scores?'), findsOneWidget);
    expect(
      find.text('Do you really want to reset all scores on this lobby?'),
      findsOneWidget,
    );
    expect(answers, isEmpty, reason: 'it answered before anybody did');
  });

  testWidgets('backing out is no', (tester) async {
    final answers = await ask(tester);

    await tester.tap(find.text('reset'));
    await tester.pumpAndSettle();
    // The flow's back pill, which is what a dialog's cancel looks like here.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(answers, [false]);
  });

  testWidgets('the red button is yes', (tester) async {
    final answers = await ask(tester);

    await tester.tap(find.text('reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(answers, [true]);
  });

  testWidgets('dismissing it another way reads as no', (tester) async {
    // A route popped from somewhere else, or a back gesture: the dialog
    // returns nothing, and nothing must not be taken for yes.
    final answers = await ask(tester);

    await tester.tap(find.text('reset'));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();

    expect(answers, [false]);
  });
}
