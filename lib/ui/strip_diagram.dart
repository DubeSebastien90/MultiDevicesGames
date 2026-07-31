import 'package:flutter/material.dart';

import '../model/arrangement.dart';

/// One phone in the diagram, as drawing it needs it.
class DiagramPhone {
  const DiagramPhone({
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
/// larger looks larger here. This is the whole "put your phone there"
/// instruction in one glance — and since each minigame asks for a different
/// arrangement, the picture is how you know the table has to change.
class ArrangementDiagram extends StatelessWidget {
  const ArrangementDiagram({
    super.key,
    required this.phones,
    this.arrangement = Arrangement.strip,
    this.extent = 84,
  });

  final List<DiagramPhone> phones;
  final Arrangement arrangement;

  /// How much room the drawing gets along its long axis.
  final double extent;

  @override
  Widget build(BuildContext context) {
    if (phones.isEmpty) {
      return SizedBox(
        height: extent,
        child: Center(
          child: Text(
            'No phones yet',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final horizontal = arrangement.isHorizontal;

    // Scale so the whole arrangement fits the space it is given: across the
    // packing axis for a strip, along it for a stack.
    final double unit;
    if (horizontal) {
      final tallestMm =
          phones.map((p) => p.heightMm).reduce((a, b) => a > b ? a : b);
      unit = extent / tallestMm;
    } else {
      final totalMm = phones.fold<double>(0, (sum, p) => sum + p.heightMm);
      // Leave room for the gaps drawn between phones.
      unit = (extent - 4.0 * (phones.length - 1)) / totalMm;
    }

    final chips = <Widget>[
      for (final (i, p) in phones.indexed) ...[
        if (i > 0)
          SizedBox(width: horizontal ? 6 : 0, height: horizontal ? 0 : 4),
        _PhoneChip(
          phone: p,
          width: p.widthMm * unit,
          height: p.heightMm * unit,
          scheme: scheme,
        ),
      ],
    ];

    return SizedBox(
      height: extent,
      child: horizontal
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: chips,
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: chips,
            ),
    );
  }
}

class _PhoneChip extends StatelessWidget {
  const _PhoneChip({
    required this.phone,
    required this.width,
    required this.height,
    required this.scheme,
  });

  final DiagramPhone phone;
  final double width;
  final double height;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final border = !phone.connected
        ? scheme.error
        : phone.isMe
            ? scheme.primary
            : scheme.outlineVariant;

    return SizedBox(
      height: height,
      width: width,
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
              Flexible(
                child: Text(
                  phone.label,
                  style: Theme.of(context).textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
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
