import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../contract/sim.dart' show PhoneSlice;
import '../layout/board_links.dart';
import '../model/world_rect.dart';
import 'link_palette.dart';
import 'sticker/sticker.dart';

/// A to-scale picture of the board the game actually compiled.
///
/// Drawn straight from the compiled screens, so it shows the real order, the
/// real gaps, the real cross-alignment — **and the real angles**. A ring of
/// phones facing outward draws as a ring of turned phones; a row draws as a
/// row. Nothing here knows what shape a board is supposed to be.
///
/// Two earlier versions of this were wrong in instructive ways. The first laid
/// chips out in a `Row` in join order, which broke the moment a game sorted its
/// phones. The second used each screen's bounding box, which is fine until a
/// phone is turned — and then a 72° phone in a circle draws as a fat upright
/// rectangle that looks nothing like the thing on the table.
class BoardDiagram extends StatelessWidget {
  const BoardDiagram({
    super.key,
    required this.slices,
    required this.board,
    this.links = const [],
    this.meId,
    this.confirmed = const {},
    this.maxExtent = 170,
  });

  /// Every screen's place on the board, in board order.
  final List<PhoneSlice> slices;

  /// The playfield, for proportions.
  final WorldRect board;

  /// Every screen's edge stripes — *all* of them, not just this phone's. Seeing
  /// both ends of a red join in the picture is what makes the red line on your
  /// own glass mean something.
  final List<EdgeMarker> links;

  /// Highlighted as "you".
  final String? meId;

  /// Phone ids that have confirmed their position.
  final Set<String> confirmed;

  /// The most room the drawing may take along its longer axis, or null to let
  /// it fill whatever it is given — which is what the placement screen wants,
  /// where the picture *is* the screen.
  final double? maxExtent;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      return SizedBox(
        height: 60,
        child: Center(
          child: Text('No phones yet', style: St.body(14, color: St.muted)),
        ),
      );
    }

    // Frame the union of the playfield and every screen, so a phone sticking
    // out past the board — or a whole ring around it — is never clipped.
    var left = board.left;
    var top = board.top;
    var right = board.right;
    var bottom = board.bottom;
    for (final s in slices) {
      final b = s.viewport; // bounding box: right for framing, not for drawing
      left = math.min(left, b.left);
      top = math.min(top, b.top);
      right = math.max(right, b.right);
      bottom = math.max(bottom, b.bottom);
    }
    final frameWidth = right - left;
    final frameHeight = bottom - top;
    if (frameWidth <= 0 || frameHeight <= 0) return const SizedBox.shrink();

    final cap = maxExtent;

    // [AspectRatio] already takes the largest size its constraints allow, so
    // filling the space is simply a matter of not capping it.
    final picture = AspectRatio(
      aspectRatio: frameWidth / frameHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / frameWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // The playfield, so a screen reaching past it is visible as
              // exactly that.
              Positioned(
                left: (board.left - left) * scale,
                top: (board.top - top) * scale,
                width: board.width * scale,
                height: board.height * scale,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // The playfield in a pale grey, dashed out of the white
                    // page by nothing more than its colour: it is the ground
                    // the phones stand on, not a sticker of its own.
                    color: const Color(0xFFEDEDED),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              for (final (i, slice) in slices.indexed)
                _positionedScreen(slice, i, left, top, scale),
              // Drawn over the screens so a join reads as one band even
              // where two phones nearly touch.
              Positioned.fill(
                child: CustomPaint(
                  painter: _LinkPainter(
                    links: links,
                    left: left,
                    top: top,
                    scale: scale,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return Center(
      child: cap == null
          ? picture
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: frameWidth >= frameHeight ? cap * 2.2 : cap,
                maxHeight: cap,
              ),
              child: picture,
            ),
    );
  }

  /// One screen, drawn at its true size *and its true angle*.
  ///
  /// Positioned by its centre rather than a corner, because a turned rectangle
  /// has no corner worth measuring from — the same reason the layout itself is
  /// centre-based.
  Widget _positionedScreen(
    PhoneSlice slice,
    int index,
    double left,
    double top,
    double scale,
  ) {
    final screen = slice.screen;
    final w = screen.width * scale;
    final h = screen.height * scale;

    return Positioned(
      left: (screen.centerX - left) * scale - w / 2,
      top: (screen.centerY - top) * scale - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: screen.turnRadians,
        child: _Screen(
          index: index,
          label: slice.label,
          isMe: slice.phoneId == meId,
          confirmed: confirmed.contains(slice.phoneId),
          turnRadians: screen.turnRadians,
        ),
      ),
    );
  }
}

class _Screen extends StatelessWidget {
  const _Screen({
    required this.index,
    required this.label,
    required this.isMe,
    required this.confirmed,
    required this.turnRadians,
  });

  final int index;
  final String label;
  final bool isMe;
  final bool confirmed;
  final double turnRadians;

