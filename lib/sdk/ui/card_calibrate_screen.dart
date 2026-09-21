import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/device_metrics.dart';
import 'lobby_flow_style.dart';

/// Full-screen calibration using an ISO 7810 ID-1 card (credit/ID cards).
///
/// The user places a physical card on the screen and slides until the outline
/// matches. Because the card dimensions are fixed worldwide (85.6 × 54 mm),
/// matching the outline uniquely determines the panel DPI, which is then used
/// to recompute accurate mm dimensions for this device.
class CardCalibrateScreen extends StatefulWidget {
  const CardCalibrateScreen({super.key, required this.metrics});

  final DeviceMetrics metrics;

  @override
  State<CardCalibrateScreen> createState() => _CardCalibrateScreenState();
}

class _CardCalibrateScreenState extends State<CardCalibrateScreen> {
  // ISO 7810 ID-1, shown portrait on a portrait screen so the narrow
  // dimension (54 mm) sits across the phone width.
  static const _kWidthMm = 54.0;
  static const _kHeightMm = 85.6;
  static const _kCornerMm = 3.18; // standard corner radius

  late double _dpi;

  @override
  void initState() {
    super.initState();
    _dpi = widget.metrics.dpi;
  }

  DeviceMetrics _calibrated() {
    final m = widget.metrics;
    return DeviceMetrics(
      activePxWidth: m.activePxWidth,
      activePxHeight: m.activePxHeight,
      widthMm: m.activePxWidth / _dpi * 25.4,
      heightMm: m.activePxHeight / _dpi * 25.4,
      bezelMm: m.bezelMm,
      devicePixelRatio: m.devicePixelRatio,
      label: m.label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final dpr = m.devicePixelRatio;

    // Card outline in logical pixels at the current DPI guess.
    final cardW = _kWidthMm * _dpi / 25.4 / dpr;
    final cardH = _kHeightMm * _dpi / 25.4 / dpr;
    final cornerR = _kCornerMm * _dpi / 25.4 / dpr;

    // Slider range: card fills 20–90 % of the available axes. dpr cancels.
    final maxDpi = math
        .min(
          m.activePxWidth * 0.90 * 25.4 / _kWidthMm,
          m.activePxHeight * 0.78 * 25.4 / _kHeightMm,
        )
        .clamp(200.0, 600.0);
    final minDpi = (m.activePxWidth * 0.22 * 25.4 / _kWidthMm).clamp(
      100.0,
      250.0,
    );

    final result = _calibrated();

    return Scaffold(
      // Paper, like the rest of the flow. It was black — which read as a
      // camera viewfinder, and this is not one — and a dark card on a white
      // screen is the easier of the two to line an outline up against anyway.
      backgroundColor: LobbyFlowColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            LobbyHeader(
              title: 'Card calibration',
              // Backing out keeps whatever the screen had before: popping with
              // no result is what the caller reads as "nothing changed".
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Center(
                child: Container(
                  width: cardW,
                  height: cardH,
                  decoration: BoxDecoration(
                    color: LobbyFlowColors.field,
                    border: Border.all(color: LobbyFlowColors.ink, width: 3),
                    borderRadius: BorderRadius.circular(cornerR),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Place a credit or ID card on the screen.\n'
                'Slide until the outline matches the card exactly.',
                textAlign: TextAlign.center,
                style: LobbyText.body,
              ),
            ),
            const SizedBox(height: 8),

            // What the slider currently claims this panel measures. The one
            // number the whole screen exists to produce, so it is set like a
            // number and not like a caption.
            Text(
              '${result.widthMm.toStringAsFixed(1)} × '
              '${result.heightMm.toStringAsFixed(1)} mm',
              style: LobbyText.count.copyWith(fontSize: 20),
            ),

            // The flow has no slider of its own, so this is one built from its
            // parts: ink track, a green thumb the size of a fingertip, and no
            // ripple — the card moving under your finger is the feedback.
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                activeTrackColor: LobbyFlowColors.ink,
                inactiveTrackColor: LobbyFlowColors.field,
                thumbColor: LobbyFlowColors.green,
                overlayColor: LobbyFlowColors.green.withValues(alpha: 0.18),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13),
              ),
              child: Slider(
                value: _dpi.clamp(minDpi, maxDpi),
                min: minDpi,
                max: maxDpi,
                divisions: 450,
                onChanged: (v) => setState(() => _dpi = v),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: LobbyPillButton(
                onPressed: () => Navigator.of(context).pop(result),
                icon: Icons.check,
                label: 'Save',
                background: LobbyFlowColors.green,
                fontSize: 17,
                iconSize: 20,
                radius: LobbyMetrics.bigRadius,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
