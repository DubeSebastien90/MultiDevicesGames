import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/device_metrics.dart';
import '../platform/native_dpi_channel.dart';
import 'card_calibrate_screen.dart';
import 'sticker/sticker.dart';

/// Correcting what the platform guessed about this screen — a page, not a
/// dialog.
///
/// It used to be an [AlertDialog] wrapped around a collapsible card, which put
/// three text fields, two buttons and a paragraph of explanation inside a box
/// that could not show them all at once. Everything that was in there is still
/// here; it is laid out as the flow lays out a screen, in the order somebody
/// actually works in — see what the phone believes, try the automatic answers,
/// then correct the numbers by hand.
///
/// Flutter reports a density *bucket*, not the panel's real DPI, so the derived
/// millimetres can be several percent out — which is several millimetres of
/// seam misalignment. A ruler across the glass beats any estimate, and this is
/// the same trade the placement Confirm step already makes: when there is no
/// sensor, the human is the sensor.
class ScreenSizeScreen extends StatefulWidget {
  const ScreenSizeScreen({
    super.key,
    required this.metrics,
    required this.onChanged,
  });

  final DeviceMetrics metrics;
  final ValueChanged<DeviceMetrics> onChanged;

  @override
  State<ScreenSizeScreen> createState() => _ScreenSizeScreenState();
}

class _ScreenSizeScreenState extends State<ScreenSizeScreen> {
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _bezel;

  /// The numbers as they stand right now, so the drawing and the fact line
  /// answer the fields as they are typed in rather than a round late.
  late DeviceMetrics _metrics = widget.metrics;

  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    final m = widget.metrics;
    _width = TextEditingController(text: m.widthMm.toStringAsFixed(1));
    _height = TextEditingController(text: m.heightMm.toStringAsFixed(1));
    _bezel = TextEditingController(text: m.bezelMm.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _bezel.dispose();
    super.dispose();
  }

  /// Hand the typed numbers on, keeping whatever could not be parsed.
  void _push() {
    final m = _metrics;
    _publish(
      m.copyWith(
        widthMm: double.tryParse(_width.text) ?? m.widthMm,
        heightMm: double.tryParse(_height.text) ?? m.heightMm,
        bezelMm: double.tryParse(_bezel.text) ?? m.bezelMm,
      ),
    );
  }

  void _publish(DeviceMetrics m) {
    setState(() => _metrics = m);
    widget.onChanged(m);
  }

  /// Ask the platform again. Worth offering on its own: a phone that was
  /// calibrated on an older build may simply have a better answer waiting.
  Future<void> _redetect() async {
    setState(() => _detecting = true);
    try {
      final m = _metrics;
      final result = await NativeDpiChannel.detect(
        physicalPx: Size(m.activePxWidth, m.activePxHeight),
        devicePixelRatio: m.devicePixelRatio,
        platform: defaultTargetPlatform,
      );
      if (!mounted) return;
      _width.text = result.widthMm.toStringAsFixed(1);
      _height.text = result.heightMm.toStringAsFixed(1);
      _publish(result.copyWith(bezelMm: m.bezelMm, label: m.label));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  /// The card flow, which measures the panel by a thing of known size.
  Future<void> _calibrateWithCard() async {
    final result = await Navigator.of(context).push<DeviceMetrics>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CardCalibrateScreen(metrics: _metrics),
      ),
    );
    if (result == null || !mounted) return;
    _width.text = result.widthMm.toStringAsFixed(1);
    _height.text = result.heightMm.toStringAsFixed(1);
    _publish(result);
  }

  @override
  Widget build(BuildContext context) {
    final m = _metrics;
    final note = St.body(14, weight: FontWeight.w500, color: St.muted);

    return StickerPage(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          StickerHeader(
            'Screen size',
            onBack: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 22),

          // What the phone believes, drawn rather than written: the same
          // picture the settings page shows, and the thing every control
          // below is trying to make true.
          DimensionsCard(metrics: m),
          const SizedBox(height: 14),

          // The rest of what the old card reported, in one line. These are
          // facts about the panel, not settings — the pixels and the dpi
          // follow from the millimetres above.
          Text(
            '${m.activePxWidth.toInt()} × ${m.activePxHeight.toInt()} px'
            '   ·   ${m.dpi.toStringAsFixed(0)} dpi'
            '   ·   bezel ${m.bezelMm.toStringAsFixed(1)} mm',
            textAlign: TextAlign.center,
            style: St.body(14, color: St.muted),
          ),
          const SizedBox(height: 14),
          Text(
            'The board is built in millimetres, so these numbers decide '
            'whether the seam lines up. Measure the lit glass (not the '
            'casing) and the dead border around it.',
            textAlign: TextAlign.center,
            style: note,
          ),
          const SizedBox(height: 22),

          // The two ways of not measuring anything by hand, first, because
          // either one may make the fields below unnecessary. One colour:
          // they are two halves of one offer — let the phone work its size
          // out for you — and differ only in whether you have a card.
          StickerWideButton(
            onTap: _detecting ? null : _redetect,
            icon: Symbols.autorenew_rounded,
            label: _detecting ? 'Detecting…' : 'Re-detect automatically',
            color: St.blue,
            textColor: St.white,
            fontSize: 20,
          ),
          const SizedBox(height: 16),
          StickerWideButton(
            onTap: _calibrateWithCard,
            icon: Symbols.credit_card_rounded,
            label: 'Auto-calibrate with physical card',
            color: St.blue,
            textColor: St.white,
            fontSize: 20,
          ),
          const SizedBox(height: 28),

          // And the ruler, for whoever has one. Width and height side by side
          // because they are one measurement taken twice; the bezel on its
          // own line because it is a different thing entirely — the dead
          // border, not the glass.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Measurement(
                  label: 'Screen width (mm)',
                  controller: _width,
                  onChanged: _push,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _Measurement(
                  label: 'Screen height (mm)',
                  controller: _height,
                  onChanged: _push,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Measurement(
            label: 'Bezel per edge (mm)',
            controller: _bezel,
            onChanged: _push,
          ),
          const SizedBox(height: 28),

          // The back button in the header is the same way out, but a page
          // you have just typed into wants somewhere deliberate to say "that
          // is it".
          StickerWideButton(
            onTap: () => Navigator.of(context).pop(),
            icon: Symbols.check_rounded,
            label: 'Done',
            color: St.go,
            textColor: St.white,
            height: 66,
            fontSize: 26,
          ),
        ],
      ),
    );
  }
}

/// One millimetre field, named above rather than inside.
class _Measurement extends StatelessWidget {
  const _Measurement({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => StickerField(
    label: label,
    controller: controller,
    onChanged: (_) => onChanged(),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
  );
}

/// What this phone thinks it measures, drawn as the screen it is describing.
class DimensionsCard extends StatelessWidget {
  const DimensionsCard({super.key, required this.metrics});

  final DeviceMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final measure = St.display(18, height: 1);
    return StickerCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          Text('Screen dimensions', style: St.display(22, height: 1)),
          const SizedBox(height: 18),
          Row(
            children: [
              Text('${metrics.heightMm.toStringAsFixed(0)} mm', style: measure),
              const SizedBox(width: 12),
              // The phone lying on its side, as a sticker of its own.
              Expanded(
                child: AspectRatio(
                  aspectRatio: 2,
                  child: DecoratedBox(
                    decoration: St.sticker(
                      color: const Color(0xFFBDE8FB),
                      radius: 14,
                      shadow: 4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('${metrics.widthMm.toStringAsFixed(0)} mm', style: measure),
        ],
      ),
    );
  }
}
