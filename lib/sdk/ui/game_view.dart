import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../client/viewport_game.dart';
import '../contract/sim.dart' show TouchPhase;
import '../contract/view.dart';

/// The gameplay screen: one phone's window onto the shared board.
class GameView extends StatefulWidget {
  const GameView({super.key, required this.controller});

  final AppController controller;

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  late final ViewportGame _game;
  Timer? _statsTimer;
  Timer? _hudTimer;
  bool _showDebug = false;
  String _shownHudState = '';

  @override
  void initState() {
    super.initState();
    _game = ViewportGame(session: widget.controller.client!);

    // Snapshots arrive 60 times a second and deliberately do not notify the
    // widget tree — that is what keeps rendering in the Flame loop. The game's
    // shared state rides along with them, so poll it slowly and rebuild the
    // HUD only when something a human can read actually changed.
    _hudTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final client = widget.controller.client!;
      final signature = '${client.sharedState}';
      if (signature != _shownHudState && mounted) {
        setState(() => _shownHudState = signature);
      }
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _hudTimer?.cancel();
    super.dispose();
  }

  void _toggleDebug() {
    setState(() => _showDebug = !_showDebug);
    _statsTimer?.cancel();
    if (_showDebug) {
      // The readouts change every frame; refreshing the panel a few times a
      // second is enough and keeps it out of the render loop.
      _statsTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => setState(() {}),
      );
    }
  }

  /// Raw local input, forwarded untouched.
  ///
  /// Deliberately [PointerEvent.localPosition] and not the global position: the
  /// whole surface may be turned to match a phone laid sideways on the table,
  /// and the local frame is the turned one. Reading global coordinates here
  /// would send the host a finger that never moves the way the player's did.
  ///
  /// The listener fills the surface with no padding, so local coordinates start
  /// at the first lit pixel — which is exactly what the host's transform
  /// expects.
  void _pointer(PointerEvent event, String phase) {
    widget.controller.client!.sendTouch(
      event.localPosition.dx,
      event.localPosition.dy,
      phase,
    );
  }

  /// The game's own overlay, if it has one.
  Widget? get _hud {
    final client = widget.controller.client!;
    final view = client.view;
    if (view == null) return null;
    return view.buildHud(
      context,
      HudFrame(
        phoneId: client.phoneId ?? '',
        sharedState: client.sharedState,
        scores: client.scores,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.controller.client!;
    final layout = client.layout;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      // The app never rotates; the *board* does. Turning the whole gameplay
      // surface — canvas, HUD and buttons together — is what makes a phone laid
      // on its side read upright to the person at the table.
      // Deliberately not turned. A phone placed at an angle occupies an angled
      // slot in the *world*, and the camera already turns to match it — so the
      // world arrives upright on this screen and the HUD reads normally. Doing
      // it here as well would rotate everything a second time.
      body: Stack(
        children: [
          Positioned.fill(child: GameWidget(game: _game)),
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _pointer(e, TouchPhase.down),
              onPointerMove: (e) => _pointer(e, TouchPhase.move),
              onPointerUp: (e) => _pointer(e, TouchPhase.up),
              onPointerCancel: (e) => _pointer(e, TouchPhase.up),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 10,
            top: 8,
            child: Row(
              children: [
                _Badge(
                  text: layout == null
                      ? client.phoneId ?? '…'
                      : '${client.phoneId} · '
                            '${layout.index + 1}/${layout.total}',
                ),
                // This phone's running score, when the session has one at all.
                if (client.scores.isUsed) ...[
                  const SizedBox(width: 6),
                  _Badge(
                    text: '${client.scores[client.phoneId ?? '']} pts',
                    highlight: true,
                  ),
                ],
                // Whatever the game wants to say for itself.
                if (_hud != null) ...[const SizedBox(width: 6), _hud!],
              ],
            ),
          ),
          Positioned(
            right: 6,
            top: 4,
            child: Row(
              children: [
                _HudButton(
                  icon: Icons.refresh,
                  tooltip: 'Start the round over',
                  onPressed: client.sendReset,
                ),
                _HudButton(
                  icon: Icons.bug_report_outlined,
                  tooltip: 'Debug',
                  onPressed: _toggleDebug,
                ),
                _HudButton(
                  icon: Icons.logout,
                  tooltip: 'Leave',
                  onPressed: widget.controller.leave,
                ),
              ],
            ),
          ),
          if (_showDebug)
            Positioned(
              left: 10,
              bottom: 10,
              child: _DebugPanel(
                controller: widget.controller,
                game: _game,
                onChanged: () => setState(() {}),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.highlight = false});

  final String text;

  /// Used for the score, which is the one badge worth glancing at mid-game.
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: highlight ? 0.5 : 0.35),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: highlight ? 12.5 : 11,
        fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
        color: highlight ? const Color(0xFFFFD166) : Colors.white70,
      ),
    ),
  );
}

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    iconSize: 18,
    color: Colors.white54,
    icon: Icon(icon),
  );
}

/// Everything you need to argue about whether the seam is working.
class _DebugPanel extends StatelessWidget {
  const _DebugPanel({
    required this.controller,
    required this.game,
    required this.onChanged,
  });

  final AppController controller;
  final ViewportGame game;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;
    final buffer = client.buffer;
    final layout = client.layout;

    return Container(
      width: 300,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Interpolation delay',
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: buffer.interpDelayMs,
                  min: 0,
                  max: 200,
                  divisions: 20,
                  label: '${buffer.interpDelayMs.round()} ms',
                  onChanged: (v) {
                    buffer.interpDelayMs = v;
                    onChanged();
                  },
                ),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  '${buffer.interpDelayMs.round()}ms',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ],
          ),
          const Text(
            'Drag this to 0 and watch the bird stutter — that is the jitter the '
            'buffer is hiding.',
            style: TextStyle(fontSize: 9.5, color: Colors.white38),
          ),
          // The grid and dead-zone toggles used to live here, back when one
          // renderer drew every game. They belong to ShapeView now, and a game
          // that draws its own pixels was never going to honour them.
          const Divider(height: 14, color: Colors.white24),
          _row(
            'rtt',
            client.rttMs == null
                ? '—'
                : '${client.rttMs!.toStringAsFixed(0)} ms',
          ),
          _row('snapshots buffered', '${buffer.bufferedSnapshots}'),
          _row(
            'snapshot spacing',
            '${buffer.snapshotIntervalMs.toStringAsFixed(1)} ms',
          ),
          _row('extrapolating', buffer.extrapolating ? 'YES' : 'no'),
          _row('render clock', '${buffer.renderTimeMs.toStringAsFixed(0)} ms'),
          if (layout != null) ...[
            _row('px per cm', layout.logicalPxPerWorldUnit.toStringAsFixed(1)),
            _row(
              'world offset',
              '${layout.worldCenterX.toStringAsFixed(2)} cm',
            ),
            _row('viewport', layout.viewport.toString()),
          ],
          if (controller.host != null) ...[
            const Divider(height: 14, color: Colors.white24),
            TextButton.icon(
              // Back to the arrangement screen for the *same* game, which is
              // what you want when a measurement turned out wrong.
              onPressed: () => controller.host!.recalibrate(),
              icon: const Icon(Icons.tune, size: 15),
              label: const Text(
                'Re-calibrate the board',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white38),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
      ],
    ),
  );
}
