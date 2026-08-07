/// Something went wrong, or is about to.
///
/// There were three byte-identical copies of this before it existed — the
/// landscape warning and the error banner on the menu, and the plan-error
/// banner in the lobby. Each carried its own icon and its own dismiss button
/// and otherwise agreed exactly, so the only thing three copies bought was
/// three places to forget to restyle.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.message,
    this.onDismiss,
  });

  final IconData icon;
  final String message;

  /// Null for a condition the player cannot dismiss because it is still true —
  /// the landscape warning goes away by turning the phone, not by tapping.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(14, 12, onDismiss == null ? 14 : 6, 12),
      decoration: BoxDecoration(
        color: AppColors.dangerSurface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.danger, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF7F1D1D),
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
            ),
        ],
      ),
    );
  }
}
