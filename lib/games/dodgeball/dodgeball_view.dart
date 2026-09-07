import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:rive/rive.dart' as rive;

import '../../sdk/contract/view.dart';
import '../../sdk/model/player.dart';
import '../../sdk/ui/intro_animation.dart';
import 'dodgeball_config.dart';

/// Renders the dodgeball game: players, bouncing balls, dash effects, and
/// countdown/game-over overlays.
class DodgeballView extends GameView {
  DodgeballView({required this.phoneId, this.roster = Roster.empty});

  final String phoneId;

  /// Everyone in the round, for their platform colour. The sim ships a colour
  /// of its own on the entity, but the one a player recognises across the table
  /// is the one the lobby gave them.
  final Roster roster;

  static const _floorColor = Color(0xFF161B22);
  static const _ballColor = Color(0xFFFF4444);
  static const _ballGlowColor = Color(0x44FF4444);

  /// The walking character that stands in for the player's body.
  ///
  /// `UpView_SM` is a single looping `Walk` with no inputs, so standing still
  /// is not a state the file can be asked for — it is simply the machine not
  /// being advanced. That is why every player needs their own artboard: they
  /// stop and start independently, and one shared instance can only be walking
  /// or frozen for everybody at once.
  static const _characterAsset = 'assets/sdk/animations/bottomDownView.riv';
  static const _characterStateMachine = 'UpView_SM';

  /// World units per second below which a player counts as standing still.
  ///
  /// Not zero: positions are interpolated, so a stationary player still jitters
  /// by a hair between frames and an exact test would flicker the walk on and
  /// off.
  static const _walkingSpeed = 0.5;

  /// Which way the character is drawn, in the same convention as `angle`:
  /// 0 is +x, `pi / 2` is down the screen — which is how this one is drawn,
  /// despite the artboard being called `UpView_Artboard`. Everything is rotated
  /// by the difference between where the player is heading and this.
  static const _characterFacing = math.pi / 2;

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  rive.File? _riveFile;

  /// One artboard + state machine per player entity, made on first sight.
  final _characters = <String, _Character>{};

  /// Where each player was last frame, to tell walking from standing.
  final _lastSeen = <String, Offset>{};

  @override
  Future<void> load() async {
    // Same gate as the intro: on a platform where `rive_native` takes the
    // process down there is nothing to catch, so do not even load.
    if (!IntroAnimation.available) return;
    try {
      final file = await rive.File.asset(
        _characterAsset,
        riveFactory: rive.Factory.flutter,
      );
      if (file == null) throw StateError('not found');
      _riveFile = file;
    } on Object catch (e) {
      // Falls back to the sphere. A missing character is a uglier game, not a
      // broken one.
      debugPrint('[dodgeball] $_characterAsset did not load: $e');
    }
  }

  /// The character for one player, or null while the file is missing.
  ///
  /// Made once and kept: [color] is written into the artboard here, at birth,
  /// and a player's colour does not change for the length of a round.
  _Character? _characterFor(String id, Color color) {
    final existing = _characters[id];
    if (existing != null) return existing;
    final file = _riveFile;
    if (file == null) return null;
    try {
      // `frameOrigin: true` puts the artboard's top-left at (0, 0) — the
      // centring is done by hand at draw time, which is the only version of it
      // that behaves the same on every runtime.
      final artboard = file.defaultArtboard(frameOrigin: true);
      if (artboard == null) throw StateError('no artboard');
      final sm = artboard.stateMachine(_characterStateMachine) ??
          artboard.defaultStateMachine();
      _paint(file, artboard, sm, color);
      // Once, so the artboard holds the first frame of the walk rather than
      // whatever pose it was exported in.
      sm?.advanceAndApply(0);
      final character = _Character(artboard, sm);
      _characters[id] = character;
      return character;
    } on Object catch (e) {
      debugPrint('[dodgeball] no character for $id: $e');
      return null;
    }
  }

