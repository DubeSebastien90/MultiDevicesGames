import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import 'fusebox_config.dart';

class _Cell {
  _Cell({
    required this.index,
    required this.phoneId,
    required this.row,
    required this.col,
    required this.centerX,
    required this.centerY,
    required this.size,
  });

  final int index;
  final String phoneId;
  final int row;
  final int col;
  final double centerX;
  final double centerY;
  final double size;

  bool lit = false;
  final neighbors = <int>[];
}

/// A shared game of Lights Out. Every tap flips its own light and every
/// orthogonal neighbour's; the table wins by going dark together.
///
/// No physics: like Flood and Guac-a-Mole, this is a schedule and a bit of
/// bookkeeping, nothing to integrate. What makes it a puzzle rather than a
/// reflex or memory test is that toggling is entirely deterministic and every
/// move is its own undo — the table can reason its way to the answer, not
/// just react fast enough or remember far enough back.
///
/// Cells are read straight off the compiled board rather than off the plan's
/// own sort, the same principle Push of War's team split and Tandem's
/// neighbour pairing use: [BoardCompiler] sorts every plan into reading order
/// — down the board, then across it — so on a two-row [Layouts.grid] the
/// first half of `context.slices` is the top row, left to right, and the
/// second half is the bottom row, the same way. That is what makes "the cell
/// two along" a real neighbour rather than an artefact of who joined first.
class FuseBoxSim implements GameSim {
  FuseBoxSim(this.context, {math.Random? random})
      : _random = random ?? math.Random() {
    _cells = _buildCells(context.slices);
    _scramble();
  }

  final BoardContext context;
  final math.Random _random;

  late final List<_Cell> _cells;

  double _elapsed = 0;
  int _taps = 0;
  bool _awarded = false;
  GameOutcome? _outcome;

  double get secondsLeft => math.max(0, FuseBoxConfig.roundSeconds - _elapsed);
  int get litCount => _cells.where((c) => c.lit).length;

  // ------------------------------------------------------------------ build

  static List<_Cell> _buildCells(List<PhoneSlice> slices) {
    final cols = slices.length ~/ 2;
    final cells = <_Cell>[
      for (var i = 0; i < slices.length; i++)
        _Cell(
          index: i,
          phoneId: slices[i].phoneId,
          row: i < cols ? 0 : 1,
          col: i % cols,
          centerX: slices[i].viewport.centerX,
          centerY: slices[i].viewport.centerY,
          size: math.min(slices[i].viewport.width, slices[i].viewport.height) *
              FuseBoxConfig.cellSizeFraction,
        ),
    ];

    for (final cell in cells) {
      for (final other in cells) {
        if (identical(cell, other)) continue;
        final horizontal =
            cell.row == other.row && (cell.col - other.col).abs() == 1;
        final vertical = cell.row != other.row && cell.col == other.col;
        if (horizontal || vertical) cell.neighbors.add(other.index);
      }
    }
    return cells;
  }

  /// Flip a cell to a fresh, solvable puzzle. Every toggle here is applied the
  /// same way a tap is, so scrambling and solving are literally the same
  /// operation run in opposite directions.
  void _scramble() {
    void oneMove() =>
        _toggle(_cells[_random.nextInt(_cells.length)].index);

    for (var i = 0; i < FuseBoxConfig.scrambleMoves(_cells.length); i++) {
      oneMove();
    }
    // A random scramble can cancel itself out by chance — vanishingly
    // unlikely at any real board size, but a round that opens already solved
    // is a bug, not a shortcut, so it is guarded explicitly rather than hoped
    // away.
    while (litCount == 0) {
      oneMove();
    }
  }

  void _toggle(int index) {
    final cell = _cells[index];
    cell.lit = !cell.lit;
    for (final n in cell.neighbors) {
      _cells[n].lit = !_cells[n].lit;
    }
  }

  // ------------------------------------------------------------------- step

  @override
  void step(double dt) {
    if (outcome != null) return;
    _elapsed += dt;
  }

  // ------------------------------------------------------------------ input

  /// Tapping anywhere on your own screen trips your light — position-blind,
  /// the same way Flood and Push of War read a tap, because there is only one
  /// light per phone and nothing to aim at.
  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (outcome != null) return;

    final cell = _cellFor(touch.phoneId);
    if (cell == null) return;

    _toggle(cell.index);
    _taps++;

    if (litCount == 0 && !_awarded) {
      _awarded = true;
      context.scores.awardAll(FuseBoxConfig.winBonus);
    }
  }

  _Cell? _cellFor(String phoneId) {
    for (final c in _cells) {
      if (c.phoneId == phoneId) return c;
    }
    return null;
  }

  // -------------------------------------------------------------- entities

  @override
  Iterable<Entity> get entities => [
    for (final c in _cells)
      Entity(
        descriptor: EntityDescriptor(
          id: 'cell${c.index}',
          kind: 'cell',
          props: {'size': c.size},
        ),
        x: c.centerX,
        y: c.centerY,
      ),
  ];

  /// Lit or not, keyed by entity id — small and slow-changing, so it belongs
  /// in shared state rather than in a prop. A cell's position is the one thing
  /// about it that is fixed for the round; on/off is the thing that changes.
  @override
  Map<String, Object?> get sharedState => {
    'lit': {for (final c in _cells) 'cell${c.index}': c.lit},
    'secondsLeft': secondsLeft.ceil(),
    'taps': _taps,
  };

  @override
  GameOutcome? get outcome {
    if (litCount == 0) {
      return _outcome ??=
          GameOutcome.won(summary: 'every light dark, in $_taps taps');
    }
    if (_elapsed >= FuseBoxConfig.roundSeconds) {
      return _outcome ??= GameOutcome.lost(
        summary: '$litCount light${litCount == 1 ? '' : 's'} still lit',
      );
    }
    return null;
  }

  @override
  void reset() {
    for (final c in _cells) {
      c.lit = false;
    }
    _elapsed = 0;
    _taps = 0;
    _awarded = false;
    _outcome = null;
    _scramble();
  }

  @override
  void dispose() {}
}
