library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

import '../audio/sounds.dart';
import '../audio/ui_audio.dart';

class IntroAnimation extends StatefulWidget {
  const IntroAnimation({
    super.key,
    required this.onDone,
    this.playerColor,
    this.duration = fallbackAfter,
  });

  final VoidCallback onDone;

  final Color? playerColor;

  final Duration duration;

  static const fallbackAfter = Duration(seconds: 6);

  static const drawnSeconds = 2.0;

  static const playedSeconds = 3.0;

  static const pace = drawnSeconds / playedSeconds;

  static const asset = 'assets/sdk/animations/startanimationColors.riv';

  static const stateMachine = 'SM1';
  static const startTrigger = 'startGame';

  static const doneEvent = 'EyesOpenDone';

  static const viewModel = 'PersoVM';
  static const colorProperty = 'skinColor';

  static bool get available => _available;
  static bool _available = false;

  static bool get platformSupportsRive =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;

  static Future<void> initRuntime() async {
    if (!platformSupportsRive) {
      debugPrint(
        '[intro] not rendered on $defaultTargetPlatform — see '
        'IntroAnimation.platformSupportsRive',
      );
      _available = false;
      return;
    }
    try {
      await rive.RiveNative.init();
      _available = true;
    } on Object catch (e) {
      debugPrint(
        '[intro] Rive runtime unavailable, intros will be skipped: $e',
      );
      _available = false;
    }
  }

  @override
  State<IntroAnimation> createState() => _IntroAnimationState();
}

base class _IntroController extends rive.RiveWidgetController {
  _IntroController(super.file, {super.stateMachineSelector});

  VoidCallback? onSettled;

  bool _ran = false;
  bool _flushed = false;

  @override
  bool advance(double elapsedSeconds) {
    if (super.advance(elapsedSeconds * IntroAnimation.pace)) {
      _ran = true;
      _flushed = false;
      return true;
    }
    if (!_ran) return false;
    if (!_flushed) {
      _flushed = true;
      return true;
    }
    onSettled?.call();
    return false;
  }
}

class _IntroAnimationState extends State<IntroAnimation> {
  rive.File? _file;
  _IntroController? _controller;
  Timer? _net;
  bool _done = false;

  @override
  void initState() {
    super.initState();

    _net = Timer(widget.duration, () {
      debugPrint(
        '[intro] ${IntroAnimation.doneEvent} never arrived — '
        'lifting the curtain anyway',
      );
      _finish();
    });

    if (IntroAnimation.available) {
      unawaited(_load());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  Future<void> _load() async {
    try {
      final file = await rive.File.asset(
        IntroAnimation.asset,
        riveFactory: rive.Factory.rive,
      );
      if (file == null) throw StateError('not found');
      if (!mounted) {
        file.dispose();
        return;
      }

      final controller = _IntroController(
        file,
        stateMachineSelector: rive.StateMachineSelector.byName(
          IntroAnimation.stateMachine,
        ),
      )..onSettled = _finish;
      controller.stateMachine.addEventListener(_onRiveEvent);
      _paint(controller);

      // ignore: deprecated_member_use
      controller.stateMachine.trigger(IntroAnimation.startTrigger)?.fire();

      UiAudio.speaker.play(Sounds.introChime);

      setState(() {
        _file = file;
        _controller = controller;
      });
    } on Object catch (e) {
      debugPrint('[intro] ${IntroAnimation.asset} did not start: $e');
      if (mounted) _finish();
    }
  }

  void _paint(rive.RiveWidgetController controller) {
    final color = widget.playerColor;
    if (color == null) return;
    try {
      final instance = controller.dataBind(rive.DataBind.auto());
      final property = instance.color(IntroAnimation.colorProperty);
      if (property == null) {
        debugPrint(
          '[intro] no "${IntroAnimation.colorProperty}" on '
          '${IntroAnimation.viewModel} — the character keeps its own colour',
        );
        return;
      }
      property.value = color;
    } on Object catch (e) {
      debugPrint('[intro] could not colour the character: $e');
    }
  }

  void _onRiveEvent(rive.Event event) {
    if (event.name == IntroAnimation.doneEvent) _finish();
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _net?.cancel();
    _controller?.stateMachine.removeEventListener(_onRiveEvent);
    _controller?.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return ColoredBox(
      color: const Color(0xFF0B1020),
      child: controller == null
          ? const SizedBox.expand()
          : rive.RiveWidget(controller: controller, fit: rive.Fit.contain),
    );
  }
}