  /// Put a player's colour on their character.
  ///
  /// The property is found by type rather than by name — the file's view model
  /// carries exactly one colour — so renaming `skinOne` in the editor costs
  /// nothing here. Never fatal: a file exported without its view model means
  /// eight characters in the colour they were drawn, which is a duller game
  /// rather than a broken one, and the log line is the only way anybody would
  /// know why.
  void _paint(
    rive.File file,
    rive.Artboard artboard,
    rive.StateMachine? stateMachine,
    Color color,
  ) {
    try {
      final viewModel = file.defaultArtboardViewModel(artboard);
      final instance = viewModel?.createDefaultInstance();
      if (viewModel == null || instance == null) {
        debugPrint('[dodgeball] $_characterAsset has no view model — '
            'characters keep the colour they were drawn');
        return;
      }
      artboard.bindViewModelInstance(instance);
      stateMachine?.bindViewModelInstance(instance);
      for (final property in viewModel.properties) {
        if (property.type != rive.DataType.color) continue;
        instance.color(property.name)?.value = color;
        return;
      }
      debugPrint('[dodgeball] no colour property on ${viewModel.name}');
    } on Object catch (e) {
      debugPrint('[dodgeball] could not colour the character: $e');
    }
  }

  @override
  void dispose() {
    _characters.clear();
    _lastSeen.clear();
    _riveFile?.dispose();
    _riveFile = null;
    super.dispose();
  }

  @override
  void render(Canvas canvas, Frame frame) {
    // Floor, over the whole panel — see the note in `ArenaView`. Painting it
    // over `frame.board` left the far end of the biggest screen showing as a
    // differently coloured band that players were fenced out of; the sim keeps
    // them inside the screens themselves now, so every point this phone can
    // draw is playable.
    _fill.color = _floorColor;
    final view = frame.visible;
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );

    // Draw balls.
    for (final e in frame.ofKind('ball')) {
      final radius = e.propDouble('radius', DodgeballConfig.ballRadius);

      // Glow.
      _fill.color = _ballGlowColor;
      canvas.drawCircle(Offset(e.x, e.y), radius * 2.0, _fill);

      // Ball body.
      _fill.color = _ballColor;
      canvas.drawCircle(Offset(e.x, e.y), radius, _fill);

      // Highlight.
      _fill.color = const Color(0x66FFFFFF);
      canvas.drawCircle(
        Offset(e.x - radius * 0.25, e.y - radius * 0.25),
        radius * 0.3,
        _fill,
      );
    }

    // Draw players.
    for (final e in frame.ofKind('player')) {
      final idx = e.propInt('index');
      final key = 'p$idx';
      // The platform's colour for whoever is in this seat, which is the one
      // they were shown in the lobby. The sim's own palette is the fallback,
      // for a seat nobody is sitting in yet.
      final phone = frame.sharedState['phoneId_$key'] as String?;
      final seated = phone == null ? null : roster.byPhone(phone);
      final color =
          seated?.color.value ?? Color(e.propInt('color', 0xFFFFFFFF));
      final radius = e.propDouble('radius', DodgeballConfig.characterRadius);
      final alive = frame.sharedState['alive_$key'] == true;
      if (!alive) continue;

      final isDashing = frame.sharedState['dashing_$key'] == true;
      final isInvincible = frame.sharedState['invincible_$key'] == true;

      // Invincibility / dash shimmer.
      if (isInvincible) {
        final pulse = 0.5 + 0.5 * math.sin(frame.timeMs / 60);
        _stroke
          ..color = Color.fromARGB((pulse * 220).toInt(), 255, 255, 255)
          ..strokeWidth = radius * 0.18;
        canvas.drawCircle(Offset(e.x, e.y), radius * 1.4, _stroke);
      }

      // Dash trail.
      if (isDashing) {
        _fill.color = color.withAlpha(60);
        final trailDx = -math.cos(e.angle) * radius * 1.5;
        final trailDy = -math.sin(e.angle) * radius * 1.5;
        canvas.drawCircle(
          Offset(e.x + trailDx, e.y + trailDy),
          radius * 0.7,
          _fill,
        );
        canvas.drawCircle(
          Offset(e.x + trailDx * 2, e.y + trailDy * 2),
          radius * 0.4,
          _fill,
        );
      }

      // Player body: the walking character, or the old sphere when the file
      // is not there.
      final character = _characterFor(e.id, color);
      if (character != null) {
        // Walk only while actually moving. With no input on the state machine,
        // 'idle' is the machine not being advanced — it holds whatever frame of
        // the cycle the player stopped on.
        final here = Offset(e.x, e.y);
        final before = _lastSeen[e.id];
        _lastSeen[e.id] = here;
        final moving = before != null &&
            frame.dt > 0 &&
            (here - before).distance / frame.dt > _walkingSpeed;
        if (moving) character.stateMachine?.advanceAndApply(frame.dt);

        final bounds = character.artboard.bounds;
        final height = bounds.height;
        final scale = height == 0 ? 1.0 : (radius * 3.0) / height;
        canvas.save();
        canvas.translate(e.x, e.y);
        canvas.rotate(e.angle - _characterFacing);
        canvas.scale(scale);
        // The artboard draws from its top-left, so pull it back by half its
        // size: the player's position is then the middle of the character, and
        // the rotation above turns about that same point.
        canvas.translate(-bounds.width / 2, -bounds.height / 2);
        character.artboard.draw(rive.Renderer.make(canvas));
        canvas.restore();
      } else {
        _fill.color =
            isDashing ? Color.lerp(color, const Color(0xFFFFFFFF), 0.4)! : color;
        canvas.drawCircle(Offset(e.x, e.y), radius, _fill);
      }
    }

