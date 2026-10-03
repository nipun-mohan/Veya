import '../core/localization.dart';
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../core/store.dart';
import '../core/models.dart';
import '../core/platform.dart';
import '../core/phone_profile.dart';
import '../core/theme.dart';
import '../widgets/shared.dart';
import 'accessibility_consent.dart';
import 'home.dart';

class OnboardingScreen extends StatefulWidget {
  final VeyaStore store;
  final bool replay;

  /// Used after logout. It keeps the user in the sign-in flow and bypasses
  /// the introductory language and tutorial screens.
  final bool loginOnly;
  const OnboardingScreen({
    super.key,
    required this.store,
    this.replay = false,
    this.loginOnly = false,
  });
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  static const _flow = [1, 2, 0, 3, 4];
  int step = 1, demo = 0;
  bool busy = false, microphone = false, assistant = false;
  bool otpVerified = false;
  String dial = '+91', error = '';
  String? otpRequestId;
  String progress = '';
  int resendSeconds = 0;
  final phone = TextEditingController();
  final otp = TextEditingController();
  final otpFocus = FocusNode();
  PhoneProfile? pendingPhone;
  Timer? animation;
  Timer? resendTimer;
  String get number => '$dial${phone.text.replaceAll(RegExp(r'\D'), '')}';
  bool get hasValidPhone => PhoneProfile.parse(dial, phone.text) != null;
  bool get hasValidOtp => RegExp(r'^\d{6}$').hasMatch(otp.text.trim());
  @override
  void initState() {
    super.initState();
    step = widget.store.prefs.getInt('profile_setup_step') ?? 1;
    otpVerified = widget.store.prefs.getBool('phoneOtpVerified') ?? false;
    // OTP requests intentionally never survive an app restart. The language
    // step is post-verification, however, and must remain resumable.
    if (step == 2 || widget.replay || !_flow.contains(step)) {
      step = 1;
      widget.store.prefs.remove('profile_setup_step');
    }
    if (step > 2 && widget.store.phoneNumber.isEmpty) step = 1;
    dial = widget.store.phoneCountryCode;
    phone.text = otpVerified ? widget.store.phoneNationalNumber : '';
    animation = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && step == 3) setState(() => demo = (demo + 1) % 4);
    });
    if (AndroidBridge.assistantAvailable) {
      WidgetsBinding.instance.addObserver(this);
      AndroidBridge.channel.setMethodCallHandler(_handleNativeEvent);
    }
    if (MicrophonePermissions.available) refreshPermissions();
  }

  Future<dynamic> _handleNativeEvent(MethodCall call) async {
    if (call.method != 'otpReceived' || step != 2 || busy) return null;
    final code = call.arguments?.toString() ?? '';
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return null;
    setState(() {
      otp.text = code;
      error = '';
      progress = '';
    });
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted && step == 2 && !busy) await verifyOtp();
    return null;
  }

  Future<void> refreshPermissions() async {
    final microphoneGranted = await MicrophonePermissions.isGranted();
    final enabled = AndroidBridge.assistantAvailable
        ? await AndroidBridge.call<bool>('isEnabled') ?? false
        : false;
    if (!mounted) return;
    setState(() {
      assistant = enabled;
      microphone = microphoneGranted;
    });
    // Accessibility setup is the last onboarding action. Once Android reports
    // it enabled, leave setup instead of presenting the permission row again.
    if (enabled && step == 4 && !widget.replay) await complete();
  }

  Future<void> openAccessibilitySetup() async {
    if (!AndroidBridge.assistantAvailable) return;
    if (!widget.store.accessibilityConsentAccepted) {
      final accepted = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const AccessibilityConsentScreen()),
      );
      if (accepted != true) return;
      await widget.store.acceptAccessibilityConsent();
    }
    await widget.store.syncNative();
    await AndroidBridge.call('openAccessibility');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (AndroidBridge.assistantAvailable &&
        state == AppLifecycleState.resumed) {
      refreshPermissions();
    }
  }

  @override
  void dispose() {
    if (AndroidBridge.assistantAvailable) {
      WidgetsBinding.instance.removeObserver(this);
    }
    animation?.cancel();
    resendTimer?.cancel();
    phone.dispose();
    otp.dispose();
    otpFocus.dispose();
    super.dispose();
  }

  Future<void> go(int value) async {
    if (value != 2) {
      resendTimer?.cancel();
      resendTimer = null;
    }
    setState(() {
      step = value;
      error = '';
    });
    // Do not persist a pending OTP screen. A code request must begin again
    // after an app restart so that Firebase has a valid verification session.
    if (value == 2) {
      await widget.store.prefs.remove('profile_setup_step');
    } else {
      await widget.store.prefs.setInt('profile_setup_step', value);
    }
    if (AndroidBridge.assistantAvailable) {
      await AndroidBridge.call(
        value == 2 ? 'startOtpListener' : 'stopOtpListener',
      );
    }
  }

  Future<void> advance() async {
    final index = _flow.indexOf(step);
    if (index < _flow.length - 1) await go(_flow[index + 1]);
  }

  Future<void> goBack() async {
    // Language selection is the post-verification boundary. Later setup
    // screens can return to language, but never to the phone or OTP steps.
    if (otpVerified && step == 0) return;
    final index = _flow.indexOf(step);
    if (index > 0)
      await go(_flow[index - 1]);
    else if (widget.replay && mounted)
      Navigator.pop(context);
  }

  void _startResendCountdown() {
    resendTimer?.cancel();
    setState(() => resendSeconds = 30);
    resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => resendSeconds = 0);
        return;
      }
      setState(() => resendSeconds--);
    });
  }

  Future<void> resendCode() async {
    if (busy || resendSeconds > 0) return;
    otp.clear();
    await savePhone(isResend: true);
  }

  Future<void> savePhone({bool isResend = false}) async {
    final profile = PhoneProfile.parse(dial, phone.text);
    if (profile == null) {
      setState(
        () => error = 'Enter a valid phone number, including its country code.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = '';
      progress = isResend
          ? 'Sending a new verification code…'
          : 'Sending your verification code…';
      pendingPhone = profile;
    });
    try {
      // Subscribe before the request so a fast incoming SMS cannot arrive
      // before Android's SMS Retriever is listening for it.
      if (AndroidBridge.assistantAvailable) {
        await AndroidBridge.call('startOtpListener');
      }
      final response = await http.post(
        Uri.parse('${widget.store.endpoint}/v1/auth/otp/send'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'phone': profile.number}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400 || data['otp_id'] == null) {
        throw StateError(
          data['detail'] ?? 'Could not send a verification code.',
        );
      }
      otpRequestId = data['otp_id'] as String;
      if (mounted) {
        if (!isResend) await go(2);
        _startResendCountdown();
        setState(() {
          busy = false;
          progress = '';
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          busy = false;
          progress = '';
          error = _otpRequestError(e);
        });
    }
  }

  String _authError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-phone-number':
        return 'Enter a valid phone number.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'quota-exceeded':
        return 'SMS verification is temporarily unavailable. Please try again later.';
      case 'invalid-verification-code':
        return 'That code is not correct. Please try again.';
      case 'session-expired':
        return 'This code has expired. Request a new code.';
      default:
        return 'Could not verify your number. Please try again.';
    }
  }

  String _otpRequestError(Object error) {
    final text = error.toString();
    if (text.contains('OTP_RATE_LIMITED'))
      return 'Too many codes requested. Please try again later.';
    if (text.contains('INSUFFICIENT_BALANCE'))
      return 'Verification is temporarily unavailable.';
    return 'Could not send a verification code. Please try again.';
  }

  Future<void> _completePhoneVerification(
    UserCredential result,
    PhoneProfile profile,
  ) async {
    if (mounted)
      setState(() {
        busy = true;
        progress = '';
      });
    final user = result.user;
    if (user == null) throw StateError('No signed-in user returned');
    final idToken = await user.getIdToken();
    await widget.store.savePhone(profile, verified: true);
    if (idToken != null) {
      await widget.store.secure.write(
        key: 'veya_firebase_id_token',
        value: idToken,
      );
    }
    await widget.store.secure.write(key: 'veya_firebase_uid', value: user.uid);
    await widget.store.prefs.setBool('phoneOtpVerified', true);
    otpVerified = true;
    if (widget.loginOnly) {
      final microphoneGranted = await MicrophonePermissions.isGranted();
      final assistantEnabled = AndroidBridge.assistantAvailable
          ? await AndroidBridge.call<bool>('isEnabled') ?? false
          : true;
      if (microphoneGranted && assistantEnabled) {
        await complete();
      } else if (mounted) {
        await go(4);
      }
      return;
    }
    if (mounted) await go(0);
  }

  Future<void> verifyOtp() async {
    final profile = pendingPhone ?? PhoneProfile.parse(dial, phone.text);
    final id = otpRequestId;
    if (profile == null) return go(1);
    if (id == null) {
      setState(() => error = 'Request a new code and try again.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(otp.text.trim())) {
      setState(() => error = 'Enter the verification code from your SMS.');
      return;
    }
    setState(() {
      busy = true;
      error = '';
      progress = '';
    });
    try {
      final response = await http.post(
        Uri.parse('${widget.store.endpoint}/v1/auth/otp/verify'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'phone': profile.number, 'code': otp.text.trim()}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['firebase_custom_token'] as String?;
      if (response.statusCode >= 400 || token == null) {
        throw StateError(data['detail'] ?? 'That code is not correct.');
      }
      final result = await FirebaseAuth.instance.signInWithCustomToken(token);
      await _completePhoneVerification(result, profile);
    } on FirebaseAuthException catch (e) {
      if (mounted)
        setState(() {
          progress = '';
          error = _authError(e);
        });
    } catch (e) {
      if (mounted) {
        setState(() {
          progress = '';
          error = e.toString().contains('VERIFY_RATE_LIMITED')
              ? 'Too many incorrect attempts. Request a new code.'
              : 'That code is not correct. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> complete() async {
    widget.store.onboarded = true;
    await widget.store.prefs.setInt('setup_version', 3);
    await widget.store.prefs.remove('profile_setup_step');
    await widget.store.persist();
    if (widget.loginOnly && mounted) {
      // Start a fresh shell so the prior Settings tab cannot remain selected.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeShell(store: widget.store)),
        (_) => false,
      );
      return;
    }
    if (widget.replay && mounted) Navigator.pop(context);
  }

  Widget _otpScreen() => Scaffold(
    backgroundColor: VeyaColors.paper,
    bottomNavigationBar: SafeArea(
      top: false,
      child: SizedBox(
        height: 56,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: VeyaColors.ink.withValues(alpha: .9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x160F0322),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Image.asset(
              'assets/branding/powered-by-minimoth.png',
              width: 218,
              semanticLabel: 'Powered by MiniMoth.dev',
            ),
          ),
        ),
      ),
    ),
    body: TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  onPressed: busy ? null : () => go(1),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              const SizedBox(height: 34),
              const Eyebrow('VERIFY YOUR NUMBER'),
              const SizedBox(height: 14),
              const LText(
                'Let’s make\nsure it’s you.',
                style: TextStyle(
                  fontSize: 39,
                  height: 1.03,
                  letterSpacing: -2.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              LText(
                'We sent a 6-digit code to\n$number',
                style: const TextStyle(
                  color: VeyaColors.muted,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: VeyaColors.line),
                ),
                child: Column(
                  children: [
                    if (progress.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            if (busy) const VeyaLoader(),
                            if (busy) const SizedBox(width: 10),
                            Expanded(
                              child: LText(
                                progress,
                                style: const TextStyle(
                                  color: VeyaColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    GestureDetector(
                      onTap: () => otpFocus.requestFocus(),
                      child: Stack(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(
                              6,
                              (i) => SizedBox(
                                width: 42,
                                height: 56,
                                child: _OtpCell(
                                  value: i < otp.text.length ? otp.text[i] : '',
                                  active: i == otp.text.length,
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Opacity(
                              opacity: .01,
                              child: TextField(
                                controller: otp,
                                focusNode: otpFocus,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                autofocus: true,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (_) => setState(() => error = ''),
                                onSubmitted: (_) {
                                  if (!busy) verifyOtp();
                                },
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  counterText: '',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: LText(
                          error,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: busy || !hasValidOtp ? null : verifyOtp,
                        child: busy
                            ? const VeyaLoader()
                            : const LText('Verify code'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy || resendSeconds > 0 ? null : resendCode,
                      child: LText(
                        resendSeconds > 0
                            ? 'Resend code in 00:${resendSeconds.toString().padLeft(2, '0')}'
                            : 'Resend code',
                        style: TextStyle(
                          color: resendSeconds > 0
                              ? VeyaColors.muted
                              : VeyaColors.ink,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Center(
                child: TextButton(
                  onPressed: busy ? null : () => go(1),
                  child: const LText(
                    'Wrong number?  Edit number',
                    style: TextStyle(
                      color: VeyaColors.ink,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LText(title, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 12),
      LText(
        subtitle,
        style: const TextStyle(
          color: VeyaColors.muted,
          fontSize: 15,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 24),
    ],
  );
  Widget choice(
    String label,
    bool selected,
    VoidCallback select, {
    String? subtitle,
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: !enabled
          ? const Color(0xFFF3F0EB)
          : selected
          ? VeyaColors.soft
          : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: !enabled
                ? Colors.black12
                : selected
                ? VeyaColors.teal
                : Colors.black12,
          ),
        ),
        enabled: enabled,
        title: LText(
          label,
          style: TextStyle(color: enabled ? null : VeyaColors.muted),
        ),
        subtitle: subtitle == null ? null : LText(subtitle),
        trailing: Icon(
          !enabled
              ? Icons.radio_button_unchecked
              : selected
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          color: !enabled
              ? VeyaColors.muted
              : selected
              ? VeyaColors.teal
              : Colors.black26,
        ),
        onTap: enabled ? select : null,
      ),
    ),
  );
  Widget hero() => Container(
    constraints: const BoxConstraints(minHeight: 180),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: VeyaColors.ink,
      borderRadius: BorderRadius.circular(28),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            VeyaMark(size: 40),
            SizedBox(width: 12),
            LText(
              'veya',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: 24),
        LText(
          'A little less typing.\nA little more you.',
          style: TextStyle(
            color: VeyaColors.lime,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
  Widget tutorial() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: VeyaColors.soft,
      borderRadius: BorderRadius.circular(28),
    ),
    child: Column(
      children: [
        const Row(
          children: [
            CircleAvatar(child: Icon(Icons.person_outline)),
            SizedBox(width: 12),
            Expanded(
              child: LText(
                'A conversation',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Align(
          alignment: Alignment.centerLeft,
          child: Chip(label: LText('Are we still meeting tomorrow?')),
        ),
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: Container(
            key: ValueKey(demo),
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 124),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: VeyaColors.ink,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                LText(
                  [
                    'Tap the floating icon',
                    'Speak in your language',
                    'Your English is ready',
                    'Copy or insert. You send.',
                  ][demo],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                if (demo == 0)
                  const Icon(Icons.graphic_eq, color: VeyaColors.lime, size: 42)
                else if (demo == 1)
                  const Waveform()
                else
                  const Text(
                    'Yes, tomorrow works. See you at 10!',
                    style: TextStyle(color: VeyaColors.lime, fontSize: 16),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const LText(
          'Interactive walkthrough · no message is sent',
          style: TextStyle(fontSize: 11, color: VeyaColors.muted),
        ),
      ],
    ),
  );
  Future<void> countries() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      // Flutter's route-level drag dismissal can leave inherited widgets
      // attached on iOS. Keep the familiar handle, but dismiss explicitly.
      enableDrag: false,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 430,
          child: Column(
            children: [
              _SheetDismissHandle(onDismiss: () => Navigator.pop(sheetContext)),
              Expanded(
                child: ListView(
                  children: [
                    const ListTile(
                      title: LText(
                        'Country code',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    for (final item in const [
                      ('🇮🇳', 'India', '+91'),
                      ('🇺🇸', 'United States', '+1'),
                      ('🇩🇪', 'Germany', '+49'),
                      ('🇨🇦', 'Canada', '+1'),
                      ('🇦🇪', 'United Arab Emirates', '+971'),
                    ])
                      ListTile(
                        leading: _CountryFlag(flag: item.$1),
                        title: LText(item.$2),
                        trailing: Text(item.$3),
                        onTap: () => Navigator.pop(sheetContext, item.$3),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selection == null) return;
    setState(() => dial = selection);
  }

  List<Widget> content() {
    switch (step) {
      case 0:
        return [
          heading(
            'Choose your speaking language.',
            'Veya will use this language to understand your voice. You can change it later in Settings.',
          ),
          for (final language in languages)
            choice(
              language.native,
              widget.store.language == language.code,
              () async {
                await widget.store.setSpeakingLanguage(language.code);
                if (mounted) setState(() {});
              },
              subtitle: language.name,
            ),
          if (widget.store.uiLanguage == 'ml-IN')
            const LText(
              'Malayalam and the other listed languages are available for selection. Connect a Veya translation service to translate speech.',
            ),
        ];
      case 1:
        return [
          hero(),
          const SizedBox(height: 28),
          heading(
            'Your phone number.',
            'We’ll send a code to confirm this number.',
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                height: 56,
                child: OutlinedButton(
                  onPressed: busy ? null : countries,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: Text('$dial ▾'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(14),
                  ],
                  decoration: InputDecoration(
                    labelText: t(context, 'Phone number'),
                    labelStyle: error.isEmpty
                        ? null
                        : const TextStyle(color: Colors.redAccent),
                    enabledBorder: error.isEmpty
                        ? null
                        : OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Colors.redAccent,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                    focusedBorder: error.isEmpty
                        ? null
                        : OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: Colors.redAccent,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                  ),
                  onChanged: (_) {
                    setState(() => error = '');
                  },
                  onSubmitted: (_) {
                    if (!busy) savePhone();
                  },
                ),
              ),
            ],
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 88, top: 8),
              child: LText(
                t(context, error),
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          const SizedBox(height: 18),
          const LText(
            'Your number is stored securely on this device and used only to verify your Veya profile.',
          ),
        ];
      case 2:
        return [
          hero(),
          const SizedBox(height: 28),
          heading(
            'Verify your number.',
            'Enter the 4-digit code sent to $number. For this test build, use 1111.',
          ),
          TextField(
            controller: otp,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Verification code',
              hintText: '1111',
              errorText: error.isEmpty ? null : error,
            ),
            onSubmitted: (_) {
              if (!busy) verifyOtp();
            },
          ),
          const SizedBox(height: 18),
          const LText(
            'SMS delivery will be connected before release. This build uses a temporary test code.',
            style: TextStyle(color: VeyaColors.muted, height: 1.5),
          ),
        ];
      case 3:
        return [
          heading(
            'Meet your little voice companion.',
            'Tap. Speak. Review. Insert. Stay right in your conversation.',
          ),
          tutorial(),
        ];
      case 4:
        if (!AndroidBridge.assistantAvailable) {
          return [
            heading(
              'You’re always in control.',
              'Enable microphone access before you choose to dictate.',
            ),
            choice('Microphone', microphone, () async {
              final granted = await MicrophonePermissions.request();
              if (mounted) {
                setState(() {
                  microphone = granted;
                  if (!granted) {
                    error =
                        'Microphone access can be enabled later in iPhone Settings.';
                  } else {
                    error = '';
                  }
                });
              }
            }, subtitle: 'Records only when you choose to speak.'),
            const SizedBox(height: 18),
            const LText(
              'Veya never listens in the background. You can change microphone access anytime in iPhone Settings.',
              style: TextStyle(color: VeyaColors.muted, height: 1.5),
            ),
          ];
        }
        return [
          heading(
            'You’re always in control.',
            'Enable only what you want to use.',
          ),
          choice('Microphone', microphone, () async {
            final granted = await MicrophonePermissions.request();
            if (mounted) {
              setState(() {
                microphone = granted;
                if (!granted) {
                  error =
                      'Microphone access can also be enabled when you record.';
                }
              });
            }
          }, subtitle: 'Records only when you choose to speak.'),
          choice(
            'Floating assistant',
            assistant,
            openAccessibilitySetup,
            subtitle: 'Open Installed apps → Veya floating assistant → Enable.',
          ),
          const SizedBox(height: 18),
          const LText(
            'Accessibility finds text fields in chosen apps, excluding passwords. It reads the active field only when you tap Insert, and never presses Send. Disable it anytime in Android settings.',
            style: TextStyle(color: VeyaColors.muted, height: 1.5),
          ),
        ];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (step == 2) return _otpScreen();
    final showProgress = _flow.indexOf(step) >= _flow.indexOf(0);
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  children: [
                    if (showProgress)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 24, 8),
                        child: Row(
                          children: [
                            if (step != 0)
                              IconButton(
                                onPressed: busy ? null : goBack,
                                icon: const Icon(Icons.arrow_back_rounded),
                              )
                            else
                              const SizedBox(width: 12),
                            Expanded(
                              child: LinearProgressIndicator(
                                value:
                                    (_flow.indexOf(step) -
                                        _flow.indexOf(0) +
                                        1) /
                                    (_flow.length - _flow.indexOf(0)),
                                minHeight: 5,
                                borderRadius: BorderRadius.circular(6),
                                backgroundColor: VeyaColors.soft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!showProgress && step != 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 24, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            onPressed: busy ? null : goBack,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                      ),
                    Expanded(
                      child: KeyedSubtree(
                        key: ValueKey('onboarding-content-$step'),
                        child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            ...content(),
                            if (error.isNotEmpty && step != 1 && step != 2)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: LText(
                                  error,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton(
                            onPressed:
                                busy ||
                                    (step == 1 && !hasValidPhone) ||
                                    (step == 2 && !hasValidOtp)
                                ? null
                                : () async {
                                    if (step == 1) {
                                      await savePhone();
                                    } else if (step == 2) {
                                      await verifyOtp();
                                    } else if (step == 4) {
                                      await complete();
                                    } else {
                                      await advance();
                                    }
                                  },
                            child: busy
                                ? const VeyaLoader()
                                : LText(
                                    [
                                      'Continue',
                                      'Get OTP',
                                      'Verify number',
                                      'Continue',
                                      'Get started',
                                    ][step],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetDismissHandle extends StatelessWidget {
  final VoidCallback onDismiss;
  const _SheetDismissHandle({required this.onDismiss});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragEnd: (details) {
      if ((details.primaryVelocity ?? 0) > 0) onDismiss();
    },
    child: SizedBox(
      height: 34,
      width: double.infinity,
      child: Center(
        child: Container(
          width: 34,
          height: 4,
          decoration: BoxDecoration(
            color: VeyaColors.muted.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    ),
  );
}

class _CountryFlag extends StatelessWidget {
  final String flag;
  const _CountryFlag({required this.flag});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 20,
    child: CustomPaint(painter: _CountryFlagPainter(flag)),
  );
}

class _CountryFlagPainter extends CustomPainter {
  final String flag;
  const _CountryFlagPainter(this.flag);

  @override
  void paint(Canvas canvas, Size size) {
    final clip = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );
    canvas.save();
    canvas.clipRRect(clip);
    final paint = Paint();
    void fill(Color color, Rect rect) {
      paint.color = color;
      canvas.drawRect(rect, paint);
    }

    switch (flag) {
      case '🇮🇳':
        fill(
          const Color(0xFFFF9933),
          Rect.fromLTWH(0, 0, size.width, size.height / 3),
        );
        fill(
          Colors.white,
          Rect.fromLTWH(0, size.height / 3, size.width, size.height / 3),
        );
        fill(
          const Color(0xFF138808),
          Rect.fromLTWH(0, size.height * 2 / 3, size.width, size.height / 3),
        );
        paint
          ..color = const Color(0xFF000080)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawCircle(Offset(size.width / 2, size.height / 2), 3, paint);
        break;
      case '🇺🇸':
        for (var index = 0; index < 7; index++) {
          fill(
            index.isEven ? const Color(0xFFB22234) : Colors.white,
            Rect.fromLTWH(
              0,
              index * size.height / 7,
              size.width,
              size.height / 7,
            ),
          );
        }
        fill(
          const Color(0xFF3C3B6E),
          Rect.fromLTWH(0, 0, size.width * .45, size.height * .54),
        );
        break;
      case '🇩🇪':
        fill(Colors.black, Rect.fromLTWH(0, 0, size.width, size.height / 3));
        fill(
          const Color(0xFFDD0000),
          Rect.fromLTWH(0, size.height / 3, size.width, size.height / 3),
        );
        fill(
          const Color(0xFFFFCE00),
          Rect.fromLTWH(0, size.height * 2 / 3, size.width, size.height / 3),
        );
        break;
      case '🇨🇦':
        fill(
          const Color(0xFFEF2B2D),
          Rect.fromLTWH(0, 0, size.width * .26, size.height),
        );
        fill(
          Colors.white,
          Rect.fromLTWH(size.width * .26, 0, size.width * .48, size.height),
        );
        fill(
          const Color(0xFFEF2B2D),
          Rect.fromLTWH(size.width * .74, 0, size.width * .26, size.height),
        );
        paint.color = const Color(0xFFEF2B2D);
        canvas.drawPath(
          Path()
            ..moveTo(size.width / 2, 3)
            ..lineTo(size.width * .56, size.height * .43)
            ..lineTo(size.width * .67, size.height * .38)
            ..lineTo(size.width * .57, size.height * .57)
            ..lineTo(size.width * .62, size.height * .7)
            ..lineTo(size.width / 2, size.height - 2)
            ..lineTo(size.width * .38, size.height * .7)
            ..lineTo(size.width * .43, size.height * .57)
            ..lineTo(size.width * .33, size.height * .38)
            ..lineTo(size.width * .44, size.height * .43)
            ..close(),
          paint,
        );
        break;
      case '🇦🇪':
        fill(
          const Color(0xFFEF3340),
          Rect.fromLTWH(0, 0, size.width * .25, size.height),
        );
        fill(
          const Color(0xFF009739),
          Rect.fromLTWH(size.width * .25, 0, size.width * .75, size.height / 3),
        );
        fill(
          Colors.white,
          Rect.fromLTWH(
            size.width * .25,
            size.height / 3,
            size.width * .75,
            size.height / 3,
          ),
        );
        fill(
          Colors.black,
          Rect.fromLTWH(
            size.width * .25,
            size.height * 2 / 3,
            size.width * .75,
            size.height / 3,
          ),
        );
        break;
    }
    canvas.restore();
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = const Color(0x220F0322);
    canvas.drawRRect(clip, paint);
  }

  @override
  bool shouldRepaint(covariant _CountryFlagPainter oldDelegate) =>
      oldDelegate.flag != flag;
}

class _OtpArtwork extends CustomPainter {
  const _OtpArtwork();
  @override
  void paint(Canvas c, Size s) {
    c.drawPath(
      Path()
        ..moveTo(s.width * .36, 0)
        ..lineTo(s.width, 0)
        ..lineTo(s.width, s.height * .7)
        ..quadraticBezierTo(s.width * .7, s.height * .42, s.width * .36, 0)
        ..close(),
      Paint()..color = VeyaColors.mango,
    );
    c.drawPath(
      Path()
        ..moveTo(s.width * .35, s.height * .2)
        ..quadraticBezierTo(
          s.width * .9,
          s.height * .15,
          s.width * .96,
          s.height * .62,
        )
        ..quadraticBezierTo(
          s.width * .86,
          s.height * .8,
          s.width * .57,
          s.height * .55,
        )
        ..close(),
      Paint()..color = VeyaColors.orange,
    );
    final p = Paint()..color = VeyaColors.lavender;
    c.save();
    c.translate(s.width * .38, s.height * .48);
    c.rotate(.55);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 20, 76),
        const Radius.circular(12),
      ),
      p,
    );
    c.translate(35, 25);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 22, 76),
        const Radius.circular(12),
      ),
      p,
    );
    c.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OtpCell extends StatelessWidget {
  final String value;
  final bool active;
  const _OtpCell({required this.value, required this.active});
  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: VeyaColors.peach,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: active ? VeyaColors.orange : Colors.transparent,
        width: active ? 2 : 1,
      ),
    ),
    child: LText(
      value,
      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
    ),
  );
}
