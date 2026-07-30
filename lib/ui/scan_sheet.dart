import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Scan the host QR')),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Camera unavailable: ${error.errorCode.name}\n\n'
              'Go back and type the address instead.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
