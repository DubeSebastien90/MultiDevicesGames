import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../client/viewport_game.dart';
import '../net/protocol.dart';

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
  bool _showDebug = false;

  @override
  void initState() {
    super.initState();
    _game = ViewportGame(session: widget.controller.client!);
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
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
  /// [PointerEvent.position] is already global logical pixels, so this is
  /// immune to any inset or padding between the game surface and the screen
  /// edge — and the edge is exactly where the interesting touches are.
  void _pointer(PointerEvent event, String phase) {
    widget.controller.client!
        .sendTouch(event.position.dx, event.position.dy, phase);
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.controller.client!;
    final layout = client.layout;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
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
            child: _Badge(
              text: layout == null
                  ? client.phoneId ?? '…'
                  : '${client.phoneId} · ${layout.index + 1}/${layout.total}',
            ),
          ),
          Positioned(
            right: 6,
            top: 4,
            child: Row(
              children: [
                _HudButton(
                  icon: Icons.refresh,
                  tooltip: 'Reset the bird',
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
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, color: Colors.white70),
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
          const SizedBox(height: 6),
          _toggle(
            'World grid',
            game.showGrid,
            (v) {
              game.showGrid = v;
              onChanged();
            },
          ),
          _toggle(
            'Mark the dead zone',
            game.showSeams,
            (v) {
              game.showSeams = v;
              onChanged();
            },
          ),
          const Divider(height: 14, color: Colors.white24),
          _row('rtt', client.rttMs == null
              ? '—'
              : '${client.rttMs!.toStringAsFixed(0)} ms'),
          _row('snapshots buffered', '${buffer.bufferedSnapshots}'),
          _row('snapshot spacing',
              '${buffer.snapshotIntervalMs.toStringAsFixed(1)} ms'),
          _row('extrapolating', buffer.extrapolating ? 'YES' : 'no'),
          _row('render clock', '${buffer.renderTimeMs.toStringAsFixed(0)} ms'),
          if (layout != null) ...[
            _row('px per cm',
                layout.logicalPxPerWorldUnit.toStringAsFixed(1)),
            _row('world offset',
                '${layout.worldOffsetX.toStringAsFixed(2)} cm'),
            _row('viewport', layout.viewport.toString()),
          ],
          if (controller.host != null) ...[
            const Divider(height: 14, color: Colors.white24),
            TextButton.icon(
              onPressed: () => controller.host!.returnToLobby(),
              icon: const Icon(Icons.tune, size: 15),
              label: const Text('Re-calibrate the board',
                  style: TextStyle(fontSize: 11)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) => Row(
    children: [
      SizedBox(
        height: 26,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
    ],
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
        Text(value,
            style: const TextStyle(fontSize: 10, color: Colors.white70)),
      ],
    ),
  );
}
