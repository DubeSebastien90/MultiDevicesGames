import 'dart:convert';

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
import 'package:multiscreen_slingshot/sdk/audio/tone.dart';
import 'package:multiscreen_slingshot/sdk/audio/tone_output.dart';

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

/// A silent output that can also say when a sound ended.
///
/// The plain [SilentAudioOutput] never reports a finish, because silence has no
/// duration — which is right for it and useless for testing the voice cap, the
/// one rule that depends on sounds ending.
class EndingOutput extends SilentAudioOutput {
  EndingOutput() : super(keepLog: true);

  void Function(int handleId)? _onFinished;

  @override
  set onFinished(void Function(int handleId)? callback) =>
      _onFinished = callback;

  /// Play [handleId] to its end, as a real speaker eventually does.
  void finish(int handleId) {
    stop(handleId);
    _onFinished?.call(handleId);
  }
}

/// Let the loopback's queued messages reach the session.
Future<void> pumpEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  // The session preloads player art when a layout arrives, which needs the
  // asset bundle. Without this the decode fails harmlessly and logs a wall of
  // binding advice over the test output.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the emitter', () {
    test('a fade in goes on the wire, and only when asked for', () {
      final audio = RoundAudio();
      audio.playOnPhone(green, bang, fadeIn: const Duration(milliseconds: 250));
      audio.playOnPhone(green, bang);
      final sent = wire(audio, 0);
      expect(sent[0]['fadeIn'], 250);
      expect(sent[1].containsKey('fadeIn'), isFalse);
    });

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

    // At the ceiling the two kinds of sound are treated oppositely, and both
    // halves are worth pinning down: a round's cue is one of many and waits
    // its turn, while a sound answering a finger on this glass must be heard
    // or the app looks broken.
    test('a finger on the glass steals the oldest voice', () {
      final out = SilentAudioOutput(keepLog: true);
      final engine = AudioEngine(output: out);

      final audio = RoundAudio();
      for (var i = 0; i < AudioEngine.maxVoices; i++) {
        audio.playGeneral(bang);
      }
      for (final msg in wire(audio, 0)) {
        engine.receive(msg);
      }
      engine.pump(0);
      expect(out.playing, hasLength(AudioEngine.maxVoices));

      // The one that started first, which is the one nearest its end.
      final oldest = out.playing.first;

      engine.play(bang);

      expect(
        out.playing,
        hasLength(AudioEngine.maxVoices),
        reason: 'the room is the same size either way',
      );
      expect(
        out.playing.contains(oldest),
        isFalse,
        reason: 'the local sound should have taken the oldest seat',
      );
      expect(
        out.log.where((l) => l.startsWith('stop')),
        hasLength(1),
        reason: 'exactly one voice was given up for it',
      );
    });

    test('but a cue from the host waits its turn', () {
      final out = SilentAudioOutput(keepLog: true);
      final engine = AudioEngine(output: out);

      final audio = RoundAudio();
      for (var i = 0; i < AudioEngine.maxVoices + 3; i++) {
        audio.playGeneral(bang);
      }
      for (final msg in wire(audio, 0)) {
        engine.receive(msg);
      }
      engine.pump(0);

      // Dropped, not swapped in: cutting one of seven sounds a player is
      // already hearing to make room for an eighth trades nothing for nothing.
      expect(out.playing, hasLength(AudioEngine.maxVoices));
      expect(out.log.where((l) => l.startsWith('stop')), isEmpty);
    });

    // The cap counts *simultaneous* voices, which is only true if a voice is
    // given back when its sound ends. It was not: the engine held every handle
    // until the round cleared them, so the ninth one-shot of a round — and
    // every one after it — was dropped in silence. Nothing on the placement
    // screen ends a round, so the easter egg there simply went quiet after
    // eight pokes.
    test('a one-shot that ends gives its voice back', () {
      final out = EndingOutput();
      final engine = AudioEngine(output: out);

      // One emitter throughout: handles come from its counter, and a fresh
      // emitter per cue would mint the same handle every time and stand in for
      // one sound played nine times.
      final audio = RoundAudio();
      void play() {
        audio.playGeneral(bang);
        for (final msg in wire(audio, 0)) {
          engine.receive(msg);
        }
        engine.pump(0);
      }

      for (var i = 0; i < AudioEngine.maxVoices; i++) {
        play();
      }
      expect(out.playing, hasLength(AudioEngine.maxVoices));

      // Full: while they are all still sounding, the next one is dropped.
      play();
      expect(out.playing, hasLength(AudioEngine.maxVoices));

      // They finish, as sounds do.
      for (final id in out.playing.toList()) {
        out.finish(id);
      }
      expect(out.playing, isEmpty);

      play();
      expect(out.playing, hasLength(1), reason: 'the cap never let go');
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
        'coverage': const CoverageMap(screens: [], board: board).toJson(),
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

    test('picking a character plays its happy voice, on this phone', () {
      client.pickColor(PlayerPalette.green);
      expect(out.log, ['play -2 assets/sdk/players/green-happy.wav']);
    });

    test('trying characters in a row lets the voices overlap', () {
      client.pickColor(PlayerPalette.green);
      client.pickColor(PlayerPalette.red);
      expect(out.log, [
        'play -2 assets/sdk/players/green-happy.wav',
        'play -3 assets/sdk/players/red-happy.wav',
      ]);
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

  group('a tone', () {
    late SilentToneOutput tones;
    late AudioEngine engine;

    setUp(() {
      tones = SilentToneOutput(keepLog: true);
      engine = AudioEngine(tones: tones);
    });

    const kettle = Tone(
      fromHz: 900,
      toHz: 1800,
      glide: Duration(seconds: 10),
      volume: 0.1,
      toVolume: 0.3,
    );

    void deliver(RoundAudio audio, double atMs) {
      for (final msg in wire(audio, atMs)) {
        // Through JSON and back, as it really travels.
        engine.receive(jsonRoundTrip(msg));
      }
    }

    test('glides exponentially: half way in time is half way in octaves', () {
      expect(kettle.hzAt(0), 900);
      expect(kettle.hzAt(5000), closeTo(900 * 1.41421356, 0.01));
      expect(kettle.hzAt(10000), 1800);
      expect(kettle.hzAt(60000), 1800, reason: 'holds at the top');
      expect(kettle.volumeAt(5000), closeTo(0.2, 1e-9));
    });

    test('survives the wire', () {
      final back = Tone.fromJson(jsonRoundTrip(kettle.toJson()));
      expect(back.fromHz, kettle.fromHz);
      expect(back.toHz, kettle.toHz);
      expect(back.glide, kettle.glide);
      expect(back.volume, kettle.volume);
      expect(back.toVolume, kettle.toVolume);
    });

    test('starts at its instant on the timeline, then glides every frame, '
        'with nothing more from the host', () {
      final audio = RoundAudio();
      final handle = audio.playToneOnPhone(green, kettle);
      deliver(audio, 1000);

      engine.pump(900);
      expect(tones.log, isEmpty, reason: 'not before its instant');

      engine.pump(1000);
      expect(tones.log, ['tone ${handle.id} 900Hz']);

      engine.pump(6000);
      expect(tones.hzOf(handle.id), closeTo(900 * 1.41421356, 0.01));
      engine.pump(11000);
      expect(tones.hzOf(handle.id), 1800);
    });

    test('a phone that arrives late joins the glide where it has got to', () {
      // A cue this late would be dropped. A tone is a state, not an event.
      final audio = RoundAudio();
      final handle = audio.playToneOnPhone(green, kettle);
      deliver(audio, 1000);

      engine.pump(1000 + 5000);
      expect(tones.hzOf(handle.id), closeTo(900 * 1.41421356, 0.01));
    });

    test('stops when told, and at the end of the round', () {
      final audio = RoundAudio();
      final first = audio.playToneOnPhone(green, kettle);
      deliver(audio, 0);
      engine.pump(0);

      audio.stopSound(first);
      deliver(audio, 100);
      expect(tones.hzOf(first.id), isNull);

      final second = audio.playToneOnPhone(green, kettle);
      deliver(audio, 200);
      engine.pump(200);
      audio.stopRoundSounds();
      deliver(audio, 300);
      expect(tones.hzOf(second.id), isNull);
    });

    test('a muted phone makes no tone', () {
      engine.muted = true;
      final audio = RoundAudio()..playToneOnPhone(green, kettle);
      deliver(audio, 0);
      engine.pump(0);
      expect(tones.log, isEmpty);
    });
  });
}

Map<String, dynamic> jsonRoundTrip(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
