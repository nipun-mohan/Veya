import '../core/localization.dart';
import 'package:flutter/material.dart';
import '../core/store.dart';
import '../core/platform.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../widgets/shared.dart';
import 'settings.dart';

class HomeShell extends StatefulWidget {
  final VeyaStore store;
  const HomeShell({super.key, required this.store});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int page = 0;
  @override
  void initState() {
    super.initState();
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
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
    children: [
      Row(
        children: [
          const VeyaMark(size: 36),
          const SizedBox(width: 9),
          const LText(
            'veya',
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () => chooseLanguage(context, widget.store),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: VeyaColors.line),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.language, size: 16),
                    const SizedBox(width: 7),
                    Expanded(
                      child: LText(
                        widget.store.selectedLanguage.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 30),
      const Eyebrow('A SPACE FOR YOUR VOICE'),
      const SizedBox(height: 10),
      LText(
        'Good words start\nwith you.',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 10),
      const LText(
        'Think it. Say it. Send it.',
        style: TextStyle(color: VeyaColors.muted, fontSize: 15),
      ),
      const SizedBox(height: 25),
      SurfaceCard(
        color: VeyaColors.ink,
        padding: const EdgeInsets.fromLTRB(24, 23, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: VeyaColors.lime,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Eyebrow(
                    'YOUR VOICE, MORE POSSIBILITY',
                    color: VeyaColors.lime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 17),
            const LText(
              'Speak freely.\nWe’ll find the words.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w700,
                height: 1.25,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 8),
            const LText(
              'From your language to natural English.',
              style: TextStyle(color: Color(0xFFB5C9BC), fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Waveform(),
            const SizedBox(height: 4),
            const Center(
              child: LText(
                'Focus a message field in one of your selected apps.',
                style: TextStyle(color: Color(0xFFB5C9BC), fontSize: 10),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ],
  );
}
