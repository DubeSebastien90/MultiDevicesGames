/// The curtain between the lobby and the first game of a run.
///
/// Somebody presses Play and every phone at the table plays the same animation
/// before showing where to stand. It is the one moment the table looks like one
/// thing rather than six, which is the whole pitch of the platform — so it is
/// worth the seconds it costs, and it is worth it happening *together*.
///
/// The animation decides its own length. `SM1` holds on `Idle` — eyes closed —
/// until the `startGame` trigger fires, then plays `Lock_In` once. Two signals
/// mark the end and the first one wins: the `EyesOpenDone` event, and the
/// state machine coming to rest. They normally land on the same frame; see
/// [_IntroController] for why neither arrives on its own. Either way the timing
/// belongs to whoever drew the animation rather than to a number guessed here.
///
/// **It never waits forever.** Every phone was told to play within a few
/// milliseconds of every other, and every phone is playing the same one-shot,
/// so they land together. But a file that does not load, an event that gets
/// renamed, a state machine that never settles — none of those may strand a
/// phone behind a black screen while the rest of the table plays. That is what
/// [duration] is: a net under the event, not the thing that decides the timing.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

class IntroAnimation extends StatefulWidget {
  const IntroAnimation({
    super.key,
    required this.onDone,
    this.duration = fallbackAfter,
  });

  /// Called once, when the curtain should lift. Always called — on the event,
  /// on a failed load, and on a file that never says it finished.
  final VoidCallback onDone;

  /// How long to wait for `EyesOpenDone` before giving up and carrying on.
  ///
  /// Comfortably longer than the animation: this is the failure path, and a
  /// net set too tight would cut the artwork off mid-blink on a slow phone.
  final Duration duration;

  static const fallbackAfter = Duration(seconds: 6);

  static const asset = 'assets/sdk/animations/startanimation.riv';

  /// The state machine that holds the two states, and the input that starts it.
  static const stateMachine = 'SM1';
  static const startTrigger = 'startGame';

  /// Signalled by the state machine at the end of `Lock_In`.
  static const doneEvent = 'EyesOpenDone';

  /// Whether the Rive runtime came up at launch.
  ///
  /// Set once by [initRuntime]. False means every intro is skipped instantly
  /// rather than each one discovering the same failure and holding the table
  /// up while it does.
  static bool get available => _available;
  static bool _available = false;

  /// Whether this platform can be trusted to draw a Rive file.
  ///
  /// **Windows cannot, as of `rive_native` 0.1.11.** The runtime starts, the
  /// file loads and the artboard parses — and then the first rendered frame
  /// takes the whole process down, with no Dart exception, on both the Flutter
  /// and the Rive renderer. There is nothing to catch: a native crash is not an
  /// error a `try` can see, which is why this is a check up front rather than a
  /// rescue afterwards. Proved by `integration_test/native_smoke_test.dart`,
  /// which is the only thing in the suite that runs native code at all.
  ///
  /// Windows is where this is developed, not where it is played — the table is
  /// phones — so the trade is a desktop build with no curtain against a desktop
  /// build that dies on Play. macOS and Linux are untested and left in: there
  /// is no evidence either way, and excluding them on suspicion would take the
  /// intro away from platforms that may be perfectly fine.
  static bool get platformSupportsRive =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;

  /// Bring the Rive runtime up. Called once, from `main`, before `runApp`.
  ///
  /// Failure is not fatal and not even reported to the user: the intro is
  /// decoration, and a table that cannot play it should still be able to play
  /// the games.
  static Future<void> initRuntime() async {
    if (!platformSupportsRive) {
      debugPrint('[intro] not rendered on $defaultTargetPlatform — see '
          'IntroAnimation.platformSupportsRive');
      _available = false;
      return;
    }
    try {
      await rive.RiveNative.init();
      _available = true;
    } on Object catch (e) {
      debugPrint('[intro] Rive runtime unavailable, intros will be skipped: $e');
      _available = false;
    }
  }

  @override
  State<IntroAnimation> createState() => _IntroAnimationState();
}

