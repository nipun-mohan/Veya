import '../core/localization.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/models.dart';
import '../core/store.dart';

class VeyaMark extends StatelessWidget {
  final double size;
  final bool dark;
  const VeyaMark({super.key, this.size = 40, this.dark = true});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _MarkPainter(dark ? VeyaColors.mango : Colors.white),
    ),
  );
}

/// Circular companion for the floating-assistant preview.  It deliberately
/// shares the exact V-wave measurements of [VeyaMark].
class VeyaOrb extends StatelessWidget {
  final double size;
  const VeyaOrb({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _OrbPainter()),
  );
}

/// The one loading treatment used throughout Veya.
class VeyaLoader extends StatelessWidget {
  const VeyaLoader({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 20,
    child: const CircularProgressIndicator(
      strokeWidth: 2.8,
      color: VeyaColors.ink,
    ),
  );
}

class _MarkPainter extends CustomPainter {
  final Color color;
  _MarkPainter(this.color);
  @override
  void paint(Canvas c, Size s) {
    c.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * .28)),
      Paint()..color = color,
    );
    final wave = Paint()
      ..color = VeyaColors.ink
      ..strokeWidth = s.width * .10
      ..strokeCap = StrokeCap.round;
    // Five equal bars form the V-wave used by both the launcher and bubble.
    // Keep the left/right bars comfortably inside the tile; this preserves the
    // recognizable silhouette even at small Android launcher sizes.
    const tops = [.31, .44, .57, .44, .31];
    const bottoms = [.62, .75, .88, .75, .62];
    for (var i = 0; i < tops.length; i++) {
      final x = s.width * (.21 + i * .14);
      c.drawLine(
        Offset(x, s.height * tops[i]),
        Offset(x, s.height * bottoms[i]),
        wave,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

class _OrbPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawCircle(
      Offset(s.width / 2, s.height / 2),
      s.shortestSide / 2,
      Paint()..color = VeyaColors.mango,
    );
    final wave = Paint()
      ..color = VeyaColors.ink
      ..strokeWidth = s.width * .10
      ..strokeCap = StrokeCap.round;
    const tops = [.31, .44, .57, .44, .31];
    const bottoms = [.62, .75, .88, .75, .62];
    for (var i = 0; i < tops.length; i++) {
      final x = s.width * (.21 + i * .14);
      c.drawLine(
        Offset(x, s.height * tops[i]),
        Offset(x, s.height * bottoms[i]),
        wave,
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) => false;
}

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  const SurfaceCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(20),
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: VeyaColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class Eyebrow extends StatelessWidget {
  final String text;
  final Color color;
  const Eyebrow(this.text, {super.key, this.color = VeyaColors.muted});
  @override
  Widget build(BuildContext context) => LText(
    text,
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.7,
      color: color,
    ),
  );
}

class Waveform extends StatefulWidget {
  final bool active;
  final Color color;
  const Waveform({
    super.key,
    this.active = false,
    this.color = VeyaColors.lime,
  });
  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  @override
  void initState() {
    super.initState();
    if (widget.active) animation.repeat();
  }

  @override
  void didUpdateWidget(Waveform old) {
    super.didUpdateWidget(old);
    if (widget.active) {
      animation.repeat();
    } else {
      animation.stop();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 70,
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, _) => CustomPaint(
        size: const Size(double.infinity, 70),
        painter: _WavePainter(widget.color, animation.value, widget.active),
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  final Color color;
  final double phase;
  final bool active;
  _WavePainter(this.color, this.phase, this.active);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    final n = (s.width / 8).floor();
    for (var i = 0; i < n; i++) {
      final x = (i + .5) * s.width / n;
      final envelope = math.pow(math.sin(i / n * math.pi), 1.7);
      final signal = (math.sin(i * 1.8 + phase * math.pi * 2) * .5 + .5);
      final h = 4 + envelope * (active ? 58 : 43) * (.15 + signal * .85);
      c.drawLine(
        Offset(x, (s.height - h) / 2),
        Offset(x, (s.height + h) / 2),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LText(text)));
Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, 'Copied. Ready when you are.');
}

Future<void> chooseLanguage(BuildContext context, VeyaStore store) async {
  final search = TextEditingController();
  final query = ValueNotifier<String>('');
  final animation = AnimationController(
    vsync: Navigator.of(context),
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 190),
  );
  final animationCurve = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  OverlayEntry? entry;
  var closed = false;

  Future<void> close() async {
    if (closed) return;
    closed = true;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.wait([
      animation.reverse(),
      Future<void>.delayed(const Duration(milliseconds: 180)),
    ]);
    entry?.remove();
    animation.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      search.dispose();
      query.dispose();
    });
  }

  final sheet = Align(
    alignment: Alignment.bottomCenter,
    child: SafeArea(
      top: false,
      bottom: false,
      child: Material(
        color: VeyaColors.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: double.infinity,
          height: 570,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LanguageSheetDismissHandle(onDismiss: close),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: LText(
                  'Think in your language.',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: LText(
                  'Choose the language you’ll speak.',
                  style: TextStyle(color: VeyaColors.muted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                child: TextField(
                  controller: search,
                  onChanged: (value) => query.value = value,
                  decoration: const InputDecoration(
                    hintText: 'Search languages',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: query,
                  builder: (_, value, __) {
                    final normalized = value.trim().toLowerCase();
                    final filtered = languages.where((language) {
                      return normalized.isEmpty ||
                          language.name.toLowerCase().contains(normalized) ||
                          language.native.toLowerCase().contains(normalized);
                    });
                    return ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final language in filtered)
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                            ),
                            title: LText(language.name),
                            subtitle: LText(language.native),
                            trailing: store.language == language.code
                                ? const Icon(
                                    Icons.check_circle,
                                    color: VeyaColors.teal,
                                  )
                                : null,
                            onTap: () async {
                              await close();
                              store.language = language.code;
                              await store.persist();
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  entry = OverlayEntry(
    builder: (_) => AnimatedBuilder(
      animation: animationCurve,
      builder: (_, __) => Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: animationCurve.value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: close,
                  child: const ColoredBox(color: Color(0x88000000)),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, (1 - animationCurve.value) * 620),
              child: sheet,
            ),
          ],
        ),
      ),
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  animation.forward();
}

class _LanguageSheetDismissHandle extends StatelessWidget {
  const _LanguageSheetDismissHandle({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Close language selection',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      onVerticalDragEnd: (_) => onDismiss(),
      child: SizedBox(
        height: 28,
        width: double.infinity,
        child: Center(
          child: Container(
            height: 4,
            width: 42,
            decoration: BoxDecoration(
              color: VeyaColors.line,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onTap;
  const SectionTitle(this.title, {super.key, this.action, this.onTap});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: LText(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (action != null) TextButton(onPressed: onTap, child: LText(action!)),
    ],
  );
}

Future<void> chooseAppLanguage(BuildContext context, VeyaStore store) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: 570,
        child: Column(
          children: [
            _LanguageSheetDismissHandle(
              onDismiss: () => Navigator.pop(context),
            ),
            const ListTile(
              title: LText('App language'),
              subtitle: LText('Change the language of menus and buttons.'),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final language in languages)
                    ListTile(
                      title: Text(language.native),
                      subtitle: LText(language.name),
                      trailing: store.uiLanguage == language.code
                          ? const Icon(Icons.check_circle)
                          : null,
                      onTap: () async {
                        await store.setUiLanguage(
                          language.code,
                          setSpeaking: true,
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
