import 'package:flutter/material.dart';

import '../model/table_change.dart';
import 'lobby_flow_style.dart';

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

    // Yellow for "the table changed, here is where it is going"; coral only
    // when there is nowhere to go. The difference is the whole message, so it
    // is carried by the colour and the icon as well as the words — this is read
    // across a table, at a glance, by somebody who has just picked their phone
    // back up. Both are the flow's own colours: coral is the one it uses for a
    // round that did not go your way, not an alarm borrowed from elsewhere.
    final accent = carriesOn ? LobbyFlowColors.yellow : LobbyFlowColors.coral;

    return Scaffold(
      backgroundColor: LobbyFlowColors.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LobbyMark(
                      icon: carriesOn
                          ? Icons.group
                          : Icons.warning_amber_rounded,
                      color: accent,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'WARNING',
                      textAlign: TextAlign.center,
                      style: LobbyText.button.copyWith(
                        color: LobbyFlowColors.muted,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // The event, given the most room on the screen: it is the
                    // one thing nobody at the table can work out on their own.
                    LobbyTitle(change.who),
                    const SizedBox(height: 14),
                    Text(
                      carriesOn
                          ? 'Everyone will be asked to place their phone again.'
                          : 'No game left in the playlist fits the phones that '
                                'are still here.',
                      textAlign: TextAlign.center,
                      style: LobbyText.body,
                    ),

                    if (carriesOn) ...[
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: LobbyFlowColors.field,
                          borderRadius: BorderRadius.circular(
                            LobbyMetrics.bigRadius,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'NEXT GAME',
                              style: LobbyText.body.copyWith(letterSpacing: 2),
                            ),
                            const SizedBox(height: 4),
                            Text(change.nextGame!, style: LobbyText.count),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 30),
                    if (onDismiss != null)
                      LobbyPillButton(
                        onPressed: onDismiss,
                        icon: carriesOn
                            ? Icons.arrow_forward
                            : Icons.emoji_events,
                        // A dead end is the end of the run, so it goes where
                        // every finished run goes: the final standings. The
                        // lobby is one more tap past that, on a screen that has
                        // first told the table how the evening actually went.
                        label: carriesOn ? 'Go to next game' : 'Score board',
                        background: carriesOn
                            ? LobbyFlowColors.green
                            : LobbyFlowColors.orange,
                        fontSize: 17,
                        iconSize: 22,
                        radius: LobbyMetrics.bigRadius,
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 28,
                        ),
                      )
                    else
                      // Something to look at, so a phone with no button does
                      // not read as a phone that has frozen.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const LobbySpinner(
                            size: 16,
                            strokeWidth: 2,
                            color: LobbyFlowColors.muted,
                          ),
                          const SizedBox(width: 10),
                          Text('Waiting for the host…', style: LobbyText.body),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
