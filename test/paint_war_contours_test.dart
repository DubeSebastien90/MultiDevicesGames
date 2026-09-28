import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/paint_war/paint_war_contours.dart';

/// A grid [w] cells across from rows of text: a letter is that painter's
/// (`a` is 0), a dot is nobody's.
Int8List grid(List<String> rows) => Int8List.fromList([
  for (final row in rows)
    for (final c in row.codeUnits) c == 46 ? -1 : c - 97,
]);

List<List<(double, double)>> outlinesOf(
  List<String> rows, {
  int owner = 0,
}) => PaintContours.outlines(
  grid(rows),
  owner: owner,
  gw: rows.first.length,
  gx: 0,
  gy: 0,
  cell: 1,
);

double area(List<(double, double)> loop) {
  var sum = 0.0;
  for (var k = 0; k < loop.length; k++) {
    final (x0, y0) = loop[k];
    final (x1, y1) = loop[(k + 1) % loop.length];
    sum += x0 * y1 - x1 * y0;
  }
  return sum.abs() / 2;
}

({double left, double top, double right, double bottom}) boundsOf(
  List<(double, double)> loop,
) {
  var l = double.infinity, t = double.infinity;
  var r = -double.infinity, b = -double.infinity;
  for (final (x, y) in loop) {
    if (x < l) l = x;
    if (y < t) t = y;
    if (x > r) r = x;
    if (y > b) b = y;
  }
  return (left: l, top: t, right: r, bottom: b);
}

void main() {
  test('decodes the sim\'s runs back into a grid of owners', () {
    final owners = PaintContours.decode('.3a2.1b4');
    expect(owners, [-1, -1, -1, 0, 0, -1, 1, 1, 1, 1]);
  });

  test('nobody\'s paint has no outline', () {
    expect(outlinesOf(['....', '....']), isEmpty);
  });

  test('a block of paint is one smooth loop the size of the block', () {
    final loops = outlinesOf([
      '..........',
      '..aaaaaa..',
      '..aaaaaa..',
      '..aaaaaa..',
      '..aaaaaa..',
      '..........',
    ]);
    expect(loops, hasLength(1));

    // The block covers x 2..8 and y 1..5. The outline runs through the middle
    // of the edge cells' sides and is rounded off at the corners, so it sits
    // within a cell of that, and keeps most of the area.
    final b = boundsOf(loops.single);
    expect(b.left, closeTo(2, 1));
    expect(b.right, closeTo(8, 1));
    expect(b.top, closeTo(1, 1));
    expect(b.bottom, closeTo(5, 1));
    expect(area(loops.single), greaterThan(24 * 0.75));
    expect(area(loops.single), lessThan(24 * 1.05));

    // More than the four corners of a box: it is smooth.
    expect(loops.single.length, greaterThan(16));
  });

  test('a hole is its own loop, so it can be filled even-odd', () {
    final loops = outlinesOf([
      '.........',
      '.aaaaaaa.',
      '.aaaaaaa.',
      '.aa...aa.',
      '.aa...aa.',
      '.aa...aa.',
      '.aaaaaaa.',
      '.aaaaaaa.',
      '.........',
    ]);
    expect(loops, hasLength(2));
    final areas = loops.map(area).toList()..sort();
    expect(areas.first, lessThan(areas.last / 3), reason: 'the hole');
  });

  test('another painter\'s paint is not this one\'s', () {
    final rows = ['.......', '.aa.bb.', '.aa.bb.', '.......'];
    expect(outlinesOf(rows, owner: 0), hasLength(1));
    expect(outlinesOf(rows, owner: 1), hasLength(1));
    expect(
      boundsOf(outlinesOf(rows, owner: 0).single).right,
      lessThan(boundsOf(outlinesOf(rows, owner: 1).single).left),
    );
  });

  test('two territories side by side meet on the same line', () {
    // a's right edge and b's left edge are both halfway between columns 3
    // and 4 before any smoothing. Smoothing may bow them a little, but never
    // apart: no strip of paper between two territories.
    final rows = [
      '..........',
      '.aaabbbbb.',
      '.aaabbbbb.',
      '.aaabbbbb.',
      '.aaabbbbb.',
      '.aaabbbbb.',
      '..........',
    ];
    final a = boundsOf(outlinesOf(rows, owner: 0).single);
    final b = boundsOf(outlinesOf(rows, owner: 1).single);
    expect(a.right, closeTo(4, 0.3));
    expect(b.left, closeTo(4, 0.3));
    expect(a.right, greaterThanOrEqualTo(b.left - 0.05));
  });

  test('cells touching only at a corner are kept apart', () {
    final loops = outlinesOf([
      '......',
      '.aa...',
      '.aa...',
      '...aa.',
      '...aa.',
      '......',
    ]);
    expect(loops, hasLength(2));
  });

  test('paint against the edge of the board is outlined along it', () {
    final loops = outlinesOf(['aaa..', 'aaa..', 'aaa..']);
    expect(loops, hasLength(1));
    final b = boundsOf(loops.single);
    expect(b.left, closeTo(0, 0.6));
    expect(b.top, closeTo(0, 0.6));
  });

  test("smoothing keeps a real territory's size", () {
    // A spawn-sized circle: eight cells across its radius.
    const r = 8;
    final rows = [
      for (var j = -r - 2; j <= r + 2; j++)
        String.fromCharCodes([
          for (var i = -r - 2; i <= r + 2; i++)
            i * i + j * j <= r * r ? 97 : 46,
        ]),
    ];
    final cells = rows.join().codeUnits.where((c) => c == 97).length;
    final loops = outlinesOf(rows);
    expect(loops, hasLength(1));
    expect(area(loops.single), closeTo(cells, cells * 0.05));
  });
}
