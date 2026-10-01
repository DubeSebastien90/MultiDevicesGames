import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../audio/ui_audio.dart';
import 'sticker/sticker.dart';

class TableNotice extends StatelessWidget {
  const TableNotice({super.key, required this.controller});

  final AppController controller;

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

    return StickerCard(
      radius: 18,
      shadow: 4,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: St.blue,
              shape: BoxShape.circle,
              border: Border.all(color: St.ink, width: 2.5),
            ),
            child: const Center(
              child: StIcon(Symbols.group_rounded, size: 18, color: St.white),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: St.body(14, weight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: withButtonSound(_dismiss),
            visualDensity: VisualDensity.compact,
            icon: const StIcon(Symbols.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
