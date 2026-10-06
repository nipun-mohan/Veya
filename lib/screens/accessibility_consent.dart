import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
          const _WalkthroughVideo(),
          const SizedBox(height: 18),
          SurfaceCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(
                  'What Veya accesses',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
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
              child: opening ? const VeyaLoader() : LText('Open settings'),
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

class _WalkthroughVideo extends StatefulWidget {
  const _WalkthroughVideo();
  @override
  State<_WalkthroughVideo> createState() => _WalkthroughVideoState();
}

class _WalkthroughVideoState extends State<_WalkthroughVideo> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        VideoPlayerController.asset('assets/video/floating_assistant_setup.mp4')
          ..initialize().then((_) {
            if (!mounted) return;
            _controller
              ..setLooping(true)
              ..setVolume(0)
              ..play();
            setState(() {});
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Material(
      color: Colors.transparent,
      child: SizedBox(
        height: 520,
        width: double.infinity,
        child: Center(
          child: AspectRatio(
            aspectRatio: _controller.value.isInitialized
                ? _controller.value.aspectRatio
                : 9 / 16,
            child: _controller.value.isInitialized
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoPlayer(_controller),
                      const IgnorePointer(
                        child: CustomPaint(painter: _VideoCornerMask()),
                      ),
                    ],
                  )
                : const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(color: VeyaColors.mango),
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
}

/// Android's video texture is rendered above Flutter's normal clip layer.
/// This paints the page colour over its corners to create the intended shape.
class _VideoCornerMask extends CustomPainter {
  const _VideoCornerMask();

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Path()..addRect(Offset.zero & size);
    final rounded = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, frame, rounded),
      Paint()..color = VeyaColors.paper,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoCornerMask oldDelegate) => false;
}
