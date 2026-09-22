import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/host/host_session.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/sdk/net/websocket_transport.dart';

/// Colour is identity here, and identity has to be unique — so the interesting
/// cases are all about two phones wanting the same one.
///
/// Driven through the real host and real transports, because the uniqueness
/// promise is made by the *host*, and a unit test of the palette alone would
/// prove nothing about the promise that matters.
DeviceMetrics portraitPhone(String label) => DeviceMetrics(
  activePxWidth: 1080,
  activePxHeight: 2400,
  widthMm: 68.58,
  heightMm: 152.4,
  bezelMm: 3,
  devicePixelRatio: 3,
  label: label,
);

Future<void> waitFor(
  String what,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for: $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('the palette', () {
    test('every colour is distinct in id, name and value', () {
      final ids = {for (final c in PlayerPalette.all) c.id};
      final names = {for (final c in PlayerPalette.all) c.name};
      final values = {for (final c in PlayerPalette.all) c.value.toARGB32()};

      expect(ids, hasLength(PlayerPalette.all.length));
      expect(names, hasLength(PlayerPalette.all.length));
      expect(values, hasLength(PlayerPalette.all.length));
    });

    test('ids are looked up, and nonsense resolves to nothing', () {
      expect(PlayerPalette.byId('green'), PlayerPalette.green);
      expect(PlayerPalette.byId('chartreuse'), isNull);
      expect(PlayerPalette.byId(null), isNull);
    });

    test('the away grey is never a seat', () {
      expect(PlayerPalette.all, isNot(contains(PlayerPalette.away)));
      expect(PlayerPalette.byId(PlayerPalette.away.id), isNull);
      expect(
        PlayerPalette.firstFree([for (final c in PlayerPalette.all) c.id]),
        isNull,
      );
    });

    test('firstFree skips what is taken and runs out honestly', () {
      expect(PlayerPalette.firstFree([]), PlayerPalette.all.first);
      expect(
        PlayerPalette.firstFree([PlayerPalette.all.first.id]),
        PlayerPalette.all[1],
      );
      expect(
        PlayerPalette.firstFree([for (final c in PlayerPalette.all) c.id]),
        isNull,
        reason: 'an exhausted palette must say so rather than repeat itself',
      );
    });
  });

  group('the host hands colours out', () {
    late HostSession host;
    late LoopbackPair loopback;
    late ClientSession phone1;
    late ClientSession phone2;

    setUp(() async {
      host = HostSession(name: 'colour board', advertise: false);
      final address = await host.start();

      loopback = LoopbackPair();
      phone1 = ClientSession(
        transport: loopback.transport,
        metrics: portraitPhone('host phone'),
      );
      await phone1.connect();
      host.addLocalPeer(loopback.peer);

      phone2 = ClientSession(
        transport: WebSocketTransport(address.replace(host: '127.0.0.1')),
        metrics: portraitPhone('joined phone'),
        joinCode: host.joinCode,
      );
      await phone2.connect();

      await waitFor('both phones in', () => host.phones.length == 2);
    });

    tearDown(() async {
      phone1.dispose();
      phone2.dispose();
      host.dispose();
      await loopback.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('everyone is seated on arrival, distinctly', () async {
      await waitFor('both seated', () =>
          host.phones.every((p) => p.color != null));

      final colors = {for (final p in host.phones) p.color!.id};
      expect(colors, hasLength(2),
          reason: 'two phones must never share a colour');
    });

    test('a phone can change colour, and both phones hear about it', () async {
      await waitFor('both seated', () =>
          host.phones.every((p) => p.color != null));

      // Something nobody has.
      final free = PlayerPalette.firstFree(
        [for (final p in host.phones) p.color!.id],
      )!;

      phone2.pickColor(free);

      await waitFor('phone2 wears the new colour',
          () => phone2.myColor?.id == free.id);

      // And the other phone sees it too — the lobby broadcast is the single
      // source of truth about who is what.
      await waitFor(
        'phone1 was told',
        () => phone1.takenColorIds.contains(free.id),
      );
    });

    test('the second phone to want a colour does not get it', () async {
      await waitFor('both seated', () =>
          host.phones.every((p) => p.color != null));

      final contested = host.phones.first.color!;
      final loserBefore = host.phones[1].color!;

      // phone2 asks for the colour phone1 already wears.
      phone2.pickColor(contested);

      // Give the request a generous window to be wrong in.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(host.phones.first.color!.id, contested.id,
          reason: 'the holder keeps it');
      expect(host.phones[1].color!.id, loserBefore.id,
          reason: 'the asker keeps what it had rather than losing its seat');

      final colors = {for (final p in host.phones) p.color!.id};
      expect(colors, hasLength(2), reason: 'still no duplicates');
    });

    test('asking for your own colour again changes nothing', () async {
      await waitFor('both seated', () =>
          host.phones.every((p) => p.color != null));

      final mine = host.phones[1].color!;
      phone2.pickColor(mine);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(host.phones[1].color!.id, mine.id);
      final colors = {for (final p in host.phones) p.color!.id};
      expect(colors, hasLength(2));
    });

    test('colour reaches the game as part of the board', () async {
      await waitFor('both calibrated', () =>
          host.phones.every((p) => p.calibrated && p.color != null));

      host.startRound();

      await waitFor('placed', () => phone1.slices.isNotEmpty);

      // The slices a sim scores against carry the colours, so a game never has
      // to ask the lobby anything.
      for (final slice in phone1.slices) {
        final record =
            host.phones.firstWhere((p) => p.phoneId == slice.phoneId);
        expect(slice.color?.id, record.color?.id);
      }
    });
  });

  group('a colour belongs to somebody who is here', () {
    late HostSession host;
    late Uri address;
    final phones = <ClientSession>[];

    setUp(() async {
      host = HostSession(name: 'colour board', advertise: false);
      address = (await host.start()).replace(host: '127.0.0.1');
    });

    tearDown(() async {
      for (final p in phones) {
        p.dispose();
      }
      phones.clear();
      host.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    Future<ClientSession> join(
      String label, {
      String? deviceId,
      PlayerColor? preferred,
      void Function(PlayerColor)? onColorChosen,
    }) async {
      final phone = ClientSession(
        transport: WebSocketTransport(address),
        metrics: portraitPhone(label),
        deviceId: deviceId ?? '$label-device',
        preferredColor: preferred,
        onColorChosen: onColorChosen,
      );
      phones.add(phone);
      await phone.connect();
      await waitFor(
        '$label answered',
        () =>
            phone.phase == ClientPhase.rejected ||
            host.phones.any((p) => p.label == label && p.color != null),
      );
      return phone;
    }

    Future<void> leave(ClientSession phone) async {
      final id = phone.phoneId;
      phone.dispose();
      phones.remove(phone);
      await waitFor(
        'left',
        () => host.phones.any((p) => p.phoneId == id && !p.connected),
      );
    }

    test('dropping out in the lobby hands the colour back, not the seat',
        () async {
      final ada = await join('Ada');
      final seat = ada.phoneId!;
      final hers = host.phones.single.color!;
      host.scores.award(seat, 4);

      await leave(ada);

      final away = host.phones.single;
      expect(away.phoneId, seat, reason: 'the seat went with the colour');
      expect(away.color, isNull, reason: 'the colour is still held');
      expect(host.scores[seat], 4);

      await join('Bob');
      expect(host.phones.last.color, hers,
          reason: 'the freed colour was not offered to the next phone');
    });

    test('seven away and one here still lets a new phone in', () async {
      final everyone = [
        for (var i = 0; i < PlayerPalette.size; i++) await join('P$i'),
      ];
      for (final p in everyone.skip(1)) {
        await leave(p);
      }

      final newcomer = await join('New');
      expect(newcomer.phase, isNot(ClientPhase.rejected));
      expect(host.phones.last.color, isNotNull);
    });

    test('a ninth phone is turned away rather than seated with no colour',
        () async {
      for (var i = 0; i < PlayerPalette.size; i++) {
        await join('P$i');
      }

      final ninth = await join('Ninth');
      expect(ninth.phase, ClientPhase.rejected);
      expect(ninth.message, contains('full'));
      expect(host.phones, hasLength(PlayerPalette.size));
    });

    test('a phone sits in the colour it prefers when nobody has it', () async {
      await join('Ada', preferred: PlayerPalette.red);
      expect(host.phones.single.color, PlayerPalette.red);
    });

    test('a preferred colour already taken falls back to the first free one',
        () async {
      await join('Ada', preferred: PlayerPalette.red);
      await join('Bob', preferred: PlayerPalette.red);

      expect(host.phones.last.color, PlayerPalette.all.first);
    });

    test('coming back after the colour went sits them in their preference',
        () async {
      final ada = await join('Ada', deviceId: 'ada', preferred: PlayerPalette.red);
      final seat = ada.phoneId;
      await leave(ada);

      final again = await join('Ada', deviceId: 'ada', preferred: PlayerPalette.red);
      expect(again.phoneId, seat);
      expect(host.phones.single.color, PlayerPalette.red);
    });

    test('a pick the host confirms is remembered; a lost race is not',
        () async {
      final chosen = <PlayerColor>[];
      final ada = await join('Ada');
      final bob = await join('Bob', onColorChosen: chosen.add);

      bob.pickColor(PlayerPalette.red);
      await waitFor('confirmed', () => chosen.isNotEmpty);
      expect(chosen, [PlayerPalette.red]);

      bob.pickColor(ada.myColor!);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(chosen, [PlayerPalette.red],
          reason: 'a colour somebody else holds was remembered');
    });
  });
}
