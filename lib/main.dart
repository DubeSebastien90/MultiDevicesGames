import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sdk/app_controller.dart';
import 'sdk/ui/role_screen.dart';
import 'sdk/ui/session_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Landscape, because the v1 arrangement is a left-to-right strip: phones on
  // their sides make a wide board, and the bird's flight crosses the seam
  // horizontally, which is the thing we are trying to look at.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Edge to edge with no system bars. A status or navigation bar would eat the
  // millimetres right at the screen edge — exactly where the seam is.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MultiscreenApp());
}

class MultiscreenApp extends StatefulWidget {
  const MultiscreenApp({super.key});

  @override
  State<MultiscreenApp> createState() => _MultiscreenAppState();
}

class _MultiscreenAppState extends State<MultiscreenApp> {
  final _controller = AppController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Also what Android shows in the recent-apps switcher.
      title: 'MultiDevicesGame',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4ECDC4),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1020),
      ),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.client == null) {
            return RoleScreen(controller: _controller);
          }
          return SessionScreen(controller: _controller);
        },
      ),
    );
  }
}
