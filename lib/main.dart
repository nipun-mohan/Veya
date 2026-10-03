import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Firebase.initializeApp();
    await VeyaStrings.preload();
    final store = VeyaStore(await SharedPreferences.getInstance());
    // Load appearance and assistant settings before rendering Settings. This
    // prevents a delayed load from replacing a newly adjusted slider value.
    await store.load();
    // Require one real Firebase verification before granting access to the
    // protected flow.
    if (store.onboarded && FirebaseAuth.instance.currentUser == null) {
      store.onboarded = false;
      await store.persist();
    }
    if (mounted) setState(() => _store = store);
  }

  @override
  Widget build(BuildContext context) => VeyaApp(store: _store);
}

class VeyaApp extends StatelessWidget {
  final VeyaStore? store;
  const VeyaApp({super.key, required this.store});
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
      home: VeyaSplash(
        ready: current != null,
        child: current == null
            ? const SizedBox.shrink()
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    // If the asset ever fails to decode, users still reach the app promptly.
    _fallback = Timer(const Duration(seconds: 5), _animationFinished);
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
    if (!_animationDone || !widget.ready) return;
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
