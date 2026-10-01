import 'package:flutter/material.dart';

import '../model/table_change.dart';
import 'sticker/sticker.dart';

class TableChangeScreen extends StatelessWidget {
  const TableChangeScreen({
    super.key,
    required this.change,
    required this.onDismiss,
  });

  final TableChange change;

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final carriesOn = change.carriesOn;

    final accent = carriesOn ? St.blue : St.back;

    return StickerPage(
      maxWidth: 460,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: StickerMark(
                  icon: carriesOn
                      ? Symbols.group_rounded
                      : Symbols.warning_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'WARNING',
                textAlign: TextAlign.center,
                style: St.display(
                  16,
                  color: St.muted,
                ).copyWith(letterSpacing: 3),
              ),
              const SizedBox(height: 8),
              Text(
                change.who,
                textAlign: TextAlign.center,
                style: St.display(36, height: 1.05),
              ),
              const SizedBox(height: 12),
              Text(
                carriesOn
                    ? 'Everyone will be asked to place their phone again.'
                    : 'No game left in the playlist fits the phones that '
                          'are still here.',
                textAlign: TextAlign.center,
                style: St.body(16, weight: FontWeight.w500, color: St.muted),
              ),
              if (carriesOn) ...[
                const SizedBox(height: 22),
                Center(
                  child: StickerCard(
                    tiltDeg: -1.5,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Column(
                      children: [
                        Text(
                          'NEXT GAME',
                          style: St.body(
                            13,
                            color: St.muted,
                          ).copyWith(letterSpacing: 2),
                        ),
                        const SizedBox(height: 4),
                        Text(change.nextGame!, style: St.display(26)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 30),
              if (onDismiss != null)
                StickerWideButton(
                  onTap: onDismiss,
                  icon: carriesOn
                      ? Symbols.arrow_forward_rounded
                      : Symbols.trophy_rounded,
                  label: carriesOn ? 'Go to next game' : 'Score board',
                  color: carriesOn ? St.go : const Color(0xFFFE7013),
                  textColor: St.white,
                  height: 68,
                  fontSize: 24,
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const StickerSpinner(size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'Waiting for the host…',
                      style: St.body(15, color: St.muted),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
