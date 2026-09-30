import '../core/localization.dart';
import 'package:flutter/material.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../core/platform.dart';
import '../widgets/shared.dart';
import 'accessibility_consent.dart';
import 'privacy_policy.dart';

class SettingsScreen extends StatefulWidget {
  final VeyaStore store;
  const SettingsScreen({super.key, required this.store});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool enabled = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    final value = await AndroidBridge.call<bool>('isEnabled') ?? false;
    if (mounted) setState(() => enabled = value);
  }

  Future<void> assistant() async {
    if (!AndroidBridge.assistantAvailable) {
      toast(context, 'The floating assistant is available in the Android app.');
      return;
    }
    if (enabled) {
      await AndroidBridge.call('openAccessibilityForDisable');
      return;
    }
    if (widget.store.accessibilityConsentAccepted) {
      await _openAccessibilitySettings();
      return;
    }
    if (!mounted) return;
    final accepted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AccessibilityConsentScreen()),
    );
    if (accepted == true) {
      await widget.store.acceptAccessibilityConsent();
      await _openAccessibilitySettings();
    }
  }

  Future<void> _openAccessibilitySettings() async {
    await widget.store.syncNative();
    await AndroidBridge.call('openAccessibility');
  }

  Future<void> _editTranslationEndpoint(BuildContext context) async {
    final controller = TextEditingController(text: widget.store.endpoint);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Translation service'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://api.heyveya.app',
            labelText: 'Gateway URL',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const LText('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    widget.store.endpoint = value.replaceAll(RegExp(r'/+$'), '');
    await widget.store.persist();
    if (context.mounted) toast(context, 'Translation service saved.');
  }

  Future<void> _editProfile(BuildContext context) async {
    final name = TextEditingController(text: widget.store.profileName);
    final nameFocus = FocusNode();
    var editing = widget.store.profileName.isEmpty;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: LText(
                        'Profile',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (!editing)
                      TextButton.icon(
                        onPressed: () {
                          setSheetState(() => editing = true);
                          Future.microtask(nameFocus.requestFocus);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const LText('Edit'),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (editing)
                  TextField(
                    controller: name,
                    focusNode: nameFocus,
                    textCapitalization: TextCapitalization.words,
                    autofocus: widget.store.profileName.isEmpty,
                    decoration: const InputDecoration(labelText: 'Name'),
                  )
                else
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Name'),
                    child: Text(widget.store.profileName),
                  ),
                const SizedBox(height: 14),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Mobile number'),
                  child: Text(
                    widget.store.phoneNumber.isEmpty
                        ? 'Not added'
                        : widget.store.phoneNumber,
                  ),
                ),
                if (editing) ...[
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () async {
                      await widget.store.setProfileName(name.text);
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext, true);
                      }
                    },
                    child: const LText('Save'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    name.dispose();
    nameFocus.dispose();
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
    children: [
      Row(
        children: [
          const VeyaMark(size: 42),
          const SizedBox(width: 8),
          const LText(
            'veya',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.8,
            ),
          ),
          const Spacer(),
          const Eyebrow('JUST\nTHE WAY YOU\nLIKE IT', color: VeyaColors.ink),
        ],
      ),
      const SizedBox(height: 32),
      const Eyebrow('PREFERENCES', color: VeyaColors.muted),
      const SizedBox(height: 11),
      SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _PreferenceRow(
              icon: Icons.language_outlined,
              title: 'Speaking language',
              subtitle: widget.store.selectedLanguage.name,
              onTap: () => chooseLanguage(context, widget.store),
            ),
            const Divider(),
            _PreferenceRow(
              icon: Icons.bubble_chart_outlined,
              title: 'Floating assistant',
              subtitle: enabled ? 'Enabled' : 'Disabled',
              trailing: Switch(value: enabled, onChanged: (_) => assistant()),
            ),
          ],
        ),
      ),
      const SizedBox(height: 13),
      SurfaceCard(
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Eyebrow(
                    'FLOATING ICON APPEARANCE',
                    color: VeyaColors.muted,
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(9),
                  decoration: const BoxDecoration(
                    color: VeyaColors.mango,
                    shape: BoxShape.circle,
                  ),
                  child: const VeyaOrb(size: 30),
                ),
              ],
            ),
            _SliderRow(
              icon: Icons.open_in_full_rounded,
              label: 'Size',
              value: widget.store.floatingIconScale / 1.35,
              display:
                  '${(widget.store.floatingIconScale / 1.35 * 100).round()}%',
              min: .75 / 1.35,
              onChanged: (v) {
                widget.store.setFloatingIconAppearance(scale: v * 1.35);
                setState(() {});
              },
            ),
            _SliderRow(
              icon: Icons.opacity_outlined,
              label: 'Opacity',
              value: widget.store.floatingIconOpacity,
              display: '${(widget.store.floatingIconOpacity * 100).round()}%',
              min: .35,
              onChanged: (v) {
                widget.store.setFloatingIconAppearance(opacity: v);
                setState(() {});
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 13),
      SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _PreferenceRow(
              icon: Icons.person_outline_rounded,
              title: 'Profile',
              onTap: () => _editProfile(context),
            ),
            const Divider(),
            _PreferenceRow(
              icon: Icons.tune_rounded,
              title: 'Translation settings',
              onTap: () => _editTranslationEndpoint(context),
            ),
            const Divider(),
            _PreferenceRow(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy policy',
              subtitle: 'View the latest policy',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PreferenceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _PreferenceRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 19, vertical: 2),
    leading: Icon(icon, size: 28, color: VeyaColors.ink),
    title: LText(
      title,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
    ),
    subtitle: subtitle == null
        ? null
        : LText(
            subtitle!,
            style: const TextStyle(color: VeyaColors.muted, fontSize: 12),
          ),
    trailing:
        trailing ?? const Icon(Icons.chevron_right, color: VeyaColors.ink),
    onTap: onTap,
  );
}

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String label, display;
  final double value, min;
  final ValueChanged<double> onChanged;
  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.display,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      children: [
        Row(
          children: [
            Icon(icon, color: VeyaColors.ink, size: 23),
            const SizedBox(width: 13),
            Expanded(
              child: LText(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            LText(
              display,
              style: const TextStyle(color: VeyaColors.muted, fontSize: 12),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: 1,
          activeColor: VeyaColors.teal,
          secondaryActiveColor: VeyaColors.orange,
          thumbColor: VeyaColors.mango,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class AppsScreen extends StatefulWidget {
  final VeyaStore store;
  final List<Map<String, dynamic>> initialApps;
  const AppsScreen({
    super.key,
    required this.store,
    this.initialApps = const [],
  });
  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<Map<String, dynamic>> apps = [];
  bool loading = true;
  String query = '';
  @override
  void initState() {
    super.initState();
    if (widget.initialApps.isNotEmpty) {
      apps = widget.initialApps;
      loading = false;
    } else {
      load();
    }
  }

  Future<void> load() async {
    final raw = await AndroidBridge.call<List<dynamic>>('installedApps') ?? [];
    if (mounted) {
      setState(() {
        apps = raw.map((e) => Map<String, dynamic>.from(e)).toList();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LText('Your favourite apps')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const LText(
          'A helping hand, only where you want it.',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 12),
        const LText(
          'The floating microphone appears only in selected apps when a non-password text field has focus.',
          style: TextStyle(color: VeyaColors.muted),
        ),
        const SizedBox(height: 24),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: InputDecoration(
            hintText: t(context, 'Find an app'),
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        if (loading)
          const Center(child: VeyaLoader())
        else if (apps.isEmpty)
          const SurfaceCard(
            child: LText(
              'Install Veya on Android to choose from your installed apps.',
            ),
          )
        else
          ...apps
              .where(
                (a) => (a['name'] as String).toLowerCase().contains(
                  query.toLowerCase(),
                ),
              )
              .map(
                (a) => CheckboxListTile(
                  value: widget.store.allowedApps.contains(a['package']),
                  title: Text(a['name']),
                  subtitle: Text(
                    a['package'],
                    style: const TextStyle(
                      fontSize: 10,
                      color: VeyaColors.muted,
                    ),
                  ),
                  onChanged: (v) async {
                    if (v == true) {
                      widget.store.allowedApps.add(a['package']);
                    } else {
                      widget.store.allowedApps.remove(a['package']);
                    }
                    await widget.store.persist();
                    if (mounted) setState(() {});
                  },
                ),
              ),
      ],
    ),
  );
}
