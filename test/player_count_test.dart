import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/catalog.dart';
import 'package:multiscreen_slingshot/sdk/contract/player_count.dart';

/// How a game says what table it needs, and how the lobby decides what can be
/// played on the table it has.
void main() {
  group('a range', () {
    test('accepts its endpoints and nothing outside them', () {
      const three = PlayerCount.range(min: 3, max: 5);
      expect(three.playableCounts(), [3, 4, 5]);
      expect(three.fits(2), isFalse);
      expect(three.fits(6), isFalse);
      expect(three.smallest, 3);
      expect(three.largest, 5);
    });

    test('an open top end reads as "or more"', () {
      const open = PlayerCount.range(min: 3);
      expect(open.fits(8), isTrue);
      expect(open.describe(), 'needs 3+ phones');
    });

    test('a closed one names both ends', () {
      const closed = PlayerCount.range(min: 2, max: 4);
      expect(closed.describe(), 'needs 2–4 phones');
    });
  });

  group('parity', () {
    test('even rules out the odd counts inside the range', () {
      const teams = PlayerCount.range(
        min: 2,
        max: 8,
        parity: CountParity.even,
      );
      expect(teams.playableCounts(), [2, 4, 6, 8]);
      expect(teams.fits(3), isFalse);
      expect(teams.describe(), contains('an even number of'));
    });

    test('odd works the same way round', () {
      const oddOneOut = PlayerCount.range(
        min: 3,
        max: 7,
        parity: CountParity.odd,
      );
      expect(oddOneOut.playableCounts(), [3, 5, 7]);
      expect(oddOneOut.fits(4), isFalse);
    });

    test('it moves the real floor, not just the filter', () {
      // Stated minimum 2, but an odd game cannot be played by two.
      const odd = PlayerCount.range(min: 2, max: 9, parity: CountParity.odd);
      expect(odd.smallest, 3);
      expect(odd.largest, 9);
      expect(odd.describe(), 'needs an odd number of phones, 3 to 9');
    });
  });

  group('an explicit list', () {
    test('is the whole answer, ignoring any notion of a span', () {
      const odd = PlayerCount.anyOf([3, 5, 9]);
      expect(odd.playableCounts(ceiling: 12), [3, 5, 9]);
      expect(odd.fits(4), isFalse);
      expect(odd.fits(7), isFalse, reason: 'not a range — 7 is not listed');
      expect(odd.smallest, 3);
      expect(odd.largest, 9);
    });

    test('reads as a list', () {
      expect(
        const PlayerCount.anyOf([2, 4, 6]).describe(),
        'needs 2, 4 or 6 phones',
      );
      expect(
        const PlayerCount.anyOf([4]).describe(),
        'needs exactly 4 phones',
      );
    });
  });

  group('exactly', () {
    test('is a range of one', () {
      const duel = PlayerCount.exactly(2);
      expect(duel.playableCounts(), [2]);
      expect(duel.describe(), 'needs exactly 2 phones');
    });
  });

  group('the lobby decides from these', () {
    test('every shipped game declares a table it can be played on', () {
      for (final game in GameCatalog.playlist) {
        final counts = game.manifest.players.playableCounts();
        expect(counts, isNotEmpty,
            reason: '${game.manifest.title} can never be played');
        expect(game.manifest.requirement(), isNotEmpty);
      }
    });

    test('a game is only offered at a size it accepts', () {
      for (final game in GameCatalog.playlist) {
        for (var n = 1; n <= 8; n++) {
          final offered = GameCatalog.playableFrom(0, n);
          if (offered?.manifest.id == game.manifest.id) {
            expect(game.manifest.fits(n), isTrue);
          }
        }
      }
    });

    test('one phone plays nothing, and the walk says so plainly', () {
      // Every game needs two. A lone phone is not a table, and the walk
      // returns null rather than something it cannot lay out.
      expect(GameCatalog.anyPlayable(1), isFalse);
      expect(GameCatalog.playableFrom(0, 1), isNull);
    });

    test('two phones are the smallest real table', () {
      expect(GameCatalog.anyPlayable(2), isTrue);
      expect(GameCatalog.playableFrom(0, 2), isNotNull);
    });

    test('three phones unlock Hot Potato', () {
      expect(const _Ids().of(3), contains('hotpotato'));
      expect(const _Ids().of(2), isNot(contains('hotpotato')));
    });

    test('the summary leads with the game closest to playable', () {
      final summary = GameCatalog.requirementSummary();
      final nearestAt = summary.indexOf('Flood');
      final potatoAt = summary.indexOf('Hot Potato');
      expect(nearestAt, greaterThanOrEqualTo(0));
      expect(potatoAt, greaterThan(nearestAt),
          reason: 'a short-handed table should hear the nearest option first');
    });

    test('playableTableSizes reports every size that plays something', () {
      final sizes = GameCatalog.playableTableSizes();
      expect(sizes, isNot(contains(1)), reason: 'one phone plays nothing');
      expect(sizes, contains(2));
      expect(sizes, contains(3));
      for (final n in sizes) {
        expect(GameCatalog.anyPlayable(n), isTrue);
      }
    });
  });

  group('supportsIpad', () {
    test('defaults to false, and is not yet enforced anywhere', () {
      // None of the three has been tried on a tablet, so none of them claims
      // it. Support is opted into deliberately rather than inherited by
      // silence.
      for (final game in GameCatalog.playlist) {
        expect(game.manifest.supportsIpad, isFalse);
      }

      // Deliberately no filtering assertion: nothing reads the field yet, so a
      // table with an iPad in it is still offered every game. This test exists
      // to make that state explicit rather than let it look like an oversight.
      expect(GameCatalog.anyPlayable(3), isTrue);
    });
  });
}

/// Which games a table of [n] could play.
class _Ids {
  const _Ids();
  List<String> of(int n) => [
    for (final g in GameCatalog.playlist)
      if (g.manifest.fits(n)) g.manifest.id,
  ];
}
