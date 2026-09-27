import 'package:veya/core/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veya/core/store.dart';
import 'package:veya/core/models.dart';
import 'package:veya/main.dart';
import 'package:veya/core/api.dart';
import 'package:veya/core/theme.dart';
import 'package:veya/screens/composer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(VeyaStrings.preload);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (call) async => 1,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('app.veya/assistant'), (
          call,
        ) async {
          if (call.method == 'drainHistory') return '[]';
          if (call.method == 'isEnabled') return false;
          return null;
        });
  });
  Future<VeyaStore> store() async =>
      VeyaStore(await SharedPreferences.getInstance());
  Future<void> screen(
    WidgetTester tester,
    VeyaStore data, {
    double width = 430,
    Widget? home,
  }) async {
    tester.view.physicalSize = Size(width, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await tester.pumpWidget(
      home == null
          ? VeyaApp(store: data)
          : MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: veyaTheme(),
              home: home,
            ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Language first, phone and tour visual previews', (t) async {
    final s = await store();
    await screen(t, s, width: 390);
    expect(find.text('Choose your language.'), findsOneWidget);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/onboarding-language.png'),
    );
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Your phone number.'), findsOneWidget);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/onboarding-phone.png'),
    );
    await t.enterText(find.byType(TextField), '9876543210');
    await t.tap(find.text('Save & continue'));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/onboarding-tour.png'),
    );
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Onboarding persists completion and language selection', (
    t,
  ) async {
    final s = await store();
    await screen(t, s);
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '9876543210');
    await t.tap(find.text('Save & continue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Friends & family'));
    await t.pumpAndSettle();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    await t.tap(find.text('Get started'));
    await t.pumpAndSettle();
    expect(s.onboarded, true);
    expect(s.prefs.getBool('onboarded'), true);
    expect(find.text('Good words start\nwith you.'), findsOneWidget);
    await t.tap(find.text('English').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Tamil'));
    await t.pumpAndSettle();
    expect(s.language, 'ta-IN');
    expect(s.prefs.getString('language'), 'ta-IN');
    expect(t.takeException(), isNull);
  });
  testWidgets('Home renders at phone size', (t) async {
    final s = await store();
    s.onboarded = true;
    await screen(t, s);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../preview/home.png'),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('Tabs, history search and bookmark work', (t) async {
    final s = await store();
    s.onboarded = true;
    s.entries = [
      Entry(
        id: '1',
        source: 'A project update',
        text: 'The proposal is ready for your review.',
        language: 'en-IN',
        tone: 'Professional',
        mode: 'draft',
        created: DateTime(2026, 9, 13, 9, 30),
      ),
    ];
    await screen(t, s);
    await t.tap(find.text('History'));
    await t.pumpAndSettle();
    expect(find.text('The proposal is ready for your review.'), findsOneWidget);
    await t.tap(find.byTooltip('Bookmark'));
    await t.pumpAndSettle();
    expect(s.entries.first.favorite, true);
    await t.enterText(find.byType(TextField).first, 'missing');
    await t.pumpAndSettle();
    expect(find.text('Room for a new thought.'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '');
    await t.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../preview/history.png'),
    );
    await t.tap(find.text('Dictionary'));
    await t.pumpAndSettle();
    expect(find.text('Some words are\nuniquely yours.'), findsOneWidget);
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    expect(find.text('Make yourself\nat home.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('Dictionary validates and saves words', (t) async {
    final s = await store();
    s.onboarded = true;
    await screen(t, s);
    await t.tap(find.text('Dictionary'));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../preview/dictionary.png'),
    );
    await t.tap(find.text('Add a word'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save word'));
    await t.pumpAndSettle();
    expect(find.text('Please enter a word.'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).first, 'Nipun');
    await t.enterText(find.byType(TextFormField).last, 'A colleague');
    await t.tap(find.text('Save word'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 1));
    expect(s.words.single.spelling, 'Nipun');
    expect(t.takeException(), isNull);
  });
  testWidgets('Small phone has no layout overflow', (t) async {
    final s = await store();
    s.onboarded = true;
    await screen(t, s, width: 320);
    for (final tab in ['History', 'Dictionary', 'Settings', 'Home']) {
      await t.tap(find.text(tab));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
  });
  testWidgets(
    'Composer transforms, saves and clears stale output after editing',
    (t) async {
      final s = await store();
      s.onboarded = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            VeyaApi.channel,
            (_) async => 'Could we meet tomorrow?',
          );
      await screen(
        t,
        s,
        home: ComposerScreen(
          store: s,
          initial: 'can we meet tomorrow',
          apiFactory: () => VeyaApi(),
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../preview/composer.png'),
      );
      await t.scrollUntilVisible(
        find.text('Translate with Google'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Translate with Google'));
      await t.pumpAndSettle();
      expect(s.entries.single.text, 'Could we meet tomorrow?');
      expect(s.draft, isEmpty);
      await t.scrollUntilVisible(
        find.text('ENGLISH TRANSLATION'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('Could we meet tomorrow?'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../preview/result.png'),
      );
      await t.scrollUntilVisible(
        find.text('YOUR WORDS'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'A different message');
      await t.pump(const Duration(seconds: 1));
      expect(s.draft, 'A different message');
      expect(find.text('Could we meet tomorrow?'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Missing offline model keeps the draft and shows the error', (
    t,
  ) async {
    final s = await store();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          VeyaApi.channel,
          (_) async => throw PlatformException(
            code: 'model',
            message: 'Download failed',
          ),
        );
    await screen(
      t,
      s,
      home: ComposerScreen(store: s, initial: 'Please review my proposal'),
    );
    await t.scrollUntilVisible(
      find.text('Translate with Google'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Translate with Google'));
    await t.pumpAndSettle();
    expect(s.entries, isEmpty);
    expect(find.textContaining('Download failed'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    expect(s.draft, 'Please review my proposal');
    expect(t.takeException(), isNull);
  });

  testWidgets('Standard edition does not offer cross-app access', (t) async {
    final s = await store();
    s.onboarded = true;
    await screen(t, s);
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    expect(find.text('Floating assistant'), findsNothing);
    expect(find.text('Choose your apps'), findsNothing);
    expect(find.text('Speaking language'), findsOneWidget);
    expect(find.text('AI connection'), findsNothing);
    expect(find.text('Server translation'), findsOneWidget);
  });

  test('History disabled does not store new messages', () async {
    final s = await store();
    s.saveHistory = false;
    await s.addEntry(
      Entry(
        id: 'a',
        source: 'hello',
        text: 'Hello.',
        language: 'en-IN',
        tone: 'Natural',
        mode: 'polish',
        created: DateTime.now(),
      ),
    );
    expect(s.entries, isEmpty);
  });
}
