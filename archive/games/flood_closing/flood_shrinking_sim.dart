import '../../sdk/contract/sim.dart';
import '../flood_common/flood_board.dart';
import '../flood_common/flood_config.dart';
import '../flood_common/flood_sim.dart';

/// Option B: every tap is worth the same, but the ground keeps closing in.
///
/// The mirror image of option A, and the two overrides say exactly how. The
/// push never changes — mashing feels identical at second forty as at second
/// one — and instead the window the boundary is measured against narrows. A
/// lead that was a third of the way to winning early is the whole way there
/// later, purely because the goalposts moved in.
///
/// That is also what guarantees the round ends: as `rangeScale` falls toward
/// [FloodShrinkingConfig.minScale], any stable lead at all eventually crosses
/// the line.
class FloodShrinkingSim extends FloodSim {
  FloodShrinkingSim(BoardContext context)
      : super(context, FloodBoard.teamsFor(context));

  /// Flat, all round. The whole point of the variant.
  @override
  double pushFor(double atElapsed) => FloodConfig.basePush;

  /// How much contested field is left, 1 down to [FloodShrinkingConfig.minScale].
  double get rangeScale {
    final scale = 1 - roundElapsed / FloodShrinkingConfig.shrinkWindow;
    return scale < FloodShrinkingConfig.minScale
        ? FloodShrinkingConfig.minScale
        : scale;
  }

  /// The raw lead read through the shrinking window, clamped to the axis.
  @override
  double get effectiveBoundary => (boundary / rangeScale).clamp(-1.0, 1.0);

  /// The view draws the narrowing band from this.
  ///
  /// Coarser than it looks, and deliberately. This is the one value in the
  /// game that never settles — the field closes for the whole round whether
  /// anyone taps or not — so the rounding here sets the game's idle packet
  /// rate outright. A hundredth of the field is a fraction of a millimetre of
  /// band movement, well under what the closing edge can show, and it keeps an
  /// untouched board at a handful of messages a second instead of sixty.
  @override
  Map<String, Object?> get extraState => {
    FloodState.rangeScale: (rangeScale * 100).roundToDouble() / 100,
  };
}
