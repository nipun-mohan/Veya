import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/localization.dart';
import '../core/theme.dart';

/// Displays the policy from the public site instead of bundling a copy. This
/// means updates published at the policy URL are shown the next time it opens.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  static final _primaryUrl = Uri.parse('https://heyveya.app/privacy');
  static final _fallbackUrl = Uri.parse('https://api.heyveya.app/privacy');
  late final WebViewController _controller;
  bool _loading = true;
  bool _usingFallback = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(VeyaColors.paper)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted)
              setState(() {
                _loading = true;
                _error = null;
              });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            if (!_usingFallback) {
              _usingFallback = true;
              _controller.loadRequest(_fallbackUrl);
              return;
            }
            if (mounted) {
              setState(() {
                _loading = false;
                _error =
                    'We could not load the privacy policy. Please try again.';
              });
            }
          },
        ),
      )
      ..loadRequest(_primaryUrl);
  }

  void _retry() {
    _usingFallback = false;
    _controller.loadRequest(_primaryUrl);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: VeyaColors.paper,
    appBar: AppBar(
      backgroundColor: VeyaColors.paper,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      title: const LText(
        'Privacy policy',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 38),
                  const SizedBox(height: 14),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _retry,
                    child: const LText('Try again'),
                  ),
                ],
              ),
            ),
          ),
        if (_loading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(),
          ),
      ],
    ),
  );
}
