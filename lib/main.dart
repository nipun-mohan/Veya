import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/store.dart';
import 'core/localization.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await VeyaStrings.preload();
  final store = VeyaStore(await SharedPreferences.getInstance());
  // Load appearance and assistant settings before rendering Settings. This
  // prevents a delayed load from replacing a newly adjusted slider value.
  await store.load();
  runApp(VeyaApp(store: store));
}

class VeyaApp extends StatelessWidget {
  final VeyaStore store;
  const VeyaApp({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      title: 'Veya',
      debugShowCheckedModeBanner: false,
      theme: veyaTheme(),
      locale: Locale(store.uiLanguage.split('-').first),
      supportedLocales: VeyaStrings.codes.map((code) => Locale(code)).toList(),
      localizationsDelegates: const [
        VeyaStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: store.onboarded
          ? HomeShell(store: store)
          : OnboardingScreen(store: store),
    ),
  );
}
