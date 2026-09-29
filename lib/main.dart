import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sdk/app_controller.dart';
import 'sdk/audio/audio_engine.dart';
import 'sdk/audio/audio_resume.dart';
import 'sdk/audio/soloud_output.dart';
import 'sdk/audio/sounds.dart';
import 'sdk/audio/ui_audio.dart';
import 'sdk/ui/age_gate_screen.dart';
import 'sdk/ui/ball_wipe.dart';
import 'sdk/ui/intro_animation.dart';
import 'sdk/ui/role_screen.dart';
import 'sdk/ui/session_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The menus' speaker. Here and not in a widget, so tests that pump screens
  // directly keep the silent default.
  UiAudio.speaker = AudioEngine(output: SoLoudOutput());

  // Decode the sounds that play in quick runs before anyone can press
  // anything, so none of them waits on its first decode mid-sequence. Not
  // awaited: a launch should not wait on audio either.
  unawaited(
    SoLoudOutput.preload([
      for (final cue in [
        ...Sounds.holdSteps,
        ...Sounds.buttonPress,
        Sounds.pop,
        // Decoded ahead, or its first play waits on the decode and rings a
        // beat behind the animation it belongs to.
        Sounds.introChime,
      ])
        cue.asset!,
    ]),
  );

  // Landscape, because the v1 arrangement is a left-to-right strip: phones on
  // their sides make a wide board, and the bird's flight crosses the seam
  // horizontally, which is the thing we are trying to look at.
  // Portrait, always, on every device — and the app never re-lays-out because
  // somebody physically turned a phone.
  //
  // A phone lying flat on a table has no meaningful "up": gravity cannot tell
  // you which way the board runs. So orientation stops being something the OS
  // decides and becomes something a *game* declares, as `quarterTurns` on each
  // placement in its BoardPlan. The phone then rotates its own surface to match
  // the board it was put into. Chasing the accelerometer instead was the source
  // of a whole class of bug — locks that iPadOS quietly ignores, and metrics
  // measured mid-rotation.
  // `portraitUp` alone, deliberately. Allowing `portraitDown` as well undid the
  // paragraph above: a 180° flip *is* the OS re-laying-out the surface, and the
  // board it is a viewport onto is compiled once in the lobby and never
  // recomputed. Turning a phone therefore swapped the screen under a world that
  // had not moved — the camera kept aiming at the old slot, and the game looked
  // frozen or half off the edge until the round ended.
  //
  // A phone that is genuinely upside down in the arrangement is told so by its
  // placement's `quarterTurns`, which rotates the *world* to meet it. That is
  // the supported way to be upside down, and it survives being laid flat where
  // the accelerometer has nothing to say.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Edge to edge with no system bars. A status or navigation bar would eat the
  // millimetres right at the screen edge — exactly where the seam is.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Before the first frame, because the first thing a run does is play one.
  // Failure here is not fatal — intros are skipped and the games still run.
  await IntroAnimation.initRuntime();

  // Rasterise the end-of-round balls now rather than when the first round
  // ends. Not awaited: they are wanted minutes from now, and a launch should
  // not wait on artwork.
  unawaited(BallWipe.preload());

  runApp(const MultiscreenApp());
}

class MultiscreenApp extends StatefulWidget {
  const MultiscreenApp({super.key});

  @override
  State<MultiscreenApp> createState() => _MultiscreenAppState();
}

class _MultiscreenAppState extends State<MultiscreenApp> {
  final _controller = AppController();

  /// Rebuilds the audio engine on the way back from the background — the
  /// system takes the audio device from an app that is not in front, and
  /// without this nothing played again until the app was killed. See
  /// [restartSoLoud].
  final _audioResume = AudioResumeWatcher(restart: restartSoLoud);

  /// Shuts the audio engine down when the window is closed — without it the
  /// process outlives its window on Windows, see [shutdownSoLoud] — and hands
  /// leaving and coming back to [_audioResume].
  late final _exitListener = AppLifecycleListener(
    onExitRequested: () async {
      shutdownSoLoud();
      return AppExitResponse.exit;
    },
    onHide: _audioResume.left,
    onPause: _audioResume.left,
    onResume: _audioResume.back,
  );

  @override
  void initState() {
    super.initState();
    _exitListener;
    // Read this device's own name off storage now rather than when somebody
    // taps Join, so rejoining a game never waits on a disk read.
    _controller.warmUp();
    // NO-IAP: RevenueCat is never configured until in-app purchases ship.
    // Same shape: ask RevenueCat now so a host who already owns Premium sees
    // the catalogue unlocked before they ever open the games list, rather
    // than waiting on a network round trip the first time they tap it.
    // _controller.premium.initialize();
  }

  @override
  void dispose() {
    _exitListener.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Also what Android shows in the recent-apps switcher.
      title: 'BubbleGames',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4ECDC4),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1020),
      ),
      // Nothing else gets a frame until the gate has an answer. The band it
      // produces is threaded into RoleScreen as an argument rather than looked
      // up there, so the screen that owns the name field cannot be built
      // without it.
      home: AgeGate(
        builder: (context, band) => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (_controller.client == null) {
              return RoleScreen(controller: _controller, ageBand: band);
            }
            return SessionScreen(controller: _controller);
          },
        ),
      ),
    );
  }
}
