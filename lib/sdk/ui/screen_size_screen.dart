import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/device_metrics.dart';
import '../platform/native_dpi_channel.dart';
import 'card_calibrate_screen.dart';
import 'lobby_flow_style.dart';

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

    return Scaffold(
      backgroundColor: LobbyFlowColors.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                LobbyHeader(
                  title: 'Screen size',
                  onBack: () => Navigator.of(context).pop(),
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                ),
                const SizedBox(height: 18),

                // What the phone believes, drawn rather than written: the same
                // picture the settings page shows, and the thing every control
                // below is trying to make true.
                DimensionsCard(metrics: m),
                const SizedBox(height: 12),

                // The rest of what the old card reported, in one line. These
                // are facts about the panel, not settings — the pixels and the
                // dpi follow from the millimetres above.
                Text(
                  '${m.activePxWidth.toInt()} × ${m.activePxHeight.toInt()} px'
                  '   ·   ${m.dpi.toStringAsFixed(0)} dpi'
                  '   ·   bezel ${m.bezelMm.toStringAsFixed(1)} mm',
                  textAlign: TextAlign.center,
                  style: LobbyText.body,
                ),
                const SizedBox(height: 20),

                Text(
                  'The board is built in millimetres, so these numbers decide '
                  'whether the seam lines up. Measure the lit glass (not the '
                  'casing) and the dead border around it.',
                  textAlign: TextAlign.center,
                  style: LobbyText.body,
                ),
                const SizedBox(height: 22),

                // The two ways of not measuring anything by hand, first,
                // because either one may make the fields below unnecessary.
                LobbyPillButton(
                  onPressed: _detecting ? null : _redetect,
                  icon: Icons.autorenew,
                  label: _detecting ? 'Detecting…' : 'Re-detect automatically',
                  // The same purple as the card button below. They are the two
                  // halves of one offer — let the phone work its size out for
                  // you — so they are one colour, and the difference between
                  // them is only which one you happen to have a card for.
                  background: LobbyFlowColors.purple,
                  fontSize: 16,
                  iconSize: 20,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 20,
                  ),
                ),
                const SizedBox(height: 12),
                LobbyPillButton(
                  onPressed: _calibrateWithCard,
                  icon: Icons.credit_card,
                  label: 'Auto-calibrate with physical card',
                  background: LobbyFlowColors.purple,
                  fontSize: 16,
                  iconSize: 20,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 20,
                  ),
                ),
                const SizedBox(height: 26),

                // And the ruler, for whoever has one. Width and height side by
                // side because they are one measurement taken twice; the bezel
                // on its own line because it is a different thing entirely —
                // the dead border, not the glass.
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Measurement(
                        label: 'Screen height (mm)',
                        controller: _height,
                        onChanged: _push,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Measurement(
                  label: 'Bezel per edge (mm)',
                  controller: _bezel,
                  onChanged: _push,
                ),
                const SizedBox(height: 28),

                // The dialog's Done button, kept: the back pill in the header
                // is the same way out, but a page you have just typed into
                // wants somewhere deliberate to say "that is it".
                LobbyPillButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icons.check,
                  label: 'Done',
                  background: LobbyFlowColors.green,
                  fontSize: 17,
                  iconSize: 20,
                  radius: LobbyMetrics.bigRadius,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One millimetre field, named above rather than inside.
///
/// The flow's fields are pills with a hint in them, and a hint disappears the
/// moment there is a value — which is exactly wrong for three numbers that all
/// look alike once typed.
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6),
          child: Text(label, style: LobbyText.body),
        ),
        LobbyChipField(
          controller: controller,
          onChanged: (_) => onChanged(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
        ),
      ],
    );
  }
}

/// What this phone thinks it measures, drawn as the screen it is describing.
class DimensionsCard extends StatelessWidget {
  const DimensionsCard({super.key, required this.metrics});

  final DeviceMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: LobbyFlowColors.field,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Text('Screen dimensions', style: LobbyText.label),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Measure('${metrics.heightMm.toStringAsFixed(0)} mm'),
              const SizedBox(width: 10),
              // The phone lying on its side, as the mockup draws it.
              Expanded(
                child: AspectRatio(
                  aspectRatio: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: LobbyFlowColors.ink, width: 3),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Measure('${metrics.widthMm.toStringAsFixed(0)} mm'),
        ],
      ),
    );
  }
}

class _Measure extends StatelessWidget {
  const _Measure(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: LobbyFlowColors.ink,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
  );
}
