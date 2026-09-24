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
        height: 292,
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
            const Positioned(right: -10, top: 0, child: _MangoSpeech()),
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
            Positioned(
              right: 0,
              bottom: 3,
              child: Transform.rotate(
                angle: -.17,
                child: const LText(
                  'Your\nvoice\ntravels\nfurther',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: .96,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 26),
      _AssistantStatus(
        count: widget.store.allowedApps.length,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AppsScreen(store: widget.store)),
        ),
      ),
      const SizedBox(height: 14),
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

class _MangoSpeech extends StatelessWidget {
  const _MangoSpeech();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(184, 244), painter: _MangoPainter());
}

class _MangoPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawPath(
      Path()
        ..moveTo(s.width * .39, s.height * .02)
        ..quadraticBezierTo(
          s.width * .83,
          -s.height * .04,
          s.width * .78,
          s.height * .22,
        )
        ..lineTo(s.width * .54, s.height * .75)
        ..quadraticBezierTo(
          s.width * .47,
          s.height * .98,
          s.width * .30,
          s.height * .90,
        )
        ..lineTo(s.width * .30, s.height * .28)
        ..quadraticBezierTo(
          s.width * .30,
          s.height * .08,
          s.width * .39,
          s.height * .02,
        )
        ..close(),
      Paint()..color = VeyaColors.mango,
    );
    c.drawPath(
      Path()
        ..moveTo(s.width * .31, s.height * .54)
        ..quadraticBezierTo(
          s.width * .68,
          s.height * .30,
          s.width * .88,
          s.height * .46,
        )
        ..quadraticBezierTo(
          s.width * .98,
          s.height * .61,
          s.width * .72,
          s.height * .70,
        )
        ..quadraticBezierTo(
          s.width * .52,
          s.height * .78,
          s.width * .25,
          s.height * .98,
        )
        ..lineTo(s.width * .25, s.height * .67)
        ..quadraticBezierTo(
          s.width * .25,
          s.height * .58,
          s.width * .31,
          s.height * .54,
        )
        ..close(),
      Paint()..color = VeyaColors.orange,
    );
    c.save();
    c.translate(s.width * .86, s.height * .19);
    c.rotate(-.72);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s.width * .18, s.height * .055),
        Radius.circular(s.width * .05),
      ),
      Paint()..color = VeyaColors.lavender,
    );
    c.translate(-s.width * .02, s.height * .10);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s.width * .18, s.height * .055),
        Radius.circular(s.width * .05),
      ),
      Paint()..color = VeyaColors.lavender,
    );
    c.restore();
    c.save();
    c.translate(s.width * .64, s.height * .93);
    c.rotate(-.72);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          -s.width * .16,
          -s.height * .045,
          s.width * .34,
          s.height * .09,
        ),
        Radius.circular(s.width * .08),
      ),
      Paint()..color = VeyaColors.lavender,
    );
    c.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
