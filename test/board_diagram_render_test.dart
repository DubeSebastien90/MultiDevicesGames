import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_game.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/ui/board_diagram.dart';
import 'package:multiscreen_slingshot/sdk/ui/link_palette.dart';

/// Does the schema actually put every connector on screen?
///
/// The geometry, the wire format and the client are all covered elsewhere and
/// all correct — so if a connector goes missing the only place left is the
/// painting. This renders the real widget and counts coloured pixels, which is
/// the one check that cannot be satisfied by correct data alone.
PhoneSpec phone(String id) => PhoneSpec(
  phoneId: id,
  label: 'phone $id',
  widthMm: 68.58,
  heightMm: 152.4,
  bezelMm: 3,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: 1080,
  activePxHeight: 2400,
);

/// How many pixels of [want] appear in the rendered image, allowing for
/// antialiasing against the background.
int _countCloseTo(ByteData pixels, ui.Color want, {int tolerance = 24}) {
  var hits = 0;
  for (var i = 0; i < pixels.lengthInBytes; i += 4) {
    final r = pixels.getUint8(i);
    final g = pixels.getUint8(i + 1);
    final b = pixels.getUint8(i + 2);
    final a = pixels.getUint8(i + 3);
    if (a < 200) continue;
    final wantR = (want.r * 255).round();
    final wantG = (want.g * 255).round();
    final wantB = (want.b * 255).round();
    if ((r - wantR).abs() <= tolerance &&
        (g - wantG).abs() <= tolerance &&
        (b - wantB).abs() <= tolerance) {
      hits++;
    }
  }
  return hits;
}

void main() {
  testWidgets('the schema draws a connector for every join, in every colour',
      (tester) async {
    final lobby = LobbyInfo([phone('p1'), phone('p2'), phone('p3')]);
    final board =
        const BoardCompiler().compile(const DodgeballGame().planBoard(lobby), lobby);

    // Two joins in a three-phone stack, so two colours.
    expect(board.links.map((l) => l.colorIndex).toSet(), {0, 1});

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0B1020),
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 400,
                height: 400,
                child: BoardDiagram(
                  slices: board.slices,
                  board: board.board,
                  links: board.links,
                  meId: 'p2',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late ByteData pixels;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      pixels = (await image.toByteData())!;
    });

    final red = _countCloseTo(pixels, LinkPalette.of(0));
    final yellow = _countCloseTo(pixels, LinkPalette.of(1));

    expect(red, greaterThan(50), reason: 'the first join did not draw');
    expect(
      yellow,
      greaterThan(50),
      reason: 'the second join did not draw — red drew $red pixels, '
          'yellow drew $yellow',
    );
  });
}
