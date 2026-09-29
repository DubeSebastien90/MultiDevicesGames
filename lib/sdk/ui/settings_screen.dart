import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/device_metrics.dart';
// import '../monetization/premium_status.dart'; // NO-IAP
import 'lobby_flow_style.dart';
import 'screen_size_screen.dart';

/// Where the privacy policy is published. The page lives in its own repo
/// (BubbleGamesPrivacy) on GitHub Pages, so it can be corrected without shipping
/// a build.
final Uri kPrivacyPolicyUrl = Uri.parse(
  'https://dubesebastien90.github.io/BubbleGamesPrivacy/',
);

/// The formal odds and ends: what this screen measures, and the buttons that
/// belong nowhere else.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.metrics,
    required this.onMetricsChanged,
    // required this.premium, // NO-IAP
  });

  final DeviceMetrics metrics;
  final ValueChanged<DeviceMetrics> onMetricsChanged;
  // final PremiumStatus premium; // NO-IAP

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late DeviceMetrics _metrics = widget.metrics;
  // bool _restoring = false; // NO-IAP

  void _onMetricsChanged(DeviceMetrics m) {
    setState(() => _metrics = m);
    widget.onMetricsChanged(m);
  }

  /// The measuring kit: typed millimetres, native re-detect, and the card flow.
  ///
  /// A page rather than the dialog it used to be. The kit is three fields, two
  /// buttons and a paragraph explaining why any of it matters, and a dialog
  /// sized to the shorter of those was always going to cut something off — on
  /// a phone in landscape, with a keyboard up, it cut off most of it.
  void _calibrate() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ScreenSizeScreen(metrics: _metrics, onChanged: _onMetricsChanged),
      ),
    );
  }

  // NO-IAP: nothing to restore until in-app purchases ship.
  /*
  /// The paywall's restore, reachable without first tapping a locked game —
  /// the place a player who reinstalled goes looking for it.
  Future<void> _reloadPurchases() async {
    setState(() => _restoring = true);
    final outcome = await widget.premium.restore();
    if (!mounted) return;
    setState(() => _restoring = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(restoreMessage(outcome))),
    );
  }
  */

  /// Opens the policy in an in-app browser sheet (SFSafariViewController on
  /// iOS, a Custom Tab on Android) rather than throwing the player out to the
  /// browser app: they are reading one page, and should land back here.
  Future<void> _openPrivacyPolicy() async {
    var opened = false;
    try {
      opened = await launchUrl(
        kPrivacyPolicyUrl,
        mode: LaunchMode.inAppBrowserView,
      );
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't open the privacy policy.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LobbyFlowColors.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                LobbyHeader(
                  title: 'Settings',
                  onBack: () => Navigator.of(context).pop(),
                  // The list is already inset.
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                ),
                const SizedBox(height: 28),
                DimensionsCard(metrics: _metrics),
                const SizedBox(height: 28),
                _SettingsButton(
                  label: 'Calibrate screen',
                  onPressed: _calibrate,
                ),
                // NO-IAP
                // const SizedBox(height: 14),
                // _SettingsButton(
                //   label: _restoring ? 'Checking…' : 'Reload Purchases',
                //   onPressed: _restoring ? null : _reloadPurchases,
                // ),
                const SizedBox(height: 14),
                _SettingsButton(
                  label: 'See Privacy Policy',
                  onPressed: _openPrivacyPolicy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => LobbyPillButton(
    label: label,
    onPressed: onPressed,
    background: LobbyFlowColors.field,
    foreground: LobbyFlowColors.ink,
    fontSize: 17,
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
  );
}
