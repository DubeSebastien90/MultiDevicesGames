import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:multiscreen_slingshot/sdk/net/composite_discovery.dart';
import 'package:multiscreen_slingshot/sdk/net/discovery.dart';
import 'package:multiscreen_slingshot/sdk/net/discovery_stack.dart';
import 'package:multiscreen_slingshot/sdk/net/udp_discovery.dart';

/// The parts of the two-transport setup that can be tested without a network
/// or a platform channel: the TXT codec, and the merge.
///
/// The Bonjour classes themselves are not here. They are a thin shell over
/// `bonsoir`'s platform channels, so a unit test of them would be a test of a
/// mock — the parts worth asserting were deliberately pulled out into
/// [GameBeacon.tryFromAttributes] and [CompositeGameFinder], which are plain
/// Dart. What is left needs a device, and belongs in `integration_test`.
void main() {
  group('TXT attributes', () {
    Map<String, String> attributesFor(GameBeacon beacon) => {
          'app': kBeaconMagic,
          'id': beacon.id,
          'name': beacon.name,
          'ws': beacon.uri.toString(),
          'players': '${beacon.players}',
          'open': beacon.open ? '1' : '0',
          if (beacon.rejoinable.isNotEmpty)
            'rejoin': beacon.rejoinable.join(','),
        };

    test('a beacon survives the round trip through a TXT record', () {
      final original = GameBeacon(
        id: 'abc-123',
        name: "SpicyYak's board",
        uri: Uri.parse('ws://192.168.1.42:8080'),
        players: 4,
        open: true,
        rejoinable: const ['deadbeef', '0badf00d'],
        seenAt: DateTime.now(),
      );

      final parsed = GameBeacon.tryFromAttributes(attributesFor(original))!;

      expect(parsed.id, original.id);
      expect(parsed.name, original.name);
      expect(parsed.uri, original.uri);
      expect(parsed.players, original.players);
      expect(parsed.open, isTrue);
      expect(parsed.rejoinable, original.rejoinable);
    });

    test('a closed game reads as closed, and only an explicit 0 closes one', () {
      final base = {
        'app': kBeaconMagic,
        'id': 'x',
        'ws': 'ws://10.0.0.2:80',
        'name': 'g',
      };
      expect(GameBeacon.tryFromAttributes({...base, 'open': '0'})!.open, isFalse);
      expect(GameBeacon.tryFromAttributes({...base, 'open': '1'})!.open, isTrue);
      // Absent matches the datagram default rather than guessing closed.
      expect(GameBeacon.tryFromAttributes(base)!.open, isTrue);
    });

    test('the same guards apply as to a datagram', () {
      final base = {
        'app': kBeaconMagic,
        'id': 'x',
        'ws': 'ws://10.0.0.2:80',
        'name': 'g',
      };

      // Wrong app, unusable address, missing id: all rejected.
      expect(GameBeacon.tryFromAttributes({...base, 'app': 'other'}), isNull);
      expect(GameBeacon.tryFromAttributes({...base, 'ws': 'nope'}), isNull);
      expect(GameBeacon.tryFromAttributes({...base, 'id': ''}), isNull);

      // A hostile name cannot draw newlines into the list.
      final noisy =
          GameBeacon.tryFromAttributes({...base, 'name': 'a\nb\tc'})!;
      expect(noisy.name, isNot(contains('\n')));

      // Junk seats are filtered to plain hex, exactly as over UDP.
      final seats = GameBeacon.tryFromAttributes(
        {...base, 'rejoin': 'deadbeef,NOT-HEX,0badf00d'},
      )!;
      expect(seats.rejoinable, ['deadbeef', '0badf00d']);

      // A non-numeric player count does not throw, it reads as zero.
      expect(
        GameBeacon.tryFromAttributes({...base, 'players': 'lots'})!.players,
        0,
      );
    });

    test('a TXT beacon and a datagram beacon agree', () {
      final attributes = {
        'app': kBeaconMagic,
        'id': 'same',
        'name': 'Same Game',
        'ws': 'ws://192.168.0.5:9000',
        'players': '3',
        'open': '1',
        'rejoin': 'aaaaaaaa',
      };
      final viaTxt = GameBeacon.tryFromAttributes(attributes)!;
      final viaUdp = GameBeacon.tryParse(
        utf8.encode(jsonEncode({
          'app': kBeaconMagic,
          'id': 'same',
          'name': 'Same Game',
          'ws': 'ws://192.168.0.5:9000',
          'players': 3,
          'open': true,
          'rejoin': ['aaaaaaaa'],
        })),
      )!;

      expect(viaTxt.id, viaUdp.id);
      expect(viaTxt.name, viaUdp.name);
      expect(viaTxt.uri, viaUdp.uri);
      expect(viaTxt.players, viaUdp.players);
      expect(viaTxt.open, viaUdp.open);
      expect(viaTxt.rejoinable, viaUdp.rejoinable);
    });
  });

  group('CompositeGameFinder', () {
    GameBeacon beacon(String id, {int players = 0, DateTime? at}) => GameBeacon(
          id: id,
          name: id,
          uri: Uri.parse('ws://10.0.0.1:80'),
          players: players,
          open: true,
          seenAt: at ?? DateTime(2026),
        );

    test('the same game heard twice is listed once', () {
      final a = _FakeFinder()..heard = [beacon('one'), beacon('two')];
      final b = _FakeFinder()..heard = [beacon('one')];
      final composite = CompositeGameFinder([a, b]);

      expect(composite.games.map((g) => g.id), unorderedEquals(['one', 'two']));
    });

    test('the freshest sighting wins', () {
      // The Bonjour advertiser lets a stale player count ride rather than
      // republish for it, so its copy is routinely the older one.
      final stale = _FakeFinder()
        ..heard = [beacon('one', players: 1, at: DateTime(2026, 1, 1))];
      final fresh = _FakeFinder()
        ..heard = [beacon('one', players: 5, at: DateTime(2026, 1, 2))];

      expect(CompositeGameFinder([stale, fresh]).games.single.players, 5);
      // Order of sources must not decide it.
      expect(CompositeGameFinder([fresh, stale]).games.single.players, 5);
    });

    test('one working transport means discovery has not failed', () {
      final broken = _FakeFinder()..failure = 'no multicast entitlement';
      final working = _FakeFinder()..heard = [beacon('one')];

      // This is the iPhone case exactly: UDP always fails there, and saying
      // "cannot search this network" would point people at a QR code they do
      // not need.
      expect(CompositeGameFinder([broken, working]).failure, isNull);
    });

    test('every transport failing is a real failure', () {
      final a = _FakeFinder()..failure = 'one';
      final b = _FakeFinder()..failure = 'two';
      expect(CompositeGameFinder([a, b]).failure, contains('one'));
      expect(CompositeGameFinder([a, b]).failure, contains('two'));
    });

    test('a source that notices something repaints the sheet', () {
      final a = _FakeFinder();
      final composite = CompositeGameFinder([a]);
      var repaints = 0;
      composite.addListener(() => repaints++);

      a
        ..heard = [beacon('one')]
        ..announce();

      expect(repaints, 1);
    });

    test('refresh reaches every source, and disposal detaches', () {
      final a = _FakeFinder();
      final b = _FakeFinder();
      final composite = CompositeGameFinder([a, b])..refresh();

      expect(a.refreshes, 1);
      expect(b.refreshes, 1);

      composite.dispose();
      expect(a.disposed, isTrue);
      expect(b.disposed, isTrue);
    });
  });

  group('which transports run where', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('phones get Bonjour, so an iPhone and an Android can meet', () {
      // iOS because broadcast is refused there; Android because Bonjour is the
      // only thing an iPhone can hear, so without it a mixed table never finds
      // itself.
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.android,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(bonjourWorthRunning, isTrue, reason: '$platform');
        expect(createGameFinder(), isA<CompositeGameFinder>());
      }
    });

    test('desktop stays on UDP alone', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(bonjourWorthRunning, isFalse, reason: '$platform');
        expect(createGameFinder(), isA<UdpGameFinder>());
      }
    });
  });
}

class _FakeFinder extends GameFinder {
  List<GameBeacon> heard = const [];
  String? failure_;
  int refreshes = 0;
  bool disposed = false;

  set failure(String? value) => failure_ = value;

  @override
  String? get failure => failure_;

  @override
  List<GameBeacon> get games => heard;

  @override
  Future<void> start() async {}

  @override
  void refresh() => refreshes++;

  void announce() => notifyListeners();

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
