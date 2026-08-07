/// One block of the lobby: a heading, an optional action beside it, and the
/// thing itself.
///
/// The lobby is five of these stacked. Before this widget each one re-declared
/// the same `Card(margin: zero) + Padding(symmetric(vertical: 10, horizontal:
/// 14)) + Row[titleSmall, Spacer, …]` by hand, which is why they had drifted
/// apart — some padded 14 all round, some 10/14, one with an icon before the
/// title and one without.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.accent,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
  });

  /// The heading. Omitted by blocks that speak for themselves — the joined
  /// panel is one line of text and a tick, and a label above it would only say
  /// the same thing twice.
  final String? title;

  /// Drawn in a soft round badge before the title, in [accent].
  final IconData? icon;

  /// Tints the icon badge. Defaults to the brand yellow; the lobby passes a
  /// player colour where the block is about a person.
  final Color? accent;

  /// An action on the heading row — "Measure", "Reset".
  final Widget? trailing;

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = accent ?? AppColors.yellow;
    final hasHeader = title != null || trailing != null;

    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasHeader) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 17, color: AppColors.ink),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  if (title != null)
                    Expanded(
                      child: Text(title!, style: theme.textTheme.titleSmall),
                    )
                  else
                    const Spacer(),
                  ?trailing,
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
