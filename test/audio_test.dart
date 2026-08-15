import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/audio/audio_engine.dart';
import 'package:multiscreen_slingshot/sdk/audio/audio_output.dart';
import 'package:multiscreen_slingshot/sdk/audio/game_audio.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/model/player.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/model/coverage_map.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/model/phone_layout.dart';
import 'package:multiscreen_slingshot/sdk/model/world_rect.dart';
import 'package:multiscreen_slingshot/sdk/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/sdk/net/protocol.dart';

/// Audio is the one part of player identity that adds anything to the wire, and
/// almost everything worth testing about it is *timing* and *lifetime* — when a
/// cue fires, and when it stops. Neither needs a speaker, which is why the
/// output is a seam.
///
/// There is not a sound file in the project, so cues here are made with
/// [SoundCue.asset] to stand in for one that exists.
const green = Player(phoneId: 'p1', color: PlayerPalette.green);
const orange = Player(phoneId: 'p2', color: PlayerPalette.orange);

const bang = SoundCue.asset('assets/test/bang.mp3');
const theme = SoundCue.asset('assets/test/theme.mp3');

/// What the host would send for a queued command, stamped at [atMs].
List<Map<String, dynamic>> wire(RoundAudio audio, double atMs) => [
  for (final c in audio.drain()) {'type': HostMsg.sound, ...c.toJson(atMs)},
];

