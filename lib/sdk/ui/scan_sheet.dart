import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'sticker/sticker.dart';

/// True where a camera scanner is actually available. Desktop builds fall back
/// to typing the address, which is why that path is never hidden away.
bool get qrScanSupported {
  try {
    return Platform.isAndroid || Platform.isIOS;
  } on Object {
    return false;
  }
}

/// Scans the host's QR and returns its raw payload (`ws://ip:port`).
class ScanSheet extends StatefulWidget {
  const ScanSheet({super.key});

  @override
  State<ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<ScanSheet> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _done = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StickerPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: StickerHeader(
              'Scan the host QR',
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Point the camera at the code on the host's screen.",
            textAlign: TextAlign.center,
            style: St.body(15, weight: FontWeight.w500, color: St.muted),
          ),
          Expanded(
            // The camera feed as a sticker: clipped to the card's rounded
            // shape, inside its ink border.
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: StickerCard(
                radius: 30,
                shadow: 7,
                padding: EdgeInsets.zero,
                clip: true,
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => ColoredBox(
                    color: St.white,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Camera unavailable: ${error.errorCode.name}\n\n'
                          'Go back and type the address instead.',
                          textAlign: TextAlign.center,
                          style: St.body(17),
                        ),
                      ),
                    ),
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
