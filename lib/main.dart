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
import 'sdk/ui/sticker/sticker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  UiAudio.speaker = AudioEngine(output: SoLoudOutput());

  unawaited(
    SoLoudOutput.preload([
      for (final cue in [
        ...Sounds.holdSteps,
        ...Sounds.buttonPress,
        Sounds.pop,
        Sounds.introChime,
      ])
        cue.asset!,
    ]),
  );

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await IntroAnimation.initRuntime();

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

  final _audioResume = AudioResumeWatcher(restart: restartSoLoud);

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

    _controller.warmUp();
    _controller.premium.initialize();
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
      title: 'BubbleGames',
      debugShowCheckedModeBanner: false,
      theme: stickerTheme(),
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
