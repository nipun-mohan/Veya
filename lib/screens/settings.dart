import '../core/localization.dart';
import 'package:flutter/material.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../core/platform.dart';
import '../widgets/shared.dart';

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
      await AndroidBridge.call('openAccessibility');
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const LText('Bring your voice to other apps'),
        content: const SingleChildScrollView(
          child: LText(
            'Accessibility finds text fields in chosen apps, excluding passwords. It reads the active field only when you tap Insert, and never presses Send. Disable it anytime in Android settings.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const LText('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const LText('Agree & continue'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final mic = await AndroidBridge.call<bool>('requestMicrophone') ?? false;
    if (!mic) {
      if (mounted) {
        toast(
          context,
          'Microphone permission is needed for the floating dictation button.',
        );
      }
      return;
    }
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
            hintText: 'https://veya-gateway-233466884801.asia-south1.run.app',
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
    padding: const EdgeInsets.all(24),
    children: [
      const Eyebrow('JUST THE WAY YOU LIKE IT'),
      const SizedBox(height: 10),
      LText(
        'Make yourself\nat home.',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 24),
      SurfaceCard(
        color: VeyaColors.ink,
        child: Row(
          children: [
            const VeyaMark(size: 48, dark: false),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LText(
                    'Your everyday voice',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  SizedBox(height: 5),
                  LText(
                    'A little more clarity. A little more you.',
                    style: TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      const Eyebrow('SPEAK YOUR WAY'),
      const SizedBox(height: 12),
      SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: const LText('Speaking language'),
              subtitle: LText(widget.store.selectedLanguage.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => chooseLanguage(context, widget.store),
            ),
            if (AndroidBridge.assistantAvailable) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.bubble_chart_outlined),
                title: const LText('Floating assistant'),
                subtitle: LText(
                  enabled
                      ? 'Enabled · tap to manage'
                      : 'Dictate in your favourite Android apps',
                ),
                trailing: Icon(
                  enabled ? Icons.check_circle : Icons.chevron_right,
                  color: VeyaColors.teal,
                ),
                onTap: assistant,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const LText('Show floating icon'),
                subtitle: const LText('Restore after dragging to Hide'),
                onTap: () async {
                  try {
                    await AndroidBridge.call<void>('showBubble');
                    if (context.mounted) {
                      toast(
                        context,
                        'Icon restored. Focus a text field in a selected app.',
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      toast(
                        context,
                        'Could not restore the icon. Please try again.',
                      );
                    }
                  }
                },
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LText(
                      'Floating icon appearance',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.open_in_full, size: 18),
                        const SizedBox(width: 10),
                        const Expanded(child: LText('Size')),
                        Text(
                          '${(widget.store.floatingIconScale / 1.35 * 100).round()}%',
                        ),
                      ],
                    ),
                    Slider(
                      // 100% on the control maps to the 135% native maximum.
                      value: widget.store.floatingIconScale / 1.35,
                      min: .75 / 1.35,
                      max: 1,
                      divisions: 9,
                      onChanged: (value) {
                        widget.store.setFloatingIconAppearance(
                          scale: value * 1.35,
                        );
                        setState(() {});
                      },
                      onChangeEnd: (value) => widget.store
                          .setFloatingIconAppearance(scale: value * 1.35),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.opacity, size: 18),
                        const SizedBox(width: 10),
                        const Expanded(child: LText('Opacity')),
                        Text(
                          '${(widget.store.floatingIconOpacity * 100).round()}%',
                        ),
                      ],
                    ),
                    Slider(
                      value: widget.store.floatingIconOpacity,
                      min: .35,
                      max: 1,
                      divisions: 13,
                      onChanged: (value) {
                        widget.store.setFloatingIconAppearance(opacity: value);
                        setState(() {});
                      },
                      onChangeEnd: (value) => widget.store
                          .setFloatingIconAppearance(opacity: value),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.apps_rounded),
                title: const LText('Choose your apps'),
                subtitle: LText(
                  '{count} apps selected',
                  args: {'count': widget.store.allowedApps.length.toString()},
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppsScreen(store: widget.store),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 28),
      ListTile(
        leading: const Icon(Icons.person_outline),
        title: const LText('Profile'),
        subtitle: LText(
          widget.store.profileName.isEmpty
              ? (widget.store.phoneNumber.isEmpty
                    ? 'Add your name'
                    : widget.store.phoneNumber)
              : '${widget.store.profileName} · ${widget.store.phoneNumber}',
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _editProfile(context),
      ),
      const Eyebrow('TRANSLATION'),
      ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: const LText('Server translation'),
        subtitle: Text(
          widget.store.endpoint.isEmpty
              ? 'Connect a Veya translation service'
              : widget.store.endpoint,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _editTranslationEndpoint(context),
      ),
      const SizedBox(height: 28),
      const Center(child: VeyaMark(size: 32)),
      const SizedBox(height: 10),
      const Center(
        child: LText(
          'Veya 1.3.0 · Thoughtfully made for your voice.',
          style: TextStyle(color: VeyaColors.muted, fontSize: 10),
        ),
      ),
      const SizedBox(height: 20),
    ],
  );
}

class AppsScreen extends StatefulWidget {
  final VeyaStore store;
  const AppsScreen({super.key, required this.store});
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
    load();
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
          const Center(child: CircularProgressIndicator())
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
