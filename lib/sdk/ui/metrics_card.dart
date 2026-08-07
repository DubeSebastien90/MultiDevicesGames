import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/device_metrics.dart';
import 'theme/app_dimens.dart';
import 'widgets/section_card.dart';

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
  });

  final DeviceMetrics metrics;
  final ValueChanged<DeviceMetrics> onChanged;

  @override
  State<MetricsCard> createState() => _MetricsCardState();
}

class _MetricsCardState extends State<MetricsCard> {
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _bezel;
  late final TextEditingController _label;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
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

    return SectionCard(
      icon: Icons.straighten,
      title: 'This screen: ${m.widthMm.toStringAsFixed(0)} × '
          '${m.heightMm.toStringAsFixed(0)} mm',
      trailing: TextButton(
        onPressed: () => setState(() => _expanded = !_expanded),
        child: Text(_expanded ? 'Done' : 'Measure'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${m.activePxWidth.toInt()} × ${m.activePxHeight.toInt()} px  ·  '
            '${m.dpi.toStringAsFixed(0)} dpi  ·  bezel '
            '${m.bezelMm.toStringAsFixed(1)} mm',
            style: theme.textTheme.bodySmall,
          ),
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'The board is built in millimetres, so these numbers decide '
              'whether the seam lines up. Measure the lit glass (not the '
              'casing) and the dead border around it.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: _field(_width, 'Screen width (mm)')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _field(_height, 'Screen height (mm)')),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: _field(_bezel, 'Bezel per edge (mm)')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _label,
                    onChanged: (_) => _push(),
                    decoration: const InputDecoration(
                      labelText: 'Name this phone',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    onChanged: (_) => _push(),
    decoration: InputDecoration(labelText: label),
  );
}
