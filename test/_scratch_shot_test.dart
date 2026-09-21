
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_game.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_game.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/ui/board_diagram.dart';
import 'package:multiscreen_slingshot/sdk/ui/hold_to_confirm.dart';

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

Future<void> shoot(WidgetTester tester, String name, dynamic game, int n) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final lobby = LobbyInfo([for (var i = 1; i <= n; i++) phone('p$i')]);
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final key = GlobalKey();

  await tester.pumpWidget(MaterialApp(
    home: RepaintBoundary(
      key: key,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        body: HoldToConfirm(
          onConfirmed: () {},
          padding: const EdgeInsets.all(36),
          content: Column(
            children: [
              Expanded(
                child: BoardDiagram(
                  slices: board.slices,
                  board: board.board,
                  links: board.links,
                  meId: 'p2',
                  confirmed: const {'p1'},
                  maxExtent: null,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));

  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File(name).writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('row of three', (t) async =>
      shoot(t, 'shot_row.png', const DodgeballGame(), 3));
  testWidgets('ring of five', (t) async =>
      shoot(t, 'shot_ring.png', const HotPotatoGame(), 5));
}
