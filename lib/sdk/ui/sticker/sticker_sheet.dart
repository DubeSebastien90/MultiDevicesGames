import 'package:flutter/material.dart';

import '../../audio/ui_audio.dart';
import 'sticker_tokens.dart';

/// Opens a sticker sheet: ink scrim, and the sheet sliding up 40px as it fades
/// in. A tap on the scrim closes it.
Future<T?> showStickerSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: St.scrim,
    transitionDuration: St.sheet,
    pageBuilder: (ctx, _, _) => SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          // Above the keyboard too: the create-lobby sheet has a text field.
          padding: EdgeInsets.fromLTRB(
            14,
            0,
            14,
            18 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              type: MaterialType.transparency,
              child: builder(ctx),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final c = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      return AnimatedBuilder(
        animation: c,
        builder: (_, _) => Opacity(
          opacity: c.value,
          child: Transform.translate(
            offset: Offset(0, 40 * (1 - c.value)),
            child: child,
          ),
        ),
      );
    },
  );
}

/// The white sheet itself: radius 32, 3px border, hard shadow.
class StickerSheetShell extends StatelessWidget {
  const StickerSheetShell({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: St.sticker(radius: 32, shadow: 7),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(29),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

/// The round white close button in a sheet's corner.
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Close',
    child: GestureDetector(
      onTap: withButtonSound(() => Navigator.of(context).pop()),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: St.white,
          shape: BoxShape.circle,
          border: Border.all(color: St.ink, width: 3),
        ),
        child: const Center(child: StIcon(Symbols.close_rounded, size: 22)),
      ),
    ),
  );
}

/// An ink pill with yellow words that slides up, and leaves after 1.7s.
void showStickerToast(
  BuildContext context,
  String message, {
  double bottom = 40,
}) {
  final overlay = Overlay.of(context);
  final inset = MediaQuery.paddingOf(context).bottom;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 0,
      right: 0,
      bottom: bottom + inset,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - v)),
                child: child,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: St.ink,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(message, style: St.body(15, color: St.bg)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 1700), () {
    if (entry.mounted) entry.remove();
  });
}
