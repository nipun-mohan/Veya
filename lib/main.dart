import 'dart:async';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/store.dart';
import 'core/localization.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Render immediately. Local configuration now loads while the
  // splash animation is visible instead of leaving a blank native window.
  runApp(const VeyaBootstrap());
}

class VeyaBootstrap extends StatefulWidget {
  const VeyaBootstrap({super.key});

  @override
  State<VeyaBootstrap> createState() => _VeyaBootstrapState();
}

class _VeyaBootstrapState extends State<VeyaBootstrap> {
  VeyaStore? _store;
  bool _startupFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Do not keep the user on the launch view while a plugin, secure storage,
    // or network-backed token restoration is slow. The app can render its
    // local sign-in flow first and hydrate the saved account in the background.
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 4),
      );
      final store = VeyaStore(prefs);
      if (!mounted) return;
      setState(() {
        _store = store;
        _startupFailed = false;
      });
      unawaited(_hydrate(store));
    } catch (_) {
      // A failed platform-channel read must not leave the user on the brand
      // animation indefinitely. Surface a retryable screen instead.
      if (mounted) setState(() => _startupFailed = true);
    }
  }

  Future<void> _hydrate(VeyaStore store) async {
    var firebaseReady = false;
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 6));
      firebaseReady = true;
      _configureCrashReporting();
      await _configureAnalytics();
    } catch (_) {
      // A temporary Firebase or device-service failure must never leave the
      // application frozen on its splash screen. Login will surface a useful
      // error if Firebase is still unavailable when it is actually needed.
    }

    try {
      await VeyaStrings.preload().timeout(const Duration(seconds: 3));
    } catch (_) {
      // The localization delegate falls back to the bundled English labels.
    }

    try {
      await store.load().timeout(const Duration(seconds: 5));
      // Require one real Firebase verification before restoring the protected
      // route from a prior session.
      if (firebaseReady &&
          store.onboarded &&
          FirebaseAuth.instance.currentUser == null) {
        store.onboarded = false;
        await store.persist().timeout(const Duration(seconds: 3));
      }
    } catch (_) {
      // `store` was already supplied to the widget tree with safe defaults.
      // Leave the user at sign-in rather than trapping them on the launch view.
    }
  }

  void _configureCrashReporting() {
    // Crashlytics receives native Android crashes automatically. These two
    // handlers also report uncaught Flutter and async errors with a usable
    // stack trace, without affecting the user-facing error flow.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  Future<void> _configureAnalytics() async {
    // Firebase Analytics automatically records app lifecycle events and the
    // observer below records screen views. Do not attach phone numbers, OTPs,
    // message content, or other sensitive data to Analytics.
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
  }

  @override
  Widget build(BuildContext context) => VeyaApp(
    store: _store,
    startupFailed: _startupFailed,
    retryStartup: _load,
  );
}

class VeyaApp extends StatelessWidget {
  final VeyaStore? store;
  final bool startupFailed;
  final VoidCallback retryStartup;
  const VeyaApp({
    super.key,
    required this.store,
    required this.startupFailed,
    required this.retryStartup,
  });
  @override
  Widget build(BuildContext context) {
    final current = store;
    return MaterialApp(
      title: 'Veya',
      debugShowCheckedModeBanner: false,
      theme: veyaTheme(),
      locale: Locale((current?.uiLanguage ?? 'en').split('-').first),
      supportedLocales: VeyaStrings.codes.map((code) => Locale(code)).toList(),
      localizationsDelegates: const [
        VeyaStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
      ],
      home: VeyaSplash(
        ready: current != null,
        child: current == null
            ? _StartupRecovery(failed: startupFailed, onRetry: retryStartup)
            : ListenableBuilder(
                listenable: current,
                builder: (context, _) => current.onboarded
                    ? HomeShell(store: current)
                    : OnboardingScreen(store: current),
              ),
      ),
    );
  }
}

class _StartupRecovery extends StatelessWidget {
  final bool failed;
  final VoidCallback onRetry;
  const _StartupRecovery({required this.failed, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (!failed) {
      return const Scaffold(
        backgroundColor: VeyaColors.paper,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: VeyaColors.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Veya needs a moment to start.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please check your connection and try again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the supplied brand motion before exposing the existing app route.
/// The native launch view uses the same paper color so there is no white flash.
class VeyaSplash extends StatefulWidget {
  final Widget child;
  final bool ready;
  const VeyaSplash({super.key, required this.child, required this.ready});

  @override
  State<VeyaSplash> createState() => _VeyaSplashState();
}

class _VeyaSplashState extends State<VeyaSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _fallback;
  bool _complete = false;
  bool _animationDone = false;
  bool _showFallback = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    // If the asset ever fails to decode, users still reach the app promptly.
    _fallback = Timer(const Duration(seconds: 5), () {
      _animationFinished();
      if (mounted && !widget.ready) {
        setState(() => _showFallback = true);
        _tryFinish();
      }
    });
  }

  @override
  void didUpdateWidget(covariant VeyaSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tryFinish();
  }

  void _animationFinished() {
    _animationDone = true;
    _tryFinish();
  }

  void _tryFinish() {
    if (!_animationDone || (!widget.ready && !_showFallback)) return;
    if (!mounted || _complete) return;
    _fallback?.cancel();
    setState(() => _complete = true);
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_complete) return widget.child;
    return Scaffold(
      backgroundColor: VeyaColors.paper,
      body: Center(
        child: SizedBox(
          width: 184,
          height: 184,
          child: Lottie.asset(
            'assets/branding/text_splash.json',
            controller: _controller,
            fit: BoxFit.contain,
            onLoaded: (composition) {
              _controller
                ..duration = composition.duration
                ..forward(from: 0).whenComplete(() async {
                  await Future<void>.delayed(const Duration(milliseconds: 180));
                  _animationFinished();
                });
            },
          ),
        ),
      ),
    );
  }
}
