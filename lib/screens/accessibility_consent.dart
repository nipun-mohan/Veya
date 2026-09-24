import 'package:flutter/material.dart';
import 'dart:async';

import '../core/localization.dart';
import '../core/theme.dart';
import '../widgets/shared.dart';

class AccessibilityConsentScreen extends StatefulWidget {
  const AccessibilityConsentScreen({super.key});

  @override
  State<AccessibilityConsentScreen> createState() =>
      _AccessibilityConsentScreenState();
}

class _AccessibilityConsentScreenState
    extends State<AccessibilityConsentScreen> {
  bool agreed = false;
  bool opening = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _openSettings() async {
    if (!agreed || opening) return;
    setState(() {
      opening = true;
    });
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            title: LText('Enable floating assistant'),
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              children: [
                const Eyebrow('ONE-TIME SETUP'),
                const SizedBox(height: 10),
                LText(
                  'Allow Veya to\nwrite in your apps.',
                  style: TextStyle(
                    fontSize: 39,
                    height: 1.03,
                    letterSpacing: -2.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                LText(
                  'Accessibility lets Veya place your approved voice text into the message field you selected.',
                  style: TextStyle(
                    color: VeyaColors.muted,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                const _WalkthroughPreview(),
                const SizedBox(height: 22),
                const Eyebrow('IN SETTINGS'),
                const SizedBox(height: 10),
                const _Step(
                  number: '1',
                  icon: Icons.apps_rounded,
                  title: 'Open Installed apps',
                  subtitle: 'Find it in Android Accessibility settings.',
                ),
                const _Step(
                  number: '2',
                  icon: Icons.record_voice_over_outlined,
                  title: 'Select Veya',
                  subtitle: 'Open Veya floating assistant.',
                ),
                const _Step(
                  number: '3',
                  icon: Icons.toggle_on_outlined,
                  title: 'Turn on access',
                  subtitle: 'Enable the main Veya toggle. Leave shortcuts off.',
                ),
                const SizedBox(height: 18),
                SurfaceCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LText(
                        'What Veya accesses',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LText(
                        '• The active text field, so Veya knows where to insert your approved text.\n• The name of the current app, to work only in apps you selected.\n• Veya never sends a message, reads passwords, or appears in sensitive fields.',
                        style: TextStyle(
                          color: VeyaColors.muted,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: agreed,
                  onChanged: (value) => setState(() => agreed = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: LText(
                    'I understand and agree',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: agreed && !opening ? _openSettings : null,
                    child: opening
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : LText('Open settings'),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: LText('Not now'),
                ),
              ],
            ),
          ),
        );
}

class _WalkthroughPreview extends StatefulWidget {
  const _WalkthroughPreview();
  @override
  State<_WalkthroughPreview> createState() => _WalkthroughPreviewState();
}

class _WalkthroughPreviewState extends State<_WalkthroughPreview> {
  int step = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() => step = (step + 1) % 3);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Material(
      color: VeyaColors.ink,
      child: SizedBox(
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(
            children: [
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: Column(
                    key: ValueKey(step),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        [
                          Icons.apps_rounded,
                          Icons.accessibility_new_rounded,
                          Icons.toggle_on_rounded,
                        ][step],
                        color: VeyaColors.mango,
                        size: 48,
                      ),
                      const SizedBox(height: 14),
                      LText(
                        [
                          '1  Open Installed apps',
                          '2  Select Veya',
                          '3  Turn on access',
                        ][step],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const LText(
                        'Veya floating assistant',
                        style: TextStyle(
                          color: Color(0xFFD9CFE8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  final String number;
  final IconData icon;
  final String title;
  final String subtitle;
  const _Step({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: VeyaColors.mango,
          child: LText(
            number,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 13),
        Icon(icon, color: VeyaColors.ink, size: 24),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LText(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              LText(
                subtitle,
                style: const TextStyle(
                  color: VeyaColors.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
