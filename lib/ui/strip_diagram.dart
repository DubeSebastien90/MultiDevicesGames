import 'package:flutter/material.dart';

/// One phone in the strip, as the diagram needs it.
class StripPhone {
  const StripPhone({
    required this.label,
    required this.widthMm,
    required this.heightMm,
    required this.isMe,
    this.confirmed = false,
    this.connected = true,
  });

  final String label;
  final double widthMm;
  final double heightMm;
  final bool isMe;
  final bool confirmed;
  final bool connected;
}

/// A to-scale picture of the arrangement the host has in mind.
///
/// Drawn from the real millimetre measurements, so a phone that is physically
/// larger looks larger here. This is the whole "place yourself here" instruction
/// in one glance.
class StripDiagram extends StatelessWidget {
  const StripDiagram({super.key, required this.phones, this.height = 84});

  final List<StripPhone> phones;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (phones.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No phones yet',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final tallestMm = phones.map((p) => p.heightMm).reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, p) in phones.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            _PhoneChip(
              phone: p,
              // Aspect ratio comes from the measurements; the tallest phone
              // fills the row.
              boxHeight: height * (p.heightMm / tallestMm),
              scheme: scheme,
            ),
          ],
        ],
      ),
    );
  }
}

class _PhoneChip extends StatelessWidget {
  const _PhoneChip({
    required this.phone,
    required this.boxHeight,
    required this.scheme,
  });

  final StripPhone phone;
  final double boxHeight;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final aspect = phone.widthMm / phone.heightMm;
    final border = !phone.connected
        ? scheme.error
        : phone.isMe
            ? scheme.primary
            : scheme.outlineVariant;

    return SizedBox(
      height: boxHeight,
      width: boxHeight * aspect,
      child: Container(
        decoration: BoxDecoration(
          color: phone.isMe
              ? scheme.primary.withValues(alpha: 0.18)
              : scheme.surfaceContainerHighest,
          border: Border.all(color: border, width: phone.isMe ? 2 : 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                phone.label,
                style: Theme.of(context).textTheme.labelSmall,
                overflow: TextOverflow.ellipsis,
              ),
              if (phone.confirmed)
                Icon(Icons.check_circle, size: 14, color: scheme.primary),
              if (!phone.connected)
                Icon(Icons.link_off, size: 14, color: scheme.error),
            ],
          ),
        ),
      ),
    );
  }
}
