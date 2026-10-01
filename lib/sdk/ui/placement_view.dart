import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../platform_config.dart';
import '../model/phone_layout.dart';
import '../contract/sim.dart' show PhoneSlice;
import '../layout/board_links.dart';
import 'board_diagram.dart';
import 'hold_to_confirm.dart';
import 'link_palette.dart';
import 'sticker/sticker.dart';

const double kEdgeStripeWidth = 18.0;

class PlacementView extends StatelessWidget {
  const PlacementView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;
    final layout = client.layout;

    if (layout == null || client.slices.isEmpty) {
      return const StickerLoadingScreen();
    }

    final confirmedIds = <String>{
      for (final p in client.lobbyPhones)
        if ((p['confirmed'] as bool?) ?? false) p['phoneId'] as String,
    };

    final diagram = BoardDiagram(
      slices: client.slices,
      board: layout.board,
      links: client.allLinks,
      meId: client.phoneId,
      confirmed: confirmedIds,
      maxExtent: null,
    );

    final legend = client.myLinks.isEmpty
        ? null
        : _LinkLegend(
            links: client.myLinks,
            slices: client.slices,
            onPoke: client.poke,
          );

    return Scaffold(
      backgroundColor: St.bg,
      body: StickerBackground(
        shapes: homeShapes,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _EdgeStripePainter(
                  layout: layout,
                  links: client.myLinks,
                ),
              ),
            ),
            HoldToConfirm(
              confirmed: confirmedIds.contains(client.phoneId),
              onConfirmed: client.confirmPlacement,
              audio: client.audio,
              padding: const EdgeInsets.all(kEdgeStripeWidth * 2),
              content: diagram,
              footer: legend,
            ),
            if (PlatformConfig.showDevChrome)
              Positioned(
                right: 4,
                bottom: 4,
                child: SafeArea(
                  child: TextButton(
                    onPressed: controller.leave,
                    child: Text('Leave', style: St.body(14)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EdgeStripePainter extends CustomPainter {
  _EdgeStripePainter({required this.layout, required this.links});

  final PhoneLayout layout;

  final List<EdgeMarker> links;

  @override
  void paint(Canvas canvas, Size size) {
    Offset toScreen(double wx, double wy) {
      final px = layout.worldToPhysicalPx(wx, wy);
      final dpr = layout.devicePixelRatio;
      return Offset(px.x / dpr, px.y / dpr);
    }

    final stripe = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kEdgeStripeWidth
      ..strokeCap = StrokeCap.round;

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kEdgeStripeWidth + _rim * 2
      ..strokeCap = StrokeCap.round
      ..color = St.ink;

    for (final link in links) {
      final a = toScreen(link.x1, link.y1);
      final b = toScreen(link.x2, link.y2);

      final inset = _towardCentre(a, b, size, kEdgeStripeWidth / 2);
      stripe.color = link.isJoin
          ? LinkPalette.of(link.colorIndex)
          : LinkPalette.inward;
      canvas.drawLine(a + inset, b + inset, outline);
      canvas.drawLine(a + inset, b + inset, stripe);
    }
  }

  static const _rim = 3.0;

  Offset _towardCentre(Offset a, Offset b, Size size, double by) {
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final to = Offset(size.width / 2 - mid.dx, size.height / 2 - mid.dy);
    final len = to.distance;
    return len < 1e-6 ? Offset.zero : to / len * by;
  }

  @override
  bool shouldRepaint(_EdgeStripePainter old) =>
      old.layout != layout || old.links != links;
}

class _LinkLegend extends StatelessWidget {
  const _LinkLegend({
    required this.links,
    required this.slices,
    required this.onPoke,
  });

  final List<EdgeMarker> links;
  final List<PhoneSlice> slices;
  final ValueChanged<String> onPoke;

  int? _positionOf(String phoneId) {
    for (final (i, s) in slices.indexed) {
      if (s.phoneId == phoneId) return i + 1;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final link in links)
          _LinkChip(
            color: link.isJoin
                ? LinkPalette.of(link.colorIndex)
                : LinkPalette.inward,
            label: link.partnerId == null
                ? 'The middle'
                : 'Phone ${_positionOf(link.partnerId!) ?? "?"}',
            onPoke: link.partnerId == null
                ? null
                : () => onPoke(link.partnerId!),
          ),
      ],
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.color,
    required this.label,
    required this.onPoke,
  });

  final Color color;
  final String label;
  final VoidCallback? onPoke;

  static const _padding = EdgeInsets.symmetric(horizontal: 16, vertical: 9);

  @override
  Widget build(BuildContext context) {
    final poke = onPoke;
    final words = Text(label, style: St.display(17, height: 1.1));

    if (poke == null) {
      return DecoratedBox(
        decoration: St.sticker(color: color, radius: 999, shadow: 3),
        child: Padding(padding: _padding, child: words),
      );
    }

    return StickerButton(
      color: color,
      radius: 999,
      shadow: 3,
      padding: _padding,
      onTap: poke,
      child: words,
    );
  }
}
