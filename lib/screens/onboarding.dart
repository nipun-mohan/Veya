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

class OnboardingScreen extends StatefulWidget {
  final VeyaStore store;
  final bool replay;
  const OnboardingScreen({super.key, required this.store, this.replay = false});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  int step = 0, demo = 0;
  bool busy = false, microphone = false, assistant = false;
  String dial = '+91', error = '';
  final phone = TextEditingController();
  final otp = TextEditingController();
  PhoneProfile? pendingPhone;
  Timer? animation;
  String get number => '$dial${phone.text.replaceAll(RegExp(r'\D'), '')}';
  bool get hasValidPhone => PhoneProfile.parse(dial, phone.text) != null;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    step = widget.store.prefs.getInt('profile_setup_step') ?? 0;
    if (widget.replay || step < 0 || step > 4) step = 0;
    if (step > 2 && widget.store.phoneNumber.isEmpty) step = 1;
    dial = widget.store.phoneCountryCode;
    phone.text = widget.store.phoneNationalNumber;
    animation = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && step == 3) setState(() => demo = (demo + 1) % 4);
    });
    refreshPermissions();
  }

  Future<void> refreshPermissions() async {
    final enabled = await AndroidBridge.call<bool>('isEnabled') ?? false;
    if (mounted) setState(() => assistant = enabled);
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
    super.dispose();
  }

  Future<void> go(int value) async {
    setState(() {
      step = value;
      error = '';
    });
    await widget.store.prefs.setInt('profile_setup_step', value);
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
      if (mounted) {
        await go(3);
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
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: selected ? VeyaColors.soft : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? VeyaColors.teal : Colors.black12),
        ),
        title: LText(label),
        subtitle: subtitle == null ? null : LText(subtitle),
        trailing: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected ? VeyaColors.teal : Colors.black26,
        ),
        onTap: select,
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
              () async {
                await AndroidBridge.call('openAccessibility');
              },
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
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 24, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: busy
                          ? null
                          : () {
                              if (step > 0) {
                                go(step - 1);
                              } else if (widget.replay) {
                                Navigator.pop(context);
                              }
                            },
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: (step + 1) / 5,
                        minHeight: 5,
                        borderRadius: BorderRadius.circular(6),
                        backgroundColor: VeyaColors.soft,
                      ),
                    ),
                  ],
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
                                await go(step + 1);
                              }
                            },
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