/// Let the loopback's queued messages reach the session.
Future<void> pumpEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  // The session preloads player art when a layout arrives, which needs the
  // asset bundle. Without this the decode fails harmlessly and logs a wall of
  // binding advice over the test output.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the emitter', () {
    test('queues rather than plays, so a step stays replayable', () {
      final audio = RoundAudio();
      audio.playGeneral(bang);
      expect(audio.hasPending, isTrue);
      expect(audio.drain(), hasLength(1));
      expect(audio.hasPending, isFalse, reason: 'drain did not empty it');
    });

    test('mints handles from a counter, never a clock', () {
      // The one rule the whole engine rests on: a step must be pure with
      // respect to wall-clock time. Two runs of the same sequence must produce
      // the same handles.
      List<int> handles() {
        final audio = RoundAudio();
        return [
          audio.playGeneral(bang).id,
          audio.playOnPhone(green, bang).id,
          audio.playGeneral(theme, loop: true).id,
        ];
      }

      expect(handles(), handles());
      expect(handles(), [1, 2, 3]);
    });

    test('routes a general cue to nobody in particular and a targeted one to '
        'its phone', () {
      final audio = RoundAudio();
      audio.playGeneral(bang);
      audio.playOnPhone(orange, bang);

      final sent = wire(audio, 500);
      expect(sent[0]['phoneId'], isNull, reason: 'general is the host\'s');
      expect(sent[1]['phoneId'], 'p2');
      expect(sent.every((m) => m['at'] == 500), isTrue);
    });

    test('a stop follows its handle to the phone that holds it', () {
      // The stop is decided by the rules, on the host, but the sound is being
      // made somewhere else. Sending it to the host would leave the sound
      // playing on the far side of the table.
      final audio = RoundAudio();
      final onPhone = audio.playOnPhone(orange, theme, loop: true);
      final onTable = audio.playGeneral(theme, loop: true);
      audio.drain();

      audio.stopSound(onPhone);
      audio.stopSound(onTable);
      final sent = wire(audio, 100);

      expect(sent[0]['phoneId'], 'p2');
      expect(sent[1]['phoneId'], isNull);
      expect(sent.every((m) => m['op'] == AudioOp.stop), isTrue);
    });

    test('the end of a round is the one thing every phone is told', () {
      final audio = RoundAudio()..stopRoundSounds();
      final commands = audio.drain();

      expect(commands.single.isBroadcast, isTrue);
      // Everything else goes to exactly one device.
      final targeted = RoundAudio()..playOnPhone(green, bang);
      expect(targeted.drain().single.isBroadcast, isFalse);
    });

    test('a cue with no recording is a silence with a handle', () {
      final audio = RoundAudio();
      // Every cue in the SDK library is in this state today.
      final handle = audio.playGeneral(const SoundCue('unrecorded'));

      expect(handle, SoundHandle.none);
      expect(audio.hasPending, isFalse, reason: 'nothing to send');
      // Storing and stopping it must still be safe — a game does not get to
      // care which half of the library has been recorded.
      audio.stopSound(handle);
      expect(audio.hasPending, isFalse);
    });
  });

  group('a phone', () {
    late SilentAudioOutput out;
    late AudioEngine engine;

    setUp(() {
      out = SilentAudioOutput(keepLog: true);
      engine = AudioEngine(output: out);
    });

    void deliver(RoundAudio audio, double atMs) {
      for (final msg in wire(audio, atMs)) {
        engine.receive(msg);
      }
    }

    test('waits for the instant instead of playing on arrival', () {
      final audio = RoundAudio()..playGeneral(bang);
      deliver(audio, 1000);

      // The packet has landed, but this phone's delayed clock has not reached
      // the moment the sound belongs to. Playing now would put it ahead of the
      // picture that explains it.
      engine.pump(900);
      expect(out.playing, isEmpty);

      engine.pump(1000);
      expect(out.playing, hasLength(1));
    });

    test('drops a cue whose moment has long gone', () {
      // A phone that reconnects gets a burst of cues from the past. Firing
      // them replays a minute of the round into somebody's ear at once.
      final audio = RoundAudio()..playGeneral(bang);
      deliver(audio, 1000);

      engine.pump(1000 + AudioEngine.staleMs + 1);
      expect(out.playing, isEmpty);
      expect(out.log, isEmpty);
    });

    test('a stop cancels a cue that has not started yet', () {
      final audio = RoundAudio();
      final handle = audio.playGeneral(bang);
      audio.stopSound(handle);
      // Both are queued before the clock has reached either of them, which is
      // ordinary: the timeline runs 80ms behind.
      deliver(audio, 1000);

      engine.pump(2000);
      expect(out.playing, isEmpty, reason: 'a cancelled cue still fired');
    });

    test('stopping something already finished is not an error', () {
      final audio = RoundAudio();
      final handle = audio.playGeneral(bang);
      deliver(audio, 0);
      engine.pump(0);

      audio.stopSound(handle);
      deliver(audio, 10);
      audio.stopSound(handle);
      deliver(audio, 20);

      expect(out.playing, isEmpty);
    });

    test('mute silences without pretending the sound is playing', () {
      engine.muted = true;
      final audio = RoundAudio()..playGeneral(bang);
      deliver(audio, 0);
      engine.pump(0);

      expect(out.playing, isEmpty);
    });

    test('caps simultaneous one-shots but never culls music', () {
      final audio = RoundAudio();
      audio.playGeneral(theme, loop: true);
      for (var i = 0; i < AudioEngine.maxVoices + 5; i++) {
        audio.playGeneral(bang);
      }
      deliver(audio, 0);
      engine.pump(0);

      expect(out.playing, hasLength(AudioEngine.maxVoices + 1));
    });
  });

  group('a round ending', () {
    test('silences what it started and lets a persistent sound play on', () {
      final out = SilentAudioOutput(keepLog: true);
      final engine = AudioEngine(output: out);
      final audio = RoundAudio();

      final bed = audio.playGeneral(theme, loop: true, persist: true);
      final effect = audio.playGeneral(bang);
      for (final msg in wire(audio, 0)) {
        engine.receive(msg);
      }
      engine.pump(0);
      expect(out.playing, hasLength(2));

      // What the platform sends at every teardown, so a game never has to
      // remember and an abandoned round still goes quiet.
      audio.stopRoundSounds();
      for (final msg in wire(audio, 10)) {
        engine.receive(msg);
      }

      expect(out.playing, {bed.id});
      expect(out.playing.contains(effect.id), isFalse);
    });

    test('a cue queued but not yet heard dies with the round', () {
      final out = SilentAudioOutput(keepLog: true);
      final engine = AudioEngine(output: out);
      final audio = RoundAudio()..playGeneral(bang);
      for (final msg in wire(audio, 5000)) {
        engine.receive(msg);
      }

      audio.stopRoundSounds();
      for (final msg in wire(audio, 5001)) {
        engine.receive(msg);
      }

      engine.pump(5000);
      expect(out.playing, isEmpty);
    });
  });

  group('the platform speaking for a player', () {
    // Two moments the SDK owns rather than any game: saying 'I am ready', and
    // being told how a round went. Both play on the phone in that person's
    // hand, in their own character's voice.
    late SilentAudioOutput out;
    late ClientSession client;
    late LoopbackPair pair;

    setUp(() async {
      pair = LoopbackPair();
      out = SilentAudioOutput(keepLog: true);
      client = ClientSession(
        transport: pair.transport,
        metrics: DeviceMetrics(
          activePxWidth: 1080,
          activePxHeight: 2400,
          widthMm: 68.58,
          heightMm: 152.4,
          bezelMm: 3,
          devicePixelRatio: 3,
          label: 'test phone',
        ),
        audioOutput: out,
      );
      await client.connect();
    });

    tearDown(() async {
      client.dispose();
      await pair.dispose();
    });

    /// Put this phone in a round as [color], the way the host does.
    ///
    /// Built from the real `toJson` rather than a hand-written map: the layout
    /// message has a shape, and a test that invents its own is testing a
    /// format nothing else uses.
    void seat(PlayerColor color) {
      const board = WorldRect(0, 0, 30, 10);
      pair.peer.send({'type': HostMsg.welcome, 'phoneId': 'p1'});
      pair.peer.send({
        'type': HostMsg.layout,
        ...const PhoneLayout(
          phoneId: 'p1',
          index: 0,
          total: 1,
          worldCenterX: 5,
          worldCenterY: 5,
          mmToWorld: 0.1,
          dpi: 400,
          devicePixelRatio: 3,
          activePxWidth: 1080,
          activePxHeight: 2400,
          board: board,
          placement: '',
        ).toJson(),
        'coverage':
            const CoverageMap(screens: [], board: board).toJson(),
        'slices': [
          PhoneSlice(
            'p1',
            const ScreenRect(
              centerX: 5,
              centerY: 5,
              width: 6,
              height: 13,
              turnRadians: 0,
            ),
            label: 'test phone',
            color: color,
          ).toJson(),
        ],
      });
    }

    test('a player who says they are ready hears their own voice', () async {
      seat(PlayerPalette.purple);
      await pumpEvents();
      expect(client.me?.color.id, 'purple');

      client.confirmPlacement();
      expect(out.log, ['play -2 assets/sdk/players/purple-happy.wav']);
    });

    test('a phone with no seat yet stays quiet', () async {
      // Before the board is compiled there is nobody to speak for. Confirming
      // still has to work — the sound is decoration, not the message.
      client.confirmPlacement();
      expect(out.log, isEmpty);
    });

    test('winning sounds happy and losing sounds sad, per phone', () async {
      seat(PlayerPalette.red);
      await pumpEvents();

      pair.peer.send({
        'type': HostMsg.outcome,
        'kind': 'contest',
        'won': true,
        'winners': ['p1'],
      });
      await pumpEvents();
      expect(out.log.single, endsWith('red-happy.wav'));

      out.clearLog();
      pair.peer.send({
        'type': HostMsg.outcome,
        'kind': 'contest',
        'won': true,
        'winners': ['p2'],
      });
      await pumpEvents();
      expect(out.log.single, endsWith('red-sad.wav'));
    });

    test('a round nobody wins is well played, on every phone', () async {
      // `personal` is the score-attack ending: no winning, just facts. Every
      // phone celebrates, because nobody lost.
      seat(PlayerPalette.blue);
      await pumpEvents();

      pair.peer.send({
        'type': HostMsg.outcome,
        'kind': 'personal',
        'won': true,
        'lines': {'p1': 'You made 320 points'},
      });
      await pumpEvents();
      expect(out.log.single, endsWith('blue-happy.wav'));
    });

    test('a draw is silence', () async {
      // Nobody won and nobody lost. A sad voice here would be telling somebody
      // they lost a round that nothing lost.
      seat(PlayerPalette.green);
      await pumpEvents();

      pair.peer.send({'type': HostMsg.outcome, 'kind': 'draw', 'won': false});
      await pumpEvents();
      expect(out.log, isEmpty);
    });
  });

  group('a view', () {
    test('plays on its own phone without waiting for the timeline', () {
      // Local decoration: a tick under a finger on this phone's own glass has
      // no shared instant to agree with.
      final out = SilentAudioOutput(keepLog: true);
      final engine = AudioEngine(output: out);

      final handle = engine.play(bang);
      expect(out.playing, hasLength(1));

      // Local handles are negative, so they can never collide with the host's,
      // which count up from one.
      expect(handle.id, lessThan(0));

      engine.stopSound(handle);
      expect(out.playing, isEmpty);
    });
  });
}
