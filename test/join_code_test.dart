import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/host/host_session.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/net/discovery.dart';
import 'package:multiscreen_slingshot/sdk/net/host_address.dart';
import 'package:multiscreen_slingshot/sdk/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/sdk/net/websocket_transport.dart';

/// The door policy: the name is public, the code is not, and only the code
/// gets you in.
DeviceMetrics phone(String label) => DeviceMetrics(
  activePxWidth: 2400,
  activePxHeight: 1080,
  widthMm: 152.4,
  heightMm: 68.58,
  bezelMm: 3,
  devicePixelRatio: 3,
  label: label,
);

Future<void> waitFor(
  String what,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late HostSession host;
  late Uri local;

  setUp(() async {
    host = HostSession(name: 'kitchen table', advertise: false);
    final address = await host.start();
    local = address.replace(host: '127.0.0.1');
  });

  tearDown(() async {
    host.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  ClientSession joiner({String? code}) => ClientSession(
    transport: WebSocketTransport(local),
    metrics: phone('joiner'),
    joinCode: code,
  );

  test('a host has a 5-digit code and a name', () {
    expect(host.joinCode, matches(RegExp(r'^\d{5}$')));
    expect(host.name, 'kitchen table');
    expect(isValidJoinCode(host.joinCode), isTrue);
  });

  test('the right code gets you in', () async {
    final client = joiner(code: host.joinCode);
    await client.connect();

    await waitFor('welcomed', () => client.phase == ClientPhase.lobby);
    expect(client.phoneId, isNotNull);
    expect(client.sessionName, 'kitchen table');
    expect(host.phones.length, 1);

    client.dispose();
  });

  test('a wrong code is turned away and never becomes a phone', () async {
    final wrong = host.joinCode == '00000' ? '11111' : '00000';
    final client = joiner(code: wrong);
    await client.connect();

    await waitFor('rejected', () => client.phase == ClientPhase.rejected);
    expect(client.message, contains('Wrong code'));
    expect(client.phoneId, isNull);
    expect(host.phones, isEmpty, reason: 'a rejected peer must not hold a slot');

    client.dispose();
  });

  test('no code at all is turned away', () async {
    final client = joiner();
    await client.connect();

    await waitFor('rejected', () => client.phase == ClientPhase.rejected);
    expect(host.phones, isEmpty);

    client.dispose();
  });

  test('a failed attempt does not burn a phone number', () async {
    final wrong = host.joinCode == '00000' ? '11111' : '00000';
    final rejected = joiner(code: wrong);
    await rejected.connect();
    await waitFor('rejected', () => rejected.phase == ClientPhase.rejected);
    rejected.dispose();

    final accepted = joiner(code: host.joinCode);
    await accepted.connect();
    await waitFor('welcomed', () => accepted.phase == ClientPhase.lobby);

    // p1, not p2: the stranger never got a number.
    expect(accepted.phoneId, 'p1');
    accepted.dispose();
  });

  test('the host own screen skips the gate', () async {
    final loopback = LoopbackPair();
    final me = ClientSession(
      transport: loopback.transport,
      metrics: phone('host screen'),
    );
    await me.connect();
    host.addLocalPeer(loopback.peer);

    await waitFor('host is in its own lobby',
        () => me.phase == ClientPhase.lobby);
    expect(host.phones.length, 1);

    me.dispose();
    await loopback.dispose();
  });

  group('the QR carries the code so a scan needs no keypad', () {
    test('address plus code', () {
      final target = parseHostTarget('ws://192.168.1.42:8080#48213');
      expect(target, isNotNull);
      expect(target!.uri.toString(), 'ws://192.168.1.42:8080');
      expect(target.code, '48213');
    });

    test('a bare typed address carries no code', () {
      final target = parseHostTarget('192.168.1.42');
      expect(target!.uri.port, kDefaultPort);
      expect(target.code, isNull);
    });

    test('a junk fragment is not mistaken for a code', () {
      expect(parseHostTarget('ws://192.168.1.42:8080#nope')!.code, isNull);
      expect(parseHostTarget('ws://192.168.1.42:8080#123')!.code, isNull);
    });

    test('nonsense is rejected outright', () {
      expect(parseHostTarget(''), isNull);
      expect(parseHostTarget('http://example.com'), isNull);
    });
  });

  group('beacons', () {
    test('round-trip through the wire format', () {
      final beacon = GameBeacon(
        id: 'abc',
        name: 'kitchen table',
        uri: Uri.parse('ws://192.168.1.42:8080'),
        players: 2,
        open: true,
        seenAt: DateTime.now(),
      );

      final parsed =
          GameBeacon.tryParse(utf8.encode(jsonEncode(beacon.toJson())));

      expect(parsed, isNotNull);
      expect(parsed!.id, 'abc');
      expect(parsed.name, 'kitchen table');
      expect(parsed.uri, Uri.parse('ws://192.168.1.42:8080'));
      expect(parsed.players, 2);
      expect(parsed.open, isTrue);
    });

    test('a beacon never carries the join code', () {
      final host2 = HostSession(name: 'x', advertise: false);
      final json = jsonEncode(GameBeacon(
        id: 'abc',
        name: host2.name,
        uri: Uri.parse('ws://192.168.1.42:8080'),
        players: 1,
        open: true,
        seenAt: DateTime.now(),
      ).toJson());
      expect(json, isNot(contains(host2.joinCode)));
      host2.dispose();
    });

    test('a hostile name cannot draw newlines into the list', () {
      final parsed = GameBeacon.tryParse(
        '{"app":"mss1","id":"x","name":"evil\\nlist\\ninjection",'
                '"ws":"ws://10.0.0.1:8080","players":1,"open":true}'
            .codeUnits,
      );
      expect(parsed!.name, 'evil list injection');
    });

    test('junk on the port is ignored', () {
      expect(GameBeacon.tryParse('hello'.codeUnits), isNull);
      expect(GameBeacon.tryParse('{"app":"other"}'.codeUnits), isNull);
      expect(
        GameBeacon.tryParse('{"app":"mss1","id":"x","ws":"nope"}'.codeUnits),
        isNull,
      );
    });
  });
}
