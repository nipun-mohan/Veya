import '../core/localization.dart';
import 'package:flutter/material.dart';
import '../core/store.dart';
import '../core/platform.dart';
import '../core/theme.dart';
import '../widgets/shared.dart';
import 'settings.dart';

class HomeShell extends StatefulWidget {
  final VeyaStore store;
  const HomeShell({super.key, required this.store});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int page = 0;
  bool assistantEnabled = false;
  List<Map<String, dynamic>> availableApps = const [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAssistantState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmApps());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAssistantState();
  }

  Future<void> _refreshAssistantState() async {
    final enabled = await AndroidBridge.call<bool>('isEnabled') ?? false;
    if (mounted) setState(() => assistantEnabled = enabled);
  }

  Future<void> _warmApps() async {
    final raw = await AndroidBridge.call<List<dynamic>>('installedApps') ?? [];
    if (!mounted) return;
    setState(() {
      availableApps = raw
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    });
  }

  void _openApps() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AppsScreen(store: widget.store, initialApps: availableApps),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: IndexedStack(
            index: page,
            children: [
              _home(),
              SettingsScreen(store: widget.store),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: (v) => setState(() => page = v),
      destinations: [
        NavigationDestination(
          icon: Icon(Icons.grid_view_rounded),
          label: t(context, 'Home'),
        ),
        NavigationDestination(
          icon: Icon(Icons.tune_rounded),
          label: t(context, 'Settings'),
        ),
      ],
    ),
  );
  Widget _home() => ListView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
    children: [
      Row(
        children: [
          const VeyaMark(size: 44),
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
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => chooseLanguage(context, widget.store),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: VeyaColors.line),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.language_outlined, size: 18),
                  const SizedBox(width: 8),
                  LText(
                    widget.store.selectedLanguage.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.expand_more, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
      const Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(top: 5, right: 4),
          child: LText(
            'English output (automatic)',
            style: TextStyle(color: VeyaColors.muted, fontSize: 10),
          ),
        ),
      ),
      const SizedBox(height: 28),
      SizedBox(
        height: 276,
        child: Stack(
          children: [
            const Positioned(
              left: 0,
              top: 4,
              child: LText(
                'Think it.\nSay it.\nSend it.',
                style: TextStyle(
                  fontSize: 49,
                  height: .94,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -3.1,
                ),
              ),
            ),
            const Positioned(right: 2, top: 20, child: _SpeechRibbons()),
            const Positioned(
              left: 0,
              bottom: 2,
              child: LText(
                'From your language\nto natural English.',
                style: TextStyle(
                  fontSize: 21,
                  height: 1.16,
                  color: VeyaColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
      if (assistantEnabled) ...[
        const SizedBox(height: 26),
        _AssistantStatus(
          count: widget.store.allowedApps.length,
          onTap: _openApps,
        ),
        const SizedBox(height: 14),
      ] else
        const SizedBox(height: 26),
      const SurfaceCard(
        padding: EdgeInsets.fromLTRB(20, 15, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow('HOW IT WORKS', color: VeyaColors.muted),
            SizedBox(height: 8),
            _HowRow(
              number: '1',
              icon: Icons.apps_rounded,
              title: 'Open your app',
              subtitle: 'Go to any selected app.',
            ),
            Divider(),
            _HowRow(
              number: '2',
              icon: Icons.article_outlined,
              title: 'Focus a message field',
              subtitle: 'Tap where you would type.',
            ),
            Divider(),
            _HowRow(
              number: '3',
              icon: Icons.mic_none_rounded,
              title: 'Use the Veya bubble',
              subtitle: 'Speak in your language. We’ll handle the rest.',
            ),
          ],
        ),
      ),
    ],
  );
}

class _SpeechRibbons extends StatefulWidget {
  const _SpeechRibbons();
  @override
  State<_SpeechRibbons> createState() => _SpeechRibbonsState();
}

class _SpeechRibbonsState extends State<_SpeechRibbons>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final phase = Curves.easeInOut.transform(
          _controller.value < .5
              ? _controller.value * 2
              : (1 - _controller.value) * 2,
        );
        return Transform.translate(
          offset: Offset(0, -3 * phase),
          child: Transform.scale(scale: 1 + .018 * phase, child: child),
        );
      },
      child: const SizedBox(
        width: 142,
        height: 174,
        child: Image(
          image: AssetImage('assets/branding/hero-speech-ribbons.png'),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    ),
  );
}

class _AssistantStatus extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _AssistantStatus({required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(22),
    child: Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 18, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF241044), Color(0xFF3A166C)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.circle, color: VeyaColors.mango, size: 13),
              const SizedBox(width: 8),
              const Eyebrow('READY TO GO', color: Color(0xFFFFC25B)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(
                      'Floating assistant',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.8,
                      ),
                    ),
                    SizedBox(height: 3),
                    LText(
                      'Enabled and ready in your apps.',
                      style: TextStyle(color: Color(0xFFD9CFE8), fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: VeyaColors.mango,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: VeyaColors.ink, size: 17),
                    SizedBox(width: 6),
                    LText(
                      'Enabled',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Divider(color: Color(0x55FFFFFF)),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              const Icon(Icons.apps_rounded, color: Colors.white, size: 27),
              const SizedBox(width: 17),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(
                      '$count apps selected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const LText(
                      'Tap to manage apps',
                      style: TextStyle(color: Color(0xFFD9CFE8), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ],
      ),
    ),
  );
}

class _HowRow extends StatelessWidget {
  final String number, title, subtitle;
  final IconData icon;
  const _HowRow({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: number == '2' ? const Color(0xFFE8C3FF) : VeyaColors.mango,
          ),
          child: LText(
            number,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ),
        const SizedBox(width: 15),
        Icon(icon, color: VeyaColors.ink, size: 27),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LText(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              LText(
                subtitle,
                style: const TextStyle(color: VeyaColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