    // Countdown overlay.
    if (frame.sharedState['phase'] == 'countdown') {
      final cd = (frame.sharedState['countdown'] as num?)?.toDouble() ?? 0;
      final digit = cd.ceil().toString();
      _drawCenteredText(canvas, frame, digit, frame.board.height * 0.15);
    }

    // Finished overlay.
    if (frame.sharedState['phase'] == 'finished') {
      _drawCenteredText(canvas, frame, 'OUT!', frame.board.height * 0.12);
    }
  }

  void _drawCenteredText(
      Canvas canvas, Frame frame, String text, double fontSize) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
    ))
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFFFFFFFF),
        fontWeight: FontWeight.w900,
      ))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: frame.visible.width));
    canvas.drawParagraph(
      paragraph,
      Offset(
        frame.visible.left,
        frame.visible.top + frame.visible.height / 2 - fontSize / 2,
      ),
    );
  }

  // -- HUD --------------------------------------------------------------------

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final phase = frame.sharedState['phase'] as String?;

    int? myIndex;
    for (var i = 0; i < 8; i++) {
      if (frame.sharedState['phoneId_p$i'] == phoneId) {
        myIndex = i;
        break;
      }
    }
    if (myIndex == null) return null;

    final key = 'p$myIndex';
    final alive = frame.sharedState['alive_$key'] == true;
    final dashCd =
        (frame.sharedState['dashCd_$key'] as num?)?.toDouble() ?? 0;
    final ballCount =
        (frame.sharedState['ballCount'] as num?)?.toInt() ?? 0;

    if (!alive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'ELIMINATED',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFFFF4444),
          ),
        ),
      );
    }

    if (phase == 'countdown') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Drag=Move  Tap=Dash',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFFCCCCCC),
          ),
        ),
      );
    }

    final parts = <Widget>[];

    // Ball count.
    parts.add(Text(
      'Balls: $ballCount',
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Color(0xFFFF6666),
      ),
    ));

    // Dash status.
    if (dashCd > 0) {
      parts.add(Text(
        '  DASH ${dashCd.toStringAsFixed(1)}',
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF999999),
        ),
      ));
    } else {
      parts.add(const Text(
        '  DASH READY',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF44FF44),
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: parts),
    );
  }
}

/// One player's own copy of the walking character.
class _Character {
  _Character(this.artboard, this.stateMachine);

  final rive.Artboard artboard;
  final rive.StateMachine? stateMachine;
}
