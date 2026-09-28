import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/audio/audio_engine.dart';
import 'package:multiscreen_slingshot/sdk/audio/audio_output.dart';
import 'package:multiscreen_slingshot/sdk/audio/audio_resume.dart';
import 'package:multiscreen_slingshot/sdk/audio/soloud_output.dart';
import 'package:multiscreen_slingshot/sdk/net/protocol.dart';

/// The two ways the app used to go quiet and stay quiet: an audio engine that
/// failed to start once and was never asked again, and sounds that failed to
/// play and were counted as playing until the round ran out of room.
void main() {
  group('starting the audio engine', () {
    test('a failed start is tried again, but not at once', () async {
      var now = DateTime(2026);
      var attempts = 0;
      var works = false;
      final starter = AudioStarter(
        start: () async {
          attempts++;
          if (!works) throw StateError('no audio device');
        },
        retryAfter: const Duration(seconds: 2),
        now: () => now,
      );

      expect(await starter.ensure(), isFalse);
      expect(attempts, 1);

      // Straight away: not asked again.
      expect(await starter.ensure(), isFalse);
      expect(attempts, 1);

      // The call ends; the device comes back; a little later, it is asked.
      works = true;
      now = now.add(const Duration(seconds: 3));
      expect(await starter.ensure(), isTrue);
      expect(attempts, 2);
    });

    test('once it is up, it is not started again', () async {
      var attempts = 0;
      final starter = AudioStarter(start: () async => attempts++);
      expect(await starter.ensure(), isTrue);
      expect(await starter.ensure(), isTrue);
      expect(attempts, 1);
    });

    test('callers racing each other share one start', () async {
      var attempts = 0;
      final starter = AudioStarter(
        start: () async {
          attempts++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        },
      );
      final results = await Future.wait([
        starter.ensure(),
        starter.ensure(),
        starter.ensure(),
      ]);
      expect(results, [true, true, true]);
      expect(attempts, 1);
    });

    test('reset forgets a failure', () async {
      var attempts = 0;
      final starter = AudioStarter(
        start: () async {
          attempts++;
          throw StateError('no');
        },
      );
      await starter.ensure();
      starter.reset();
      await starter.ensure();
      expect(attempts, 2);
    });
  });

  group('coming back from the background', () {
    test('rebuilds the audio only after the app really left', () async {
      var restarts = 0;
      final watcher = AudioResumeWatcher(restart: () async => restarts++);

      // Back without having gone — the notification shade, a system dialog.
      watcher.back();
      expect(restarts, 0);

      // Minimised, then back: once.
      watcher.left();
      watcher.back();
      expect(restarts, 1);

      // And not again until it leaves again.
      watcher.back();
      expect(restarts, 1);

      // Hidden and paused both count as leaving, and only one rebuild follows.
      watcher.left();
      watcher.left();
      watcher.back();
      expect(restarts, 2);
    });

    test('a restart with no audio device finishes quietly', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      var reopened = 0;
      void reopen() => reopened++;
      soLoudRestarted.add(reopen);
      addTearDown(() => soLoudRestarted.remove(reopen));

      // Two at once share one.
      final a = restartSoLoud();
      final b = restartSoLoud();
      expect(identical(a, b), isTrue);
      await a;

      // No device in a test, so nothing was started, and nobody was told to
      // reopen anything on an engine that is not there.
      expect(reopened, 0);
    });

    test('what an output was waiting to play is reported over', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final output = SoLoudOutput();
      addTearDown(output.dispose);
      final over = <int>[];
      output.onFinished = over.add;
      final playing = output.play(3, 'assets/does/not/exist.wav');
      await restartSoLoud();
      await playing;
      expect(over, contains(3));
    });
  });

  group('a sound that never plays', () {
    test('the real output reports it as over, so it frees its seat', () async {
      // In a test there is no audio device — or, if there is, no such file —
      // so this play cannot happen. What matters is that it says so.
      TestWidgetsFlutterBinding.ensureInitialized();
      final output = SoLoudOutput();
      final over = <int>[];
      output.onFinished = over.add;
      await output.play(7, 'assets/does/not/exist.wav');
      expect(over, [7]);
    });

    test('twelve failures no longer silence the rest of the round', () {
      final output = _FailingOutput();
      final engine = AudioEngine(output: output);

      // Twelve sounds that fail, then one that works — all sent by the host.
      for (var h = 1; h <= AudioEngine.maxVoices + 1; h++) {
        if (h <= AudioEngine.maxVoices) output.failing.add('assets/x$h.wav');
        engine.receive({
          'type': HostMsg.sound,
          'op': 'play',
          'h': h,
          'at': 0,
          'asset': 'assets/x$h.wav',
        });
      }
      engine.pump(1);

      expect(
        output.played,
        contains('assets/x${AudioEngine.maxVoices + 1}.wav'),
      );
    });
  });
}

/// An output whose plays of the [failing] files fail — reporting them as
/// over, as the real one now does.
class _FailingOutput extends SilentAudioOutput {
  final failing = <String>{};
  final played = <String>[];
  void Function(int handleId)? _onFinished;

  @override
  set onFinished(void Function(int handleId)? callback) =>
      _onFinished = callback;

  @override
  Future<void> play(
    int handleId,
    String asset, {
    bool loop = false,
    double volume = 1.0,
    Duration fadeIn = Duration.zero,
  }) async {
    if (failing.contains(asset)) {
      _onFinished?.call(handleId);
      return;
    }
    played.add(asset);
  }
}
