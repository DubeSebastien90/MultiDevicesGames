import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

/// Pre-renders a Lottie animation into a list of [ui.Image] frames that can be
/// drawn directly on a [Canvas].
///
/// Usage:
///   final sprite = LottieSprite();
///   await sprite.load('assets/animations/character.json', width: 128, height: 128);
///   // in render():
///   sprite.draw(canvas, offset, animationTimeMs, worldSize);
class LottieSprite {
  List<ui.Image> _frames = [];
  double _durationMs = 0;
  double _frameInterval = 0;
  bool _loaded = false;
  bool _disposed = false;
  Future<void>? _loading;

  bool get isLoaded => _loaded;
  int get frameCount => _frames.length;
  double get durationMs => _durationMs;

  /// Why the rasterisation failed, if it did. The sprite simply never draws.
  Object? get loadError => _loadError;
  Object? _loadError;

  /// Completes when a [beginLoading] finishes, successfully or not. For tests
  /// that want the frames; nothing in a running game should await it.
  Future<void>? get loading => _loading;

  /// Start rasterising, and hand control straight back.
  ///
  /// **Nothing may await a sprite before drawing.** Rasterising thirty frames
  /// through the engine takes real time and, on some machines, intermittently
  /// never finished at all — and because the client built its view with
  /// `await view.load()`, one stalled sprite left that phone on a screen that
  /// never appeared. Artwork is not allowed to decide whether a game starts, so
  /// this returns immediately and [draw] reports whether it had anything to
  /// paint. A caller that gets `false` draws its fallback and carries on.
  void beginLoading(
    String assetPath, {
    required double width,
    required double height,
    int fps = 30,
  }) {
    if (_loading != null || _loaded || _disposed) return;
    _loading = load(assetPath, width: width, height: height, fps: fps)
        .catchError((Object e) {
      _loadError = e;
    });
  }

  /// Loads a Lottie JSON asset and rasterises every frame at the given pixel
  /// size. [fps] controls how many frames are sampled — higher means smoother
  /// but more memory.
  Future<void> load(
    String assetPath, {
    required double width,
    required double height,
    int fps = 30,
  }) async {
    final data = await rootBundle.loadString(assetPath);
    final bytes = utf8.encode(data);
    final composition = LottieComposition.parseJsonBytes(bytes);

    _durationMs = composition.duration.inMilliseconds.toDouble();
    final totalFrames = (composition.durationFrames * fps / composition.frameRate)
        .round()
        .clamp(1, 300);
    _frameInterval = _durationMs / totalFrames;

    final drawable = LottieDrawable(composition);
    final targetRect = ui.Rect.fromLTWH(0, 0, width, height);
    final frames = <ui.Image>[];

    for (var i = 0; i < totalFrames; i++) {
      final progress = i / totalFrames;
      drawable.setProgress(progress);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, targetRect);

      drawable.draw(canvas, targetRect, fit: BoxFit.contain);

      final picture = recorder.endRecording();
      final image = await picture.toImage(width.toInt(), height.toInt());
      picture.dispose();
      frames.add(image);
    }

    // The round can have moved on while those thirty frames were rasterising.
    // Adopting them now would leak every one of them.
    if (_disposed) {
      for (final img in frames) {
        img.dispose();
      }
      return;
    }

    _frames = frames;
    _loaded = true;
  }

  /// Returns the frame index for a given animation time (looping).
  int frameAt(double timeMs) {
    if (_frames.isEmpty) return 0;
    final looped = timeMs % _durationMs;
    return (looped / _frameInterval).floor().clamp(0, _frames.length - 1);
  }

  /// Draws the sprite on [canvas] centred at [center], scaled so the sprite
  /// fills a [worldSize] x [worldSize] square in world units.
  ///
  /// [timeMs] should be `frame.timeMs` so every phone picks the same frame.
  ///
  /// Returns false when there is nothing to draw yet — still rasterising, or it
  /// failed. Draw your fallback then; do not wait for this to become true.
  bool draw(
    ui.Canvas canvas,
    ui.Offset center,
    double timeMs, {
    required double worldSize,
    double angle = 0,
  }) {
    if (!_loaded || _frames.isEmpty) return false;

    final img = _frames[frameAt(timeMs)];
    final scale = worldSize / img.width;

    canvas
      ..save()
      ..translate(center.dx, center.dy);
    if (angle != 0) canvas.rotate(angle);
    canvas
      ..scale(scale, scale)
      ..drawImage(img, ui.Offset(-img.width / 2, -img.height / 2), ui.Paint())
      ..restore();
    return true;
  }

  /// Draws a specific frame (by index) instead of by time. Same contract as
  /// [draw]: false means there was nothing to paint.
  bool drawFrame(
    ui.Canvas canvas,
    ui.Offset center,
    int frameIndex, {
    required double worldSize,
    double angle = 0,
  }) {
    if (!_loaded || _frames.isEmpty) return false;

    final idx = frameIndex.clamp(0, _frames.length - 1);
    final img = _frames[idx];
    final scale = worldSize / img.width;

    canvas
      ..save()
      ..translate(center.dx, center.dy);
    if (angle != 0) canvas.rotate(angle);
    canvas
      ..scale(scale, scale)
      ..drawImage(img, ui.Offset(-img.width / 2, -img.height / 2), ui.Paint())
      ..restore();
    return true;
  }

  void dispose() {
    _disposed = true;
    for (final img in _frames) {
      img.dispose();
    }
    _frames = [];
    _loaded = false;
  }
}
