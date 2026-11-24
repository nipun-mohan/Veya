import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _videoUnavailable = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(
      'assets/video/floating_assistant_setup.mp4',
    );
    _controller.addListener(_handleControllerUpdate);
    unawaited(_initializeVideo());
  }

  Future<void> _initializeVideo() async {
    try {
      await _controller.initialize();
      if (!mounted || _controller.value.hasError) {
        if (mounted) setState(() => _videoUnavailable = true);
        return;
      }
      await _controller.setLooping(true);
      await _controller.setVolume(0);
      await _controller.play();
      if (mounted) setState(() {});
    } on PlatformException {
      // Some older devices cannot decode the walkthrough's H.264 stream.
      // The video is illustrative only, so retain the setup path and avoid an
      // uncaught framework error being reported as a fatal app crash.
      if (mounted) setState(() => _videoUnavailable = true);
    } catch (_) {
      if (mounted) setState(() => _videoUnavailable = true);
    }
  }

  void _handleControllerUpdate() {
    if (mounted && _controller.value.hasError && !_videoUnavailable) {
      setState(() => _videoUnavailable = true);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerUpdate);
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
            child: _videoUnavailable
                ? const _VideoUnavailablePreview()
                : _controller.value.isInitialized
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

class _VideoUnavailablePreview extends StatelessWidget {
  const _VideoUnavailablePreview();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: VeyaColors.ink,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_outline_rounded,
              color: VeyaColors.mango,
              size: 44,
            ),
            const SizedBox(height: 10),
            LText(
              'Setup preview is unavailable on this device.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
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
