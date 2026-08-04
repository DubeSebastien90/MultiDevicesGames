import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';

/// How a round ends, and what each phone is told about it.
///
/// Every phone used to be congratulated: the outcome was one boolean for the
/// whole table, no game ever reported a loss, and the losing side of Flood read
/// "You win!" over a summary saying the other team had won. A game now declares
/// what *kind* of ending it was, and the platform turns that into words.
RoundResult resultFor(GameOutcome outcome) {
  // Through JSON on purpose: a joiner only ever sees what came down the wire,
  // so anything that does not survive the trip does not exist.
  final wire = jsonEncode({
    'kind': outcome.kind.name,
    'won': outcome.won,
    'summary': outcome.summary,
    'gameTitle': 'Arena',
    if (outcome.winners != null) 'winners': outcome.winners!.toList(),
    if (outcome.lines != null) 'lines': outcome.lines,
  });
  return RoundResult.fromJson(
    jsonDecode(wire) as Map<String, dynamic>,
  );
}

void main() {
  group('a contest', () {
    final result = resultFor(const GameOutcome.contest(
      winners: {'p1', 'p3'},
      summary: 'blue flooded the board',
    ));

    test('congratulates the winners', () {
      for (final id in ['p1', 'p3']) {
        final verdict = result.verdictFor(id);
        expect(verdict.headline, 'You win!');
        expect(verdict.celebrate, isTrue);
      }
    });

    test('and tells everybody else', () {
      final verdict = result.verdictFor('p2');
      expect(verdict.headline, 'You lost');
      expect(verdict.celebrate, isFalse);
    });

    test('the shared summary is still there for both', () {
      expect(result.summary, 'blue flooded the board');
    });
  });

  group('a draw', () {
    test('is its own ending, not a win nobody had', () {
      final result = resultFor(const GameOutcome.draw(summary: 'dead level'));
      for (final id in ['p1', 'p2']) {
        final verdict = result.verdictFor(id);
        expect(verdict.headline, 'A draw');
        expect(verdict.celebrate, isFalse);
      }
    });
  });

  group('a per-phone ending', () {
    final result = resultFor(const GameOutcome.perPhone(
      {'p1': 'You made 40 points', 'p2': 'You made 5 points'},
      summary: 'last one standing',
    ));

    test('gives each phone its own line under one headline', () {
      // The headline belongs to the platform so five phones cannot word the
      // same result differently; the line under it belongs to the game.
      expect(result.verdictFor('p1').headline, 'Well played!');
      expect(result.verdictFor('p1').line, 'You made 40 points');
      expect(result.verdictFor('p2').line, 'You made 5 points');
    });

    test('a phone the game said nothing about still reads properly', () {
      final verdict = result.verdictFor('p9');
      expect(verdict.headline, 'Well played!');
      expect(verdict.line, isNull);
    });
  });

  group('a shared ending', () {
    test('is what a co-operative game gets, unchanged', () {
      final result = resultFor(const GameOutcome.won(summary: '10 caught'));
      expect(result.verdictFor('p1').headline, 'You win!');
      expect(result.verdictFor('p2').headline, 'You win!',
          reason: 'the table did it together');
    });

    test('and a failure says so', () {
      final result = resultFor(const GameOutcome.lost(summary: 'time ran out'));
      expect(result.verdictFor('p1').headline, 'Round over');
      expect(result.verdictFor('p1').celebrate, isFalse);
    });
  });

  test('lines can ride along with a contest', () {
    // Both at once: won or lost, *and* what you personally did.
    final result = resultFor(const GameOutcome.contest(
      winners: {'p1'},
      lines: {'p1': '3 kills', 'p2': '1 kill'},
    ));

    expect(result.verdictFor('p1').headline, 'You win!');
    expect(result.verdictFor('p1').line, '3 kills');
    expect(result.verdictFor('p2').headline, 'You lost');
    expect(result.verdictFor('p2').line, '1 kill');
  });

  test('an older host that says nothing about kind is a shared win', () {
    // The wire gains fields; a message without them still has to render.
    final result = RoundResult.fromJson({'won': true, 'summary': 'done'});
    expect(result.kind, OutcomeKind.shared);
    expect(result.verdictFor('p1').headline, 'You win!');
  });

  test('a phone with no id yet is not told it lost', () {
    // Before the welcome lands there is nobody to be a winner or a loser.
    final result = resultFor(const GameOutcome.contest(winners: {'p1'}));
    expect(result.verdictFor(null).headline, 'Round over');
  });
}
