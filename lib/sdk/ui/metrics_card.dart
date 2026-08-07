import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/device_metrics.dart';
import '../platform/native_dpi_channel.dart';
import 'card_calibrate_screen.dart';

/// Lets the player correct what the platform guessed about this screen.
///
/// Flutter reports a density *bucket*, not the panel's real DPI, so the derived
/// millimetres can be several percent out — which is several millimetres of seam
/// misalignment. A ruler across the glass beats any estimate, and this is the
/// same trade the placement Confirm step already makes: when there is no sensor,
/// the human is the sensor.
class MetricsCard extends StatefulWidget {
  const MetricsCard({
    super.key,
    required this.metrics,
    required this.onChanged,
    this.initiallyExpanded = false,
  });

  final DeviceMetrics metrics;
  final ValueChanged<DeviceMetrics> onChanged;
  final bool initiallyExpanded;

  @override
  State<MetricsCard> createState() => _MetricsCardState();
}

class _MetricsCardState extends State<MetricsCard> {
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _bezel;
  late bool _expanded;
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
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

  void _push() {
    final m = widget.metrics;
    widget.onChanged(m.copyWith(
      widthMm: double.tryParse(_width.text) ?? m.widthMm,
      heightMm: double.tryParse(_height.text) ?? m.heightMm,
      bezelMm: double.tryParse(_bezel.text) ?? m.bezelMm,
    ));
  }

  Future<void> _redetect() async {
    setState(() => _detecting = true);
    try {
      final m = widget.metrics;
      final result = await NativeDpiChannel.detect(
        physicalPx: Size(m.activePxWidth, m.activePxHeight),
        devicePixelRatio: m.devicePixelRatio,
        platform: defaultTargetPlatform,
      );
      if (!mounted) return;
      _width.text = result.widthMm.toStringAsFixed(1);
      _height.text = result.heightMm.toStringAsFixed(1);
      widget.onChanged(result.copyWith(bezelMm: m.bezelMm, label: m.label));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _calibrate() async {
    final result = await Navigator.of(context).push<DeviceMetrics>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CardCalibrateScreen(metrics: widget.metrics),
      ),
    );
    if (result == null) return;
    _width.text = result.widthMm.toStringAsFixed(1);
    _height.text = result.heightMm.toStringAsFixed(1);
    widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.straighten, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This screen: ${m.widthMm.toStringAsFixed(0)} × '
                    '${m.heightMm.toStringAsFixed(0)} mm',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Done' : 'Measure'),
                ),
              ],
            ),
            Text(
              '${m.activePxWidth.toInt()} × ${m.activePxHeight.toInt()} px  ·  '
              '${m.dpi.toStringAsFixed(0)} dpi  ·  bezel '
              '${m.bezelMm.toStringAsFixed(1)} mm',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              Text(
                'The board is built in millimetres, so these numbers decide '
                'whether the seam lines up. Measure the lit glass (not the '
                'casing) and the dead border around it.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _detecting ? null : _redetect,
                icon: _detecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.autorenew, size: 18),
                label: const Text('Re-detect automatically'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _field(_width, 'Screen width (mm)')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_height, 'Screen height (mm)')),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _calibrate,
                icon: const Icon(Icons.credit_card, size: 18),
                label: const Text('Auto-calibrate with ID card'),
              ),
              const SizedBox(height: 10),
              _field(_bezel, 'Bezel per edge (mm)'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    onChanged: (_) => _push(),
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    ),
  );
}
