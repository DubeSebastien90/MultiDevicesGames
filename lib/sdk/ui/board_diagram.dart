import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../contract/sim.dart' show PhoneSlice;
import '../layout/board_links.dart';
import '../model/world_rect.dart';
import 'link_palette.dart';
import 'sticker/sticker.dart';

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

  final List<PhoneSlice> slices;

  final WorldRect board;

  final List<EdgeMarker> links;

  final String? meId;

  final Set<String> confirmed;

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

    var left = board.left;
    var top = board.top;
    var right = board.right;
    var bottom = board.bottom;
    for (final s in slices) {
      final b = s.viewport;
      left = math.min(left, b.left);
      top = math.min(top, b.top);
      right = math.max(right, b.right);
      bottom = math.max(bottom, b.bottom);
    }
    final frameWidth = right - left;
    final frameHeight = bottom - top;
    if (frameWidth <= 0 || frameHeight <= 0) return const SizedBox.shrink();

    final cap = maxExtent;

    final picture = AspectRatio(
      aspectRatio: frameWidth / frameHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / frameWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: (board.left - left) * scale,
                top: (board.top - top) * scale,
                width: board.width * scale,
                height: board.height * scale,
                child: DecoratedBox(
                  decoration: St.sticker(
                    radius: math.min(
                      22,
                      math.min(board.width, board.height) * scale * 0.08,
                    ),
                  ),
                ),
              ),
              for (final (i, slice) in slices.indexed)
                _positionedScreen(slice, i, left, top, scale),
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
    final fill = isMe ? St.blue : _otherFill;
    const edge = St.ink;

    return Container(
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: edge, width: 2.5),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          alignment: Alignment.center,
          children: [
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
            Transform.rotate(
              angle: -turnRadians,
              child: SizedBox.fromSize(
                size: _writingBox(context, constraints.biggest),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _name,
                        style: isMe
                            ? _nameStyle.copyWith(color: St.white)
                            : _nameStyle,
                      ),
                      if (label.isNotEmpty)
                        Text(
                          label,
                          style: isMe
                              ? _labelStyle.copyWith(color: St.white)
                              : _labelStyle,
                        ),
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

  String get _name => isMe ? 'YOU' : '${index + 1}';

  static const _otherFill = Color(0xFFFFE4F2);
  static const _radius = 10.0;

  static final _nameStyle = St.display(11, height: 1.1);
  static final _labelStyle = St.body(
    8,
    weight: FontWeight.w700,
    color: St.muted,
  );
  static const _checkSize = 10.0;

  Size _writingBox(BuildContext context, Size chip) {
    final h = math.max(chip.height - _barBand * 2, 1.0);
    final w = math.max(chip.width * _sideAir, 1.0);

    final aspect = _writingAspect(context);
    final c = math.cos(turnRadians).abs();
    final sn = math.sin(turnRadians).abs();

    final b = math.min(w / (aspect * c + sn), h / (aspect * sn + c));
    return Size(aspect * b, b);
  }

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

  static const _barBand = 6.0;

  static const _sideAir = 0.88;
}

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
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 + 2 * 2
      ..strokeCap = StrokeCap.round
      ..color = St.ink;

    for (final link in links) {
      final a = Offset((link.x1 - left) * scale, (link.y1 - top) * scale);
      final b = Offset((link.x2 - left) * scale, (link.y2 - top) * scale);
      stroke.color = link.isJoin
          ? LinkPalette.of(link.colorIndex)
          : LinkPalette.inward;
      canvas.drawLine(a, b, outline);
      canvas.drawLine(a, b, stroke);
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) =>
      old.links != links || old.scale != scale;
}
