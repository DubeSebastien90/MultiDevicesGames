import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../audio/ui_audio.dart';
import '../host/host_session.dart';
import 'lobby_flow_style.dart';

// The host's join code: a small stamp that opens it full screen. Shared by the
// lobby and the results screen — on the second, so a phone that dropped out of
// the run and cannot see the game in its join list can scan its way back to
// its seat between games.

/// The code as a stamp, with the mark that says it opens.
///
/// At this size it is a picture of a QR and not a scannable one, so it has to
/// say what it is for. The expand mark does that in the corner where every
/// other app puts it, and it sits on the plate rather than beside it so the
/// whole thing reads as one button.
class JoinCodeStamp extends StatelessWidget {
  const JoinCodeStamp({super.key, required this.host, this.size = 46});

  final HostSession host;

  /// The QR's own side, before the plate around it.
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = host.qrPayload;
    final onTap = code == null
        ? null
        : () => showJoinCode(context, host.name, code);

    return Semantics(
      button: true,
      label: 'Show the join code full screen',
      child: GestureDetector(
        onTap: withButtonSound(onTap),
        // The mark hangs off the plate's corner, so the taps it catches are
        // the ones aimed just outside it.
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // Room for the mark to hang into, and a tap target that clears the
          // forty-four pixels a finger is entitled to.
          padding: const EdgeInsets.only(top: 7, right: 7),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: LobbyFlowColors.paper,
                  borderRadius: BorderRadius.circular(12),
                  // Lost against the lobby's grey panel, and what keeps the
                  // plate a plate on the results screen's white page.
                  border: Border.all(color: LobbyFlowColors.field, width: 2),
                ),
                child: code == null
                    ? SizedBox(
                        width: size,
                        height: size,
                        child: const Center(
                          child: Icon(
                            Icons.more_horiz,
                            size: 18,
                            color: LobbyFlowColors.muted,
                          ),
                        ),
                      )
                    : QrImageView(
                        // Address *and* code: scanning proves you were standing
                        // in front of this screen, which is what the code asks
                        // for anyway — so a scan should not demand it twice.
                        data: code,
                        version: QrVersions.auto,
                        size: size,
                        backgroundColor: LobbyFlowColors.paper,
                        padding: EdgeInsets.zero,
                      ),
              ),
              Positioned(
                top: -7,
                right: -7,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: LobbyFlowColors.ink,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    // The two arrows pointing out of each other's corner: the
                    // one glyph everybody already reads as "make this big".
                    Icons.open_in_full,
                    size: 12,
                    color: LobbyFlowColors.paper,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The code, alone, on the whole screen.
///
/// Bigger than the lobby ever drew it even before the panel learned to fold,
/// because this is the one moment it is being scanned rather than glanced at —
/// somebody is holding their phone over yours, across a table, in whatever
/// light the room has.
Future<void> showJoinCode(BuildContext context, String name, String payload) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final side = MediaQuery.sizeOf(context).shortestSide - 96;
      return Dialog.fullscreen(
        backgroundColor: LobbyFlowColors.paper,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LobbyTitle(name, fontSize: 22),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: LobbyFlowColors.paper,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: side.clamp(160.0, 360.0),
                  backgroundColor: LobbyFlowColors.paper,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 20),
              const Text('Scan this to join the game.', style: LobbyText.body),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: LobbyPillButton(
                  label: 'Done',
                  background: LobbyFlowColors.field,
                  foreground: LobbyFlowColors.ink,
                  fontSize: 17,
                  // Horizontal too: this pill is centred in a Column and so
                  // sizes to its own contents, and a padding that only names
                  // the vertical leaves the word touching both ends of it.
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 44,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
