import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../audio/ui_audio.dart';

/// Something the table needs to know, on whichever screen it is looking at.
///
/// Shown on the placement screen as well as the lobby, and that is the point of
/// it: the message that matters most — somebody arrived or left, so the board
/// has been laid out again and everybody's Ready was thrown away — happens while
/// people are staring at the placement screen. It was being written down on the
/// host and read by nobody.
class TableNotice extends StatelessWidget {
  const TableNotice({super.key, required this.controller});

  final AppController controller;

  /// What to say, from whichever side of the session this phone is on.
  ///
  /// The host holds it directly; every other phone is told in the lobby
  /// broadcast. Same string either way.
  String? get _message =>
      controller.host?.warning ?? controller.client?.warning;

  void _dismiss() {
    controller.host?.dismissWarning();
    controller.client?.dismissWarning();
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.group, color: scheme.onTertiaryContainer, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onTertiaryContainer,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: withButtonSound(_dismiss),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, color: scheme.onTertiaryContainer, size: 16),
          ),
        ],
      ),
    );
  }
}
