import 'package:flutter/material.dart';

import '../model/name_drop_status.dart';
import '../platform/name_drop_support.dart';
import 'sticker/sticker.dart';

class NameDropGate extends StatefulWidget {
  const NameDropGate({super.key, required this.child});

  final Widget child;

  @override
  State<NameDropGate> createState() => _NameDropGateState();
}

class _NameDropGateState extends State<NameDropGate> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  Future<void> _maybeAsk() async {
    if (!await NameDropSupport.onThisDevice()) return;
    if (await NameDropPref.load() != NameDropStatus.waiting) return;
    if (!mounted) return;

    final answer = await showNameDropNotice(context);

    if (answer != NameDropStatus.waiting) await NameDropPref.save(answer);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<NameDropStatus> showNameDropNotice(BuildContext context) async {
  final answer = await showDialog<NameDropStatus>(
    context: context,
    barrierDismissible: false,
    useSafeArea: false,
    builder: (_) => const _NameDropNotice(),
  );

  return answer ?? NameDropStatus.waiting;
}

const _settingName = {
  'en': 'Bringing Devices Together',
  'fr': 'Rapprochement des appareils',
  'es': 'Acercar dispositivos',
  'de': 'Geräte zusammenführen',
};

const _pathNames = {
  'en': ['Settings', 'General', 'AirDrop'],
  'fr': ['Réglages', 'Général', 'AirDrop'],
  'es': ['Ajustes', 'General', 'AirDrop'],
  'de': ['Einstellungen', 'Allgemein', 'AirDrop'],
};

String _localised(Map<String, dynamic> table, BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  return (table[code] ?? table['en']!) as String;
}

List<String> _path(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  return (_pathNames[code] ?? _pathNames['en']!).cast<String>();
}

class _NameDropNotice extends StatelessWidget {
  const _NameDropNotice();

  @override
  Widget build(BuildContext context) {
    final setting = _localised(_settingName, context);

    return Dialog.fullscreen(
      backgroundColor: St.bg,
      child: StickerBackground(
        shapes: lobbyShapes,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: StickerMark(
                        icon: Symbols.contact_page_rounded,
                        color: St.blue,
                        size: 72,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'One thing before you play',
                      textAlign: TextAlign.center,
                      style: St.display(30, height: 1.05),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'This game puts phones edge to edge. When the tops of two '
                      'iPhones touch, iOS pops up a card offering to share your '
                      'contact details — over the game, mid-round.',
                      style: St.body(
                        16,
                        weight: FontWeight.w500,
                        color: St.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Turning off “$setting” stops it.',
                      style: St.body(17, weight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    StickerWideButton(
                      onTap: () =>
                          Navigator.of(context).pop(NameDropStatus.turnedOff),
                      label: 'Already done',
                      height: 54,
                      fontSize: 20,
                      icon: Symbols.check_rounded,
                      color: St.go,
                      textColor: St.white,
                    ),
                    const SizedBox(height: 12),
                    StickerWideButton(
                      onTap: () => _showHow(context),
                      label: 'How?',
                      height: 54,
                      fontSize: 20,
                      icon: Symbols.help_rounded,
                      color: St.premium,
                      textColor: St.white,
                    ),
                    const SizedBox(height: 12),
                    StickerWideButton(
                      onTap: () =>
                          Navigator.of(context).pop(NameDropStatus.declined),
                      label: 'No thanks',
                      height: 54,
                      fontSize: 20,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Either way, this is the last you’ll hear of it.',
                      style: St.body(
                        14,
                        weight: FontWeight.w500,
                        color: St.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHow(BuildContext context) async {
    final done = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const _HowScreen()));
    if (done == true && context.mounted) {
      Navigator.of(context).pop(NameDropStatus.turnedOff);
    }
  }
}

const _cropAlignment = [-1.0, 0.75, 1.0, 0.45];

class _HowScreen extends StatelessWidget {
  const _HowScreen();

  static const _shots = [
    'step_1_settings',
    'step_2_general',
    'step_3_airdrop',
    'step_4_toggle',
  ];

  @override
  Widget build(BuildContext context) {
    final path = _path(context);
    final setting = _localised(_settingName, context);

    final steps = <(String, String)>[
      ('Open', path[0]),
      ('Tap', path[1]),
      ('Tap', path[2]),
      ('Turn off', '“$setting”'),
    ];

    return StickerPage(
      maxWidth: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: StickerHeader(
              'Turning it off',
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      clipBehavior: Clip.none,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.72,
                      children: [
                        for (final (i, shot) in _shots.indexed)
                          _Step(
                            number: i + 1,
                            verb: steps[i].$1,
                            target: steps[i].$2,
                            shot: shot,
                            cropAlignment: _cropAlignment[i],
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Everything else about AirDrop keeps working.',
                      style: St.body(
                        14,
                        weight: FontWeight.w500,
                        color: St.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
            child: StickerWideButton(
              onTap: () => Navigator.of(context).pop(true),
              icon: Symbols.check_rounded,
              label: 'Done',
              color: St.go,
              textColor: St.white,
              height: 66,
              fontSize: 26,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.verb,
    required this.target,
    required this.shot,
    required this.cropAlignment,
  });

  final int number;
  final String verb;
  final String target;
  final String shot;
  final double cropAlignment;

  static const _cardRadius = 16.0;

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      radius: _cardRadius,
      shadow: 4,
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: St.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: St.ink, width: 2),
                  ),
                  child: Text(
                    '$number',
                    style: St.display(13, color: St.white, height: 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$verb ',
                          style: St.body(
                            12,
                            weight: FontWeight.w500,
                            color: St.muted,
                          ),
                        ),
                        TextSpan(
                          text: target,
                          style: St.body(12, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: St.ink, width: 2)),
              ),
              child: Image.asset(
                'assets/sdk/screenshots/$shot.png',
                fit: BoxFit.cover,
                alignment: Alignment(0, cropAlignment),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
