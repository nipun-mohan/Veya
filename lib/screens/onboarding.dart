import '../core/localization.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/store.dart';
import '../core/models.dart';
import '../core/platform.dart';
import '../core/phone_profile.dart';
import '../core/theme.dart';
import '../widgets/shared.dart';
import 'accessibility_consent.dart';

class OnboardingScreen extends StatefulWidget {
  final VeyaStore store;
  final bool replay;
  const OnboardingScreen({super.key, required this.store, this.replay = false});
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
  final phone = TextEditingController();
  final otp = TextEditingController();
  final otpFocus = FocusNode();
  PhoneProfile? pendingPhone;
  Timer? animation;
  String get number => '$dial${phone.text.replaceAll(RegExp(r'\D'), '')}';
  bool get hasValidPhone => PhoneProfile.parse(dial, phone.text) != null;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    step = widget.store.prefs.getInt('profile_setup_step') ?? 1;
    otpVerified = widget.store.prefs.getBool('phoneOtpVerified') ?? false;
    // New onboarding verifies the phone before language and setup choices.
    if (step == 0 || widget.replay || !_flow.contains(step)) step = 1;
    if (step > 2 && widget.store.phoneNumber.isEmpty) step = 1;
    dial = widget.store.phoneCountryCode;
    phone.text = widget.store.phoneNationalNumber;
    animation = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && step == 3) setState(() => demo = (demo + 1) % 4);
    });
    if (AndroidBridge.assistantAvailable) {
      AndroidBridge.channel.setMethodCallHandler(_handleNativeEvent);
      if (step == 2) {
        Future<void>.microtask(() => AndroidBridge.call('startOtpListener'));
      }
    }
    refreshPermissions();
  }

  Future<dynamic> _handleNativeEvent(MethodCall call) async {
    if (call.method != 'otpReceived' || step != 2 || busy) return null;
    final code = call.arguments?.toString() ?? '';
    if (!RegExp(r'^\d{4}$').hasMatch(code)) return null;
    setState(() {
      otp.text = code;
      error = '';
    });
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (mounted && step == 2 && !busy) await verifyOtp();
    return null;
  }

  Future<void> refreshPermissions() async {
    final values = await Future.wait([
      AndroidBridge.call<bool>('isEnabled'),
      AndroidBridge.call<bool>('isMicrophoneGranted'),
    ]);
    final enabled = values[0] ?? false;
    final microphoneGranted = values[1] ?? false;
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
        MaterialPageRoute(
          builder: (_) => const AccessibilityConsentScreen(),
        ),
      );
      if (accepted != true) return;
      await widget.store.acceptAccessibilityConsent();
    }
    await widget.store.syncNative();
    await AndroidBridge.call('openAccessibility');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    animation?.cancel();
    phone.dispose();
    otp.dispose();
    otpFocus.dispose();
    super.dispose();
  }

  Future<void> go(int value) async {
    setState(() {
      step = value;
      error = '';
    });
    await widget.store.prefs.setInt('profile_setup_step', value);
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

  Future<void> savePhone() async {
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
    });
    try {
      pendingPhone = profile;
      if (mounted) await go(2);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save your number. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verifyOtp() async {
    final profile = pendingPhone ?? PhoneProfile.parse(dial, phone.text);
    if (profile == null) {
      return go(1);
    }
    if (otp.text.trim() != '1111') {
      setState(() => error = 'That code is not correct. Try 1111.');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.store.savePhone(profile, verified: true);
      await widget.store.prefs.setBool('phoneOtpVerified', true);
      otpVerified = true;
      if (mounted) {
        await go(0);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not verify your number. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> complete() async {
    widget.store.onboarded = true;
    await widget.store.prefs.setInt('setup_version', 3);
    await widget.store.prefs.remove('profile_setup_step');
    await widget.store.persist();
    if (widget.replay && mounted) Navigator.pop(context);
  }

  Widget _otpScreen() => Scaffold(
    backgroundColor: VeyaColors.paper,
    body: SafeArea(
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
              'We sent a 4-digit code to\n$number',
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
                  GestureDetector(
                    onTap: () => otpFocus.requestFocus(),
                    child: Stack(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(
                            4,
                            (i) => SizedBox(
                              width: 62,
                              height: 62,
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
                              maxLength: 4,
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
                      onPressed: busy ? null : verifyOtp,
                      style: FilledButton.styleFrom(
                        backgroundColor: VeyaColors.ink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: busy
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const LText(
                              'Verify code',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const LText(
                    'Resend code in 00:24',
                    style: TextStyle(
                      color: VeyaColors.muted,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w700,
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
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 430,
          child: ListView(
            children: [
              const ListTile(
                title: LText(
                  'Country code',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              for (final item in const [
                ('🇮🇳 India', '+91'),
                ('🇺🇸 United States', '+1'),
                ('🇩🇪 Germany', '+49'),
                ('🇨🇦 Canada', '+1'),
                ('🇦🇪 United Arab Emirates', '+971'),
              ])
                ListTile(
                  title: LText(item.$1),
                  trailing: Text(item.$2),
                  onTap: () => Navigator.pop(context, item.$2),
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
            children: [
              OutlinedButton(
                onPressed: busy ? null : countries,
                child: Text('$dial ▾'),
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
                    errorText: error.isEmpty ? null : t(context, error),
                    errorMaxLines: 4,
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
        return [
          heading(
            'You’re always in control.',
            'Enable only what you want to use.',
          ),
          choice('Microphone', microphone, () async {
            final granted =
                await AndroidBridge.call<bool>('requestMicrophone') ?? false;
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
          if (AndroidBridge.assistantAvailable)
            choice(
              'Floating assistant',
              assistant,
              openAccessibilitySetup,
              subtitle:
                  'Open Installed apps → Veya floating assistant → Enable.',
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
      body: SafeArea(
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
                            value: (_flow.indexOf(step) - _flow.indexOf(0) + 1) /
                                (_flow.length - _flow.indexOf(0)),
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(6),
                            backgroundColor: VeyaColors.soft,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!showProgress)
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
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      ...content(),
                      if (error.isNotEmpty && step != 1 && step != 2)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: LText(
                            error,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: busy || (step == 1 && !hasValidPhone)
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
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
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
    );
  }
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
