import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../host/host_session.dart';
import 'sticker/sticker.dart';

// The host's join code: a small sticker that opens it big. Shared by the
// lobby and the results screen — on the second, so a phone that dropped out of
// the run and cannot see the game in its join list can scan its way back to
// its seat between games.

/// The code as a sticker, tilted, with the blue expand mark on its corner.
///
/// At this size it is a picture of a QR rather than a scannable one, so the
/// expand mark says what it is for. Opens [showJoinCodeSticker].
class JoinCodeSticker extends StatelessWidget {
  const JoinCodeSticker({super.key, required this.host});

  final HostSession host;

  @override
  Widget build(BuildContext context) {
    final code = host.qrPayload;

    return Semantics(
      label: 'Show the join code full screen',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          StickerButton(
            width: 62,
            height: 62,
            radius: 12,
            shadow: 3,
            tiltDeg: 3,
            padding: const EdgeInsets.all(5),
            onTap: code == null
                ? null
                : () => showJoinCodeSticker(context, code),
            child: code == null
                ? const StIcon(Symbols.more_horiz_rounded, color: St.muted)
                : QrImageView(
                    // Address *and* code: scanning proves you were standing
                    // in front of this screen, which is what the code asks
                    // for anyway — so a scan should not demand it twice.
                    data: code,
                    version: QrVersions.auto,
                    backgroundColor: St.white,
                    padding: EdgeInsets.zero,
                  ),
          ),
          Positioned(
            top: -10,
            right: -10,
            child: IgnorePointer(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: St.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: St.ink, width: 3),
                ),
                child: const Center(
                  child: StIcon(
                    Symbols.open_in_full_rounded,
                    size: 14,
                    color: St.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The code, big, on a sticker in the middle of the screen. A tap anywhere
/// closes it.
///
/// As large as the screen allows: this is the one moment it is being scanned
/// rather than glanced at — somebody holding their phone over yours, across a
/// table, in whatever light the room has.
Future<void> showJoinCodeSticker(BuildContext context, String payload) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: const Color(0x8C111111),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, _, _) {
        final side = (MediaQuery.sizeOf(ctx).shortestSide - 100).clamp(
          200.0,
          360.0,
        );
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: PopIn(
                child: StickerCard(
                  radius: 30,
                  shadow: 8,
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Scan to join!', style: St.display(28)),
                      const SizedBox(height: 14),
                      QrImageView(
                        data: payload,
                        version: QrVersions.auto,
                        size: side,
                        backgroundColor: St.white,
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Tap anywhere to close',
                        style: St.body(14, color: const Color(0xFF666666)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
