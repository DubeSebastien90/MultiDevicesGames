import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/device_metrics.dart';

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
  late final TextEditingController _label;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    final m = widget.metrics;
    _width = TextEditingController(text: m.widthMm.toStringAsFixed(1));
    _height = TextEditingController(text: m.heightMm.toStringAsFixed(1));
    _bezel = TextEditingController(text: m.bezelMm.toStringAsFixed(1));
    _label = TextEditingController(text: m.label);
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _bezel.dispose();
    _label.dispose();
    super.dispose();
  }

  void _push() {
    final m = widget.metrics;
    widget.onChanged(m.copyWith(
      widthMm: double.tryParse(_width.text) ?? m.widthMm,
      heightMm: double.tryParse(_height.text) ?? m.heightMm,
      bezelMm: double.tryParse(_bezel.text) ?? m.bezelMm,
      label: _label.text.trim().isEmpty ? m.label : _label.text.trim(),
    ));
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
              Row(
                children: [
                  Expanded(child: _field(_width, 'Screen width (mm)')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_height, 'Screen height (mm)')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_bezel, 'Bezel per edge (mm)')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _label,
                      onChanged: (_) => _push(),
                      decoration: const InputDecoration(
                        labelText: 'Name this phone',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
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