/// Keeps the state machine alive for one frame past the end.
///
/// `rive_native` drains reported events at the *start* of `advanceAndApply`,
/// so an event signalled on one frame is only delivered on the next. `Lock_In`
/// has no exit transition: it finishes, the machine settles, the widget stops
/// advancing — and there is no next frame, so `EyesOpenDone` is reported
/// natively and never delivered. The curtain then hung on its last frame until
/// the safety net fired, which is exactly what a three-second pause looked
/// like.
///
/// So when the machine first says it is done, this asks for one more frame.
/// That frame drains the event, and the settle is reported straight after.
/// Whichever of the two reaches [IntroAnimation.onDone] first wins; it is
/// idempotent.
///
/// [onSettled] is worth having on its own, and not only as a backstop for the
/// event: it needs no name to match, so a renamed or deleted event in the
/// editor costs the animation nothing.
base class _IntroController extends rive.RiveWidgetController {
  _IntroController(super.file, {super.stateMachineSelector});

  VoidCallback? onSettled;

  /// Whether the machine has ever been running. Without this the very first
  /// frame — `Idle`, a still frame, which settles immediately — would read as
  /// 'the animation is over' before the trigger had done anything.
  bool _ran = false;
  bool _flushed = false;

  @override
  bool advance(double elapsedSeconds) {
    if (super.advance(elapsedSeconds)) {
      _ran = true;
      _flushed = false;
      return true;
    }
    if (!_ran) return false;
    if (!_flushed) {
      // One more frame, purely so the events from the last one are delivered.
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

    // Started here rather than when the file lands, so a slow decode eats into
    // the net rather than extending the wait indefinitely.
    _net = Timer(widget.duration, () {
      debugPrint('[intro] ${IntroAnimation.doneEvent} never arrived — '
          'lifting the curtain anyway');
      _finish();
    });

    if (IntroAnimation.available) {
      unawaited(_load());
    } else {
      // Nothing to show. Leave immediately, after this frame so the phase does
      // not change during a build.
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

      // Named rather than default: the file may grow a second state machine,
      // and picking whichever one happens to be first is how an intro quietly
      // starts playing the wrong thing.
      final controller = _IntroController(
        file,
        stateMachineSelector: rive.StateMachineSelector.byName(
          IntroAnimation.stateMachine,
        ),
      )..onSettled = _finish;
      controller.stateMachine.addEventListener(_onRiveEvent);

      // The state machine owns the transition; this only says 'now'. Fired
      // once, here, because nothing on this screen can ask for it twice — the
      // curtain has no button on it, and the phone is showing it because the
      // host already pressed Play.
      //
      // `trigger()` is deprecated in favour of data binding, which would need
      // the .riv to expose a ViewModel — an editor change, not a code one. The
      // pubspec is pinned to the 0.14.x line, so it cannot vanish under a `pub
      // upgrade`, and this is the only deprecated call in the codebase.
      // Removing the condition on Idle → Lock_In in the editor would retire it
      // for good.
      // ignore: deprecated_member_use
      controller.stateMachine.trigger(IntroAnimation.startTrigger)?.fire();

      setState(() {
        _file = file;
        _controller = controller;
      });
    } on Object catch (e) {
      // A missing file, a state machine under another name, a runtime that
      // will not have it. All of them are 'carry on', never a stuck phone.
      debugPrint('[intro] ${IntroAnimation.asset} did not start: $e');
      if (mounted) _finish();
    }
  }

  /// The end of `Lock_In`, as the animation itself reports it.
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
    // The same ground the rest of the app sits on, so the curtain does not
    // flash a different colour on its way in or out.
    return ColoredBox(
      color: const Color(0xFF0B1020),
      child: controller == null
          // Deliberately blank rather than a spinner. This lasts a frame or two
          // on a file this size, and a spinner that appears and vanishes reads
          // as a stutter.
          ? const SizedBox.expand()
          : rive.RiveWidget(controller: controller, fit: rive.Fit.contain),
    );
  }
}