  @override
  Widget build(BuildContext context) {
    // Your own phone is a yellow sticker; everyone else's is white. One colour
    // does the whole job of saying which one you are holding, the way the
    // lobby's own tiles do.
    final fill = isMe ? St.bg : St.white;
    const edge = St.ink;

    return Container(
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: edge, width: isMe ? 2.5 : 1.5),
        borderRadius: BorderRadius.circular(6),
        boxShadow: St.hard(isMe ? 3 : 2),
      ),
      // The chip's own size is the only thing the writing can be measured
      // against, and only the layout knows it.
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          alignment: Alignment.center,
          children: [
            // A bar along the phone's own top edge. With everything turned, this
            // is what tells you which way round to put it down — a rectangle
            // alone cannot say which end is up.
            Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                widthFactor: 0.45,
                child: Container(
                  height: 2.5,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: edge,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Turned back, so the writing stays readable however the phone
            // lies, and grown to fill the room that leaves: [BoxFit.contain]
            // scales up as willingly as down, so one column of text is tiny on
            // an eight-phone board and large on a two-phone one without a
            // single font size being chosen for either. The sizes below are
            // therefore only ratios — the name stays bigger than the label.
            Transform.rotate(
              angle: -turnRadians,
              child: SizedBox.fromSize(
                size: _writingBox(context, constraints.biggest),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_name, style: _nameStyle),
                      if (label.isNotEmpty) Text(label, style: _labelStyle),
                      if (confirmed)
                        const StIcon(
                          Symbols.check_circle_rounded,
                          size: _checkSize,
                          color: St.go,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What this chip is called: YOU, or its place in the board's order.
  String get _name => isMe ? 'YOU' : '${index + 1}';

  static final _nameStyle = St.display(11, height: 1.1);
  static final _labelStyle = St.body(
    8,
    weight: FontWeight.w500,
    color: St.muted,
  );
  static const _checkSize = 10.0;

  /// The largest box the writing may use, measured in the chip's own
  /// coordinates — that is, before it is turned back upright.
  ///
  /// Two things decide it. The writing has a shape of its own — a short wide
  /// block, since the label is longer than it is tall — and forcing the chip's
  /// tall narrow proportions onto it is what kept the type small: the box ran
  /// out of width long before it ran out of height. So the box is cut to the
  /// writing's own aspect instead, measured below.
  ///
  /// Then the turn. The box is rotated by `turnRadians` with respect to the
  /// chip, so it fits only while `a*|cos| + b*|sin|` is within the chip's width
  /// and `a*|sin| + b*|cos|` within its height. With `a = aspect * b` both
  /// collapse to a bound on `b`, and the smaller bound is the answer —
  /// exactly, not by guesswork, and at no turn it simply fills the width.
  Size _writingBox(BuildContext context, Size chip) {
    // Room for the top-edge bar, taken off both ends so the writing stays
    // optically centred rather than pushed down.
    final h = math.max(chip.height - _barBand * 2, 1.0);
    final w = math.max(chip.width * _sideAir, 1.0);

    final aspect = _writingAspect(context);
    final c = math.cos(turnRadians).abs();
    final sn = math.sin(turnRadians).abs();

    final b = math.min(w / (aspect * c + sn), h / (aspect * sn + c));
    return Size(aspect * b, b);
  }

  /// How wide the writing is per unit of height, at whatever size it ends up
  /// being set — a pure shape, which is all the box above needs.
  ///
  /// Measured rather than assumed: the label is a name somebody typed, and a
  /// guessed aspect would either waste half the chip or let the writing spill
  /// over its edge. [FittedBox] still has the last word, so a measurement a
  /// pixel out costs a pixel of margin and nothing worse.
  double _writingAspect(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);

    Size measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      return painter.size;
    }

    final name = measure(_name, _nameStyle);
    final labelSize = label.isEmpty ? Size.zero : measure(label, _labelStyle);
    final check = confirmed ? _checkSize : 0.0;

    final width = math.max(math.max(name.width, labelSize.width), check);
    final height = name.height + labelSize.height + check;
    if (width <= 0 || height <= 0) return 1;
    return width / height;
  }

  /// The strip at the top and bottom the writing keeps clear of, so it never
  /// runs into the bar marking which end is up.
  static const _barBand = 6.0;

  /// How much of the chip's width the writing may take, so a word does not end
  /// flush against the border.
  static const _sideAir = 0.88;
}

/// The edge stripes, in the schema's own little coordinate space.
class _LinkPainter extends CustomPainter {
  _LinkPainter({
    required this.links,
    required this.left,
    required this.top,
    required this.scale,
  });

  final List<EdgeMarker> links;
  final double left;
  final double top;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    // Twice the old weight, in step with the bands drawn along the real glass
    // edges: the picture and the phone say the same thing at the same volume.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    for (final link in links) {
      stroke.color = link.isJoin
          ? LinkPalette.of(link.colorIndex)
          : LinkPalette.inward;
      canvas.drawLine(
        Offset((link.x1 - left) * scale, (link.y1 - top) * scale),
        Offset((link.x2 - left) * scale, (link.y2 - top) * scale),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) =>
      old.links != links || old.scale != scale;
}
