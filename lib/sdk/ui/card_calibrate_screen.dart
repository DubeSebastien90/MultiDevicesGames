import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/device_metrics.dart';
import 'sticker/sticker.dart';

class CardCalibrateScreen extends StatefulWidget {
  const CardCalibrateScreen({super.key, required this.metrics});

  final DeviceMetrics metrics;

  @override
  State<CardCalibrateScreen> createState() => _CardCalibrateScreenState();
}

class _CardCalibrateScreenState extends State<CardCalibrateScreen> {
  static const _kWidthMm = 54.0;
  static const _kHeightMm = 85.6;
  static const _kCornerMm = 3.18;

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

    final cardW = _kWidthMm * _dpi / 25.4 / dpr;
    final cardH = _kHeightMm * _dpi / 25.4 / dpr;
    final cornerR = _kCornerMm * _dpi / 25.4 / dpr;

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
      backgroundColor: St.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: StickerHeader(
                'Card calibration',
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: Center(
                child: Container(
                  width: cardW,
                  height: cardH,
                  decoration: BoxDecoration(
                    color: St.white,
                    border: Border.all(color: St.ink, width: 3),
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
                style: St.body(15, weight: FontWeight.w500, color: St.muted),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${result.widthMm.toStringAsFixed(1)} × '
              '${result.heightMm.toStringAsFixed(1)} mm',
              style: St.display(26),
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 8,
                activeTrackColor: St.ink,
                inactiveTrackColor: St.white,
                thumbColor: St.go,
                overlayColor: St.go.withValues(alpha: 0.18),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
              ),
              child: Slider(
                value: _dpi.clamp(minDpi, maxDpi),
                min: minDpi,
                max: maxDpi,
                divisions: 450,
                onChanged: (v) => setState(() => _dpi = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: StickerWideButton(
                onTap: () => Navigator.of(context).pop(result),
                icon: Symbols.check_rounded,
                label: 'Save',
                color: St.go,
                textColor: St.white,
                height: 66,
                fontSize: 26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
