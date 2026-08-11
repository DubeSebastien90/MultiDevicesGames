import 'package:flutter/material.dart';

import '../model/name_drop_status.dart';
import '../platform/name_drop_support.dart';

/// Shows [showNameDropNotice] over [child] the first time this is built with
/// an unanswered question on a phone that can actually NameDrop.
///
/// Wrapped around the lobby rather than built into it, for two reasons. The
/// lobby has no state of its own and does not want any; and *the lobby* is the
/// deliberate choice of moment. It is the last screen before phones start
/// moving toward each other, and the only one where a full-screen interruption
/// costs nothing — putting this on the placement or game screens would mean
/// interrupting a round to complain about interruptions.
///
/// Which is also why a reset arriving mid-game does not reopen this. The state
/// flips silently and the question comes back the next time somebody walks
/// through here.
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
    // After the first frame: this runs on the way into the lobby, and showing
    // a dialog from inside a build is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  Future<void> _maybeAsk() async {
    if (!await NameDropSupport.onThisDevice()) return;
    if (await NameDropPref.load() != NameDropStatus.waiting) return;
    if (!mounted) return;

    final answer = await showNameDropNotice(context);
    // A no-answer stays unwritten, so the question survives to the next lobby.
    if (answer != NameDropStatus.waiting) await NameDropPref.save(answer);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Asks an iPhone owner to turn off Bringing Devices Together before the game
/// starts.
///
/// That setting is what makes NameDrop fire when the tops of two iPhones meet,
/// and this platform spends its whole life asking people to put the tops of
/// phones together. [NameDropOptimizer] turns phones around to keep the
/// dangerous ends apart and gets most tables, but it cannot get all of them,
/// and a Share Contact card over a running game is the one interruption nobody
/// can dismiss quickly.
///
/// **Everything here is words.** There is no button that opens the right page
/// of Settings, because no such button can exist: `UIApplication`'s public
/// entry point opens only this app's own pane, and the `App-Prefs:` scheme that
/// reaches General → AirDrop is one Apple rejects apps for using. So the second
/// button shows the path and trusts people to walk it — which is also why
/// nothing here can verify the answer, and why the host quietly disbelieves it
/// when two phones get interrupted together.
///
/// Returns the state the answer implies. Never null: the sheet cannot be
/// dismissed except by choosing, and the instructions open *over* it, so
/// backing out of them lands back on the question rather than escaping it.
Future<NameDropStatus> showNameDropNotice(BuildContext context) async {
  final answer = await showDialog<NameDropStatus>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _NameDropNotice(),
  );
  // Only reachable if something outside this file pops the route — a state
  // restoration, a test pumping a different widget. Asking again next time is
  // the safe reading of "no answer".
  return answer ?? NameDropStatus.waiting;
}

/// The setting's name as the Settings app spells it, per language.
///
/// Somebody hunting for 'Bringing Devices Together' on a French phone will not
/// find it — iOS shows these in the device's language, and the whole value of
/// this screen is that the words on it match the words on the next one.
/// Anything not listed falls back to English, which is what the device shows
/// for unlisted languages anyway.
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
    final theme = Theme.of(context);
    final setting = _localised(_settingName, context);

    return Dialog.fullscreen(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.contact_page_outlined,
                    size: 52,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'One thing before you play',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'This game puts phones edge to edge. When the tops of two '
                    'iPhones touch, iOS pops up a card offering to share your '
                    'contact details — over the game, mid-round.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Turning off “$setting” stops it.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () => Navigator.of(context)
                        .pop(NameDropStatus.turnedOff),
                    child: const Text('Already done'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => _showHow(context),
                    child: const Text('How?'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(NameDropStatus.declined),
                    child: const Text('No thanks'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Either way, this is the last you’ll hear of it.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the walkthrough over the notice, and closes the notice as done only
  /// if they came back off the end of it.
  ///
  /// Backing out means they did not follow it through, and the honest record of
  /// that is the question they were already being asked — still underneath,
  /// still unanswered.
  Future<void> _showHow(BuildContext context) async {
    // An ordinary push, not a fullscreen dialog: this is somewhere you go and
    // come back from, and the back arrow says so. A dialog's close button
    // reads as "cancel", which is the wrong word for reaching the end of a
    // set of instructions.
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _HowScreen()),
    );
    if (done == true && context.mounted) {
      Navigator.of(context).pop(NameDropStatus.turnedOff);
    }
  }
}

class _HowScreen extends StatelessWidget {
  const _HowScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = _path(context);
    final setting = _localised(_settingName, context);

    final steps = [
      'Open ${path[0]}',
      'Tap ${path[1]}',
      'Tap ${path[2]}',
      'Turn off “$setting”',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Turning it off')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  _Step(number: i + 1, text: steps[i]),
                  if (i < steps.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 15),
                      child: SizedBox(
                        height: 18,
                        child: VerticalDivider(
                          width: 2,
                          thickness: 2,
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                Text(
                  'This also stops your iPhone starting an AirDrop when you '
                  'hold it near someone else’s. Everything else about AirDrop '
                  'keeps working.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            '$number',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(text, style: theme.textTheme.titleMedium),
        ),
      ],
    );
  }
}
