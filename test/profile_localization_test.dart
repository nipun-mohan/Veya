import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veya/core/localization.dart';
import 'package:veya/core/platform.dart';
import 'package:veya/core/models.dart';
import 'package:veya/core/phone_profile.dart';
import 'package:veya/core/store.dart';
import 'package:veya/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(VeyaStrings.preload);
  final nativeCalls = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    nativeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('app.veya/assistant'), (
          call,
        ) async {
          nativeCalls.add(call);
          if (call.method == 'drainHistory') return '[]';
          if (call.method == 'isEnabled') return false;
          return null;
        });
  });

  test(
    'Phone validation handles country lengths without claiming verification',
    () {
      expect(PhoneProfile.parse('+91', '98765 43210')?.number, '+919876543210');
      expect(PhoneProfile.parse('+91', '1234567890'), isNull);
      expect(PhoneProfile.parse('+91', '987654321'), isNull);
      expect(PhoneProfile.parse('+1', '2025550123')?.number, '+12025550123');
      expect(PhoneProfile.parse('+0', '12345678'), isNull);
      expect(PhoneProfile.parse('+44', 'abcdefghi'), isNull);
      expect(PhoneProfile.parse('+971', '12345678901234'), isNull);
    },
  );

  test('All bundled catalogs have every key and matching placeholders', () {
    final source =
        jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map;
    Set<String> placeholders(String value) =>
        RegExp(r'\{\w+\}').allMatches(value).map((m) => m[0]!).toSet();
    for (final code in VeyaStrings.codes) {
      final target =
          jsonDecode(File('assets/i18n/$code.json').readAsStringSync()) as Map;
      expect(target.keys.toSet(), source.keys.toSet(), reason: code);
      for (final key in source.keys) {
        expect(
          (target[key] as String).trim(),
          isNotEmpty,
          reason: '$code: $key',
        );
        expect(
          placeholders(target[key]),
          placeholders(source[key]),
          reason: '$code: $key',
        );
        if (code != 'en') {
          expect(target[key], isNot(source[key]), reason: '$code: $key');
        }
      }
    }
  });

  test(
    'Profile is encrypted locally, unverified, and survives reload',
    () async {
      final store = VeyaStore(await SharedPreferences.getInstance());
      await store.secure.write(
        key: 'veya_account_session',
        value: 'old-session',
      );
      await store.savePhone(PhoneProfile.parse('+91', '9876543210')!);
      expect(await store.secure.read(key: 'veya_account_session'), isNull);
      expect(store.prefs.getKeys().any((key) => key.contains('phone')), false);
      final profile = jsonDecode(
        (await store.secure.read(key: 'veya_profile_phone'))!,
      );
      expect(profile['verified'], false);
      final restored = VeyaStore(await SharedPreferences.getInstance());
      await restored.load();
      expect(restored.phoneNumber, '+919876543210');
      expect(restored.onboarded, false);
    },
  );

  testWidgets(
    'Language changes immediately, phone required, no OTP, resume retains profile',
    (tester) async {
      final store = VeyaStore(await SharedPreferences.getInstance());
      await tester.pumpWidget(VeyaApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Choose your language.'), findsOneWidget);
      await tester.tap(find.text('हिन्दी'));
      await tester.pumpAndSettle();
      expect(find.text('अपनी भाषा चुनें।'), findsOneWidget);
      await tester.tap(find.text('आगे बढ़ें'));
      await tester.pumpAndSettle();
      expect(find.text('आपका फ़ोन नंबर।'), findsOneWidget);
      await tester.tap(find.text('सहेजें और आगे बढ़ें'));
      await tester.pumpAndSettle();
      expect(find.text('देश के कोड सहित सही फ़ोन नंबर डालें।'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.tap(find.text('सहेजें और आगे बढ़ें'));
      await tester.pumpAndSettle();
      expect(store.phoneNumber, '+919876543210');
      expect(find.textContaining('WhatsApp'), findsNothing);
      expect(store.prefs.getInt('profile_setup_step'), 2);
      expect(store.prefs.getString('uiLanguage'), 'hi-IN');
      if (AndroidBridge.assistantAvailable) {
        expect(
        nativeCalls
            .where((c) => c.method == 'configure')
            .last
            .arguments['uiLanguage'],
        'hi-IN',
      );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      final restored = VeyaStore(await SharedPreferences.getInstance());
      await restored.load();
      expect(restored.uiLanguage, 'hi-IN');
      await tester.pumpWidget(VeyaApp(store: restored));
      await tester.pumpAndSettle();
      expect(find.text('Veya में आपका स्वागत है।'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final code in VeyaStrings.codes) {
    testWidgets(
      '$code: small phone onboarding, home and settings are localized',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = VeyaStore(await SharedPreferences.getInstance());
        store.uiLanguage = '$code-IN';
        final strings = Map<String, String>.from(
          jsonDecode(File('assets/i18n/$code.json').readAsStringSync()) as Map,
        );
        await tester.pumpWidget(VeyaApp(store: store));
        await tester.pumpAndSettle();
        expect(find.text(strings['Choose your language.']!), findsOneWidget);
        await tester.tap(find.text(strings['Continue']!));
        await tester.pumpAndSettle();
        expect(find.text(strings['Your phone number.']!), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        store.onboarded = true;
        store.entries = [
          Entry(
            id: 'sample',
            source: 'Settings',
            text: 'Settings',
            language: 'en-IN',
            tone: 'Offline',
            mode: 'translate',
            created: DateTime.now(),
          ),
        ];
        await tester.pumpWidget(VeyaApp(store: store));
        await tester.pumpAndSettle();
        expect(find.text(strings['Home']!), findsOneWidget);
        await tester.tap(find.text(strings['History']!));
        await tester.pumpAndSettle();
        // Interface translation must not alter user messages, even if they match a UI key.
        expect(
          find.text('Settings'),
          code == 'en' ? findsNWidgets(2) : findsOneWidget,
        );
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(strings['Settings']!)));
        await tester.pumpAndSettle();
        expect(find.text(strings['App language']!), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
