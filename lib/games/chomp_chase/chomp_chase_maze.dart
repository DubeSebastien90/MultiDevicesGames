import 'dart:math' as math;
import 'dart:typed_data';

/// A maze of corridors, one tile wide, with walls between tiles rather than
/// walls *as* tiles — so a board a few centimetres deep still has room for
/// real corridors.
///
/// It is built mirrored across both middles of the board. The two teams start
/// on opposite halves, so each gets exactly the other's maze; and there are no
/// dead ends, because a chase with a dead end in it is decided by whoever runs
/// into it first.
class ChompMaze {
  ChompMaze._(this.cols, this.rows, this._right, this._down);

  final int cols;
  final int rows;

  /// Whether the way from tile (c, r) to (c + 1, r) is open, and to (c, r + 1).
  final Uint8List _right;
  final Uint8List _down;

  int get tiles => cols * rows;

  /// Build one on a [cols] by [rows] grid.
  ///
  /// [extraLoops] is the share of the remaining walls knocked through on top
  /// of what removing the dead ends needs, for more than one way round.
  factory ChompMaze.generate(
    int cols,
    int rows,
    math.Random random, {
    double extraLoops = 0.12,
  }) {
    final maze = ChompMaze._(
      cols,
      rows,
      Uint8List(cols * rows),
      Uint8List(cols * rows),
    );
    maze._carve(random, extraLoops);
    return maze;
  }

  /// Rebuild one from [encode]'s output, on a phone.
  factory ChompMaze.decode(String code) {
    final parts = code.split(':');
    final cols = int.parse(parts[0]);
    final rows = int.parse(parts[1]);
    final bits = parts[2];
    final right = Uint8List(cols * rows);
    final down = Uint8List(cols * rows);
    for (var k = 0; k < cols * rows; k++) {
      final nibble = int.parse(bits[k], radix: 4);
      right[k] = nibble & 1;
      down[k] = (nibble >> 1) & 1;
    }
    return ChompMaze._(cols, rows, right, down);
  }

  /// The maze as one short string: its size, then a digit per tile saying
  /// which of its right and lower walls are open.
  String encode() {
    final out = StringBuffer('$cols:$rows:');
    for (var k = 0; k < tiles; k++) {
      out.write(_right[k] | (_down[k] << 1));
    }
    return out.toString();
  }

  // -- asking about it --------------------------------------------------------

  /// Whether a walker on (c, r) can step one tile in direction ([dc], [dr]).
  bool open(int c, int r, int dc, int dr) {
    if (dc == 1) return c < cols - 1 && _right[r * cols + c] == 1;
    if (dc == -1) return c > 0 && _right[r * cols + c - 1] == 1;
    if (dr == 1) return r < rows - 1 && _down[r * cols + c] == 1;
    if (dr == -1) return r > 0 && _down[(r - 1) * cols + c] == 1;
    return false;
  }

  /// How many ways out of (c, r).
  int exits(int c, int r) =>
      (open(c, r, 1, 0) ? 1 : 0) +
      (open(c, r, -1, 0) ? 1 : 0) +
      (open(c, r, 0, 1) ? 1 : 0) +
      (open(c, r, 0, -1) ? 1 : 0);

  /// How many tiles can be reached from (c, r) — all of them, in a good maze.
  int reachableFrom(int c, int r) {
    final seen = Uint8List(tiles);
    final queue = <int>[r * cols + c];
    seen[r * cols + c] = 1;
    for (var head = 0; head < queue.length; head++) {
      final k = queue[head];
      final kc = k % cols;
      final kr = k ~/ cols;
      for (final (dc, dr) in _steps) {
        if (!open(kc, kr, dc, dr)) continue;
        final n = (kr + dr) * cols + kc + dc;
        if (seen[n] == 1) continue;
        seen[n] = 1;
        queue.add(n);
      }
    }
    return queue.length;
  }

  static const _steps = [(1, 0), (-1, 0), (0, 1), (0, -1)];

  // -- building it ------------------------------------------------------------

  /// Open the wall from (c, r) in direction (dc, dr), and the same wall in all
  /// four mirror images.
  void _openMirrored(int c, int r, int dc, int dr) {
    for (final mx in [false, true]) {
      for (final my in [false, true]) {
        var ac = c, ar = r, bc = c + dc, br = r + dr;
        if (mx) {
          ac = cols - 1 - ac;
          bc = cols - 1 - bc;
        }
        if (my) {
          ar = rows - 1 - ar;
          br = rows - 1 - br;
        }
        _openBetween(ac, ar, bc, br);
      }
    }
  }

  void _openBetween(int ac, int ar, int bc, int br) {
    if (ac == bc && ar == br) return;
    if (ar == br) {
      final c = math.min(ac, bc);
      _right[ar * cols + c] = 1;
    } else {
      final r = math.min(ar, br);
      _down[r * cols + ac] = 1;
    }
  }

  void _carve(math.Random random, double extraLoops) {
    // A quarter of the board, middles included: everything else is a
    // reflection of it.
    final qc = (cols + 1) ~/ 2;
    final qr = (rows + 1) ~/ 2;
    bool inQuarter(int c, int r) => c >= 0 && r >= 0 && c < qc && r < qr;

    // A spanning tree of the quarter, depth first, so the corridors run long.
    final visited = Uint8List(qc * qr);
    final stack = <(int, int)>[(0, 0)];
    visited[0] = 1;
    while (stack.isNotEmpty) {
      final (c, r) = stack.last;
      final options = [
        for (final (dc, dr) in _steps)
          if (inQuarter(c + dc, r + dr) && visited[(r + dr) * qc + c + dc] == 0)
            (dc, dr),
      ];
      if (options.isEmpty) {
        stack.removeLast();
        continue;
      }
      final (dc, dr) = options[random.nextInt(options.length)];
      _openMirrored(c, r, dc, dr);
      visited[(r + dr) * qc + c + dc] = 1;
      stack.add((c + dc, r + dr));
    }

    // An even width or height has no shared middle to hold the halves
    // together, so knock a few doorways through the middle wall.
    if (cols.isEven) {
      for (var r = 0; r < qr; r++) {
        if (r == 0 || random.nextDouble() < 0.35) _openMirrored(qc - 1, r, 1, 0);
      }
    }
    if (rows.isEven) {
      for (var c = 0; c < qc; c++) {
        if (c == 0 || random.nextDouble() < 0.35) _openMirrored(c, qr - 1, 0, 1);
      }
    }

    // No dead ends: every tile with one way out gets a second.
    for (var r = 0; r < qr; r++) {
      for (var c = 0; c < qc; c++) {
        if (exits(c, r) > 1) continue;
        final closed = [
          for (final (dc, dr) in _steps)
            if (_inBoard(c + dc, r + dr) && !open(c, r, dc, dr)) (dc, dr),
        ];
        if (closed.isEmpty) continue;
        final (dc, dr) = closed[random.nextInt(closed.length)];
        _openMirrored(c, r, dc, dr);
      }
    }

    // And a few more loops, so there is always another way round.
    for (var r = 0; r < qr; r++) {
      for (var c = 0; c < qc; c++) {
        for (final (dc, dr) in const [(1, 0), (0, 1)]) {
          if (!_inBoard(c + dc, r + dr) || open(c, r, dc, dr)) continue;
          if (random.nextDouble() < extraLoops) _openMirrored(c, r, dc, dr);
        }
      }
    }
  }

  bool _inBoard(int c, int r) => c >= 0 && r >= 0 && c < cols && r < rows;
}
