import 'package:flutter/material.dart';

import '../model/table_change.dart';
import 'sticker/sticker.dart';

/// The whole screen, because the whole table has to act.
///
/// A banner was not enough. Somebody leaving means every remaining phone is
/// about to be asked to move — the board has been laid out again and the Ready
/// everyone gave has been thrown away — and when the playlist has nothing left
/// for the phones that remain, the round people were setting up is simply over.
/// Neither of those is something to notice out of the corner of an eye while
/// holding a finger on a confirm ring.
///
/// It takes a tap to clear, and that is the point: it is an acknowledgement, not
/// a notification. Until every phone has read it the round waits, which is the
/// same thing the table is doing anyway.
class TableChangeScreen extends StatelessWidget {
  const TableChangeScreen({
    super.key,
    required this.change,
    required this.onDismiss,
  });

  final TableChange change;

  /// Move the table on, or null on a phone that cannot.
  ///
  /// Only the host gets a button. Every phone shows the message — everybody has
  /// to put their phone somewhere new — but five people tapping five
  /// acknowledgements is five ways for the round to stall, so the decision sits
  /// with the one device that is already deciding what to play.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final carriesOn = change.carriesOn;

    // Blue for "the table changed, here is where it is going"; red only when
    // there is nowhere to go. The difference is the whole message, so it is
    // carried by the colour and the icon as well as the words — this is read
    // across a table, at a glance, by somebody who has just picked their phone
    // back up.
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

              // The event, given the most room on the screen: it is the one
              // thing nobody at the table can work out on their own.
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
                  // A dead end is the end of the run, so it goes where every
                  // finished run goes: the final standings. The lobby is one
                  // more tap past that, on a screen that has first told the
                  // table how the evening actually went.
                  label: carriesOn ? 'Go to next game' : 'Score board',
                  color: carriesOn ? St.go : const Color(0xFFFE7013),
                  textColor: St.white,
                  height: 68,
                  fontSize: 24,
                )
              else
                // Something to look at, so a phone with no button does not
                // read as a phone that has frozen.
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
