import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'phone_profile.dart';
import 'platform.dart';

class VeyaStore extends ChangeNotifier {
  final SharedPreferences prefs;
  VeyaStore(this.prefs);
  final secure = const FlutterSecureStorage();
  String uiLanguage = 'en-IN';
  String profileName = '';
  String phoneCountryCode = '+91', phoneNationalNumber = '';
  String get phoneNumber => phoneNationalNumber.isEmpty
      ? ''
      : '$phoneCountryCode$phoneNationalNumber';
  String language = 'en-IN', endpoint = '';
  double floatingIconScale = 1, floatingIconOpacity = .9;
  bool onboarded = false;
  List<String> allowedApps = [
    'com.whatsapp',
    'com.google.android.gm',
    'com.google.android.apps.messaging',
    'com.linkedin.android',
  ];
  Future<void> load() async {
    onboarded =
        (prefs.getBool('onboarded') ?? false) &&
        (prefs.getInt('setup_version') ?? 0) >= 3;
    language = prefs.getString('language') ?? 'en-IN';
    if (!languages.any((l) => l.code == language)) language = 'en-IN';
    uiLanguage = prefs.getString('uiLanguage') ?? 'en-IN';
    profileName = prefs.getString('profileName') ?? '';
    if (!languages.any((l) => l.code == uiLanguage)) uiLanguage = 'en-IN';
    final profile = await secure.read(key: 'veya_profile_phone');
    if (profile != null) {
      try {
        final data = jsonDecode(profile) as Map<String, dynamic>;
        final parsed = PhoneProfile.parse(
          data['countryCode'] as String,
          data['nationalNumber'] as String,
        );
        if (parsed != null) {
          phoneCountryCode = parsed.countryCode;
          phoneNationalNumber = parsed.nationalNumber;
        }
      } catch (_) {
        /* Keep setup available if a stored profile is invalid. */
      }
    }
    final savedEndpoint = prefs.getString('endpoint');
    const builtEndpoint = String.fromEnvironment(
      'VEYA_API_URL',
      defaultValue: 'https://veya-gateway-233466884801.asia-south1.run.app',
    );
    // Replace development-only LAN endpoints when the production app updates.
    // A release build may still override this endpoint with --dart-define.
    final normalizedSavedEndpoint = savedEndpoint?.trim() ?? '';
    final savedHost = Uri.tryParse(normalizedSavedEndpoint)?.host ?? '';
    final isDevelopmentEndpoint = savedHost.startsWith('192.168.');
    endpoint = normalizedSavedEndpoint.isNotEmpty && !isDevelopmentEndpoint
        ? normalizedSavedEndpoint
        : builtEndpoint;
    floatingIconScale = (prefs.getDouble('floatingIconScale') ?? 1)
        .clamp(.75, 1.35)
        .toDouble();
    floatingIconOpacity = (prefs.getDouble('floatingIconOpacity') ?? .9)
        .clamp(.35, 1)
        .toDouble();
    allowedApps = prefs.getStringList('allowedApps') ?? allowedApps;
    await syncNative();
    notifyListeners();
  }

  VoiceLanguage get selectedLanguage => languages.firstWhere(
    (l) => l.code == language,
    orElse: () => languages.first,
  );
  Future<void> persist() async {
    await Future.wait([
      prefs.setBool('onboarded', onboarded),
      prefs.setString('language', language),
      prefs.setString('uiLanguage', uiLanguage),
      prefs.setString('profileName', profileName),
      prefs.setString('endpoint', endpoint),
      prefs.setDouble('floatingIconScale', floatingIconScale),
      prefs.setDouble('floatingIconOpacity', floatingIconOpacity),
      prefs.setStringList('allowedApps', allowedApps),
    ]);
    await syncNative();
    notifyListeners();
  }

  Future<void> syncNative() async {
    await AndroidBridge.call('configure', {
      'endpoint': endpoint,
      'language': language,
      'uiLanguage': uiLanguage,
      'allowedApps': allowedApps,
      'floatingIconScale': floatingIconScale,
      'floatingIconOpacity': floatingIconOpacity,
    });
  }

  Future<void> setUiLanguage(String code, {bool setSpeaking = false}) async {
    if (!languages.any((l) => l.code == code)) return;
    uiLanguage = code;
    if (setSpeaking) language = code;
    notifyListeners();
    await persist();
  }

  Future<void> setSpeakingLanguage(String code) async {
    if (!languages.any((l) => l.code == code)) return;
    language = code;
    notifyListeners();
    await persist();
  }

  Future<void> setProfileName(String value) async {
    profileName = value.trim();
    await prefs.setString('profileName', profileName);
    notifyListeners();
  }

  Future<void> setFloatingIconAppearance({
    double? scale,
    double? opacity,
  }) async {
    if (scale != null) floatingIconScale = scale.clamp(.75, 1.35).toDouble();
    if (opacity != null) floatingIconOpacity = opacity.clamp(.35, 1).toDouble();
    // Persist these controls directly. Slider previews may be frequent, but a
    // direct write avoids losing the final value when the app is closed.
    await Future.wait([
      prefs.setDouble('floatingIconScale', floatingIconScale),
      prefs.setDouble('floatingIconOpacity', floatingIconOpacity),
    ]);
    notifyListeners();
    await syncNative();
  }

  Future<void> savePhone(PhoneProfile profile, {bool verified = false}) async {
    await secure.write(
      key: 'veya_profile_phone',
      value: jsonEncode({
        'countryCode': profile.countryCode,
        'nationalNumber': profile.nationalNumber,
        'verified': verified,
      }),
    );
    // A changed profile must never inherit a previously verified session.
    await secure.delete(key: 'veya_account_session');
    await secure.delete(key: 'veya_account_phone');
    phoneCountryCode = profile.countryCode;
    phoneNationalNumber = profile.nationalNumber;
    notifyListeners();
  }
}
