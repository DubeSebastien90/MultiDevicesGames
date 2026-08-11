import 'package:flutter/widgets.dart';

/// Notices when something covered the screen without the player leaving.
///
/// This exists because iOS will not say when NameDrop fires — there is no
/// notification, no callback, nothing in any framework that names the event.
/// The only thing an app can see is the shadow it casts: a full-screen system
/// card makes the app resign active, which arrives here as
/// [AppLifecycleState.inactive].
///
/// That signal is *badly* noisy, and on a table of phones lying flat with
/// people reaching across them, the loudest source is not phone calls or
/// Control Center — it is half-completed home-indicator swipes, which resign
/// active and snap back. So two filters run before anything is reported:
///
/// - **The player must not have left.** A real departure continues on to
///   [AppLifecycleState.hidden] or [AppLifecycleState.paused]; NameDrop never
///   does. This throws out every deliberate exit, every lock, every app switch.
/// - **It must have lasted.** A cancelled swipe is back inside a couple of
///   hundred milliseconds. A contact card sits there until somebody dismisses
///   it or the phones are pulled apart.
///
/// What survives both is still only a *maybe*. The filter that does the real
/// work is not here at all: it is the host noticing that two phones whose tops
/// are touching went away in the same instant. See `HostSession`.
class InterruptionWatcher with WidgetsBindingObserver {
  InterruptionWatcher(this.onInterrupted);

  /// Called with how long the screen was covered, once it is uncovered.
  final void Function(Duration held) onInterrupted;

  /// Under this, it was a gesture that did not happen.
  static const _floor = Duration(milliseconds: 500);

  /// Over this, whatever it was is not a contact card, and a round that has
  /// been paused for a minute has bigger problems than this feature.
  static const _ceiling = Duration(seconds: 60);

  /// Running from the moment the screen was covered; null when it is not.
  Stopwatch? _covered;

  /// The app went properly away — backgrounded, locked, switched out. Set on
  /// the way out and read on the way back, because the returning trip passes
  /// through [AppLifecycleState.inactive] a second time and would otherwise
  /// look exactly like the thing being watched for.
  bool _left = false;

  void start() {
    // A binding is not guaranteed — plain unit tests build sessions without
    // one. The watcher is an optimisation on a heuristic; going without it
    // costs a suggestion that does not appear, so it is not worth a crash.
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  void stop() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // Only the first one starts the clock. The second — on the way back
        // from the background — must not restart it, or a two-hour absence
        // reads as a half-second blink.
        //
        // Parenthesised because `x ??= Stopwatch()..start()` binds as
        // `(x ??= Stopwatch())..start()`, which happens to work and reads like
        // it should not.
        _covered ??= (Stopwatch()..start());

      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _left = true;

      case AppLifecycleState.resumed:
        final covered = _covered;
        _covered = null;
        final left = _left;
        _left = false;

        if (covered == null || left) return;
        final held = covered.elapsed;
        if (held >= _floor && held <= _ceiling) onInterrupted(held);
    }
  }
}
