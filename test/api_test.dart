import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veya/core/api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<String> translate({
    String language = 'hi-IN',
    String mode = 'translate',
  }) => VeyaApi().transform(
    text: 'नमस्ते',
    language: language,
    tone: 'Offline',
    mode: mode,
  );
  test(
    'Translation only calls the local channel with text and language',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VeyaApi.channel, (call) async {
            expect(call.method, 'translate');
            expect(call.arguments, {'text': 'नमस्ते', 'language': 'hi-IN'});
            return 'Hello';
          });
      expect(await translate(), 'Hello');
    },
  );
  test(
    'Unsupported language never invokes native or cloud translation',
    () async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(VeyaApi.channel, (call) async {
            called = true;
            return 'incorrect';
          });
      await expectLater(
        translate(language: 'ml-IN'),
        throwsA(isA<VeyaException>()),
      );
      expect(called, false);
    },
  );
  test('Drafts cannot silently become fabricated offline writing', () async {
    await expectLater(translate(mode: 'draft'), throwsA(isA<VeyaException>()));
  });
  test('Model failure is actionable and has no cloud fallback', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VeyaApi.channel, (call) async {
          throw PlatformException(code: 'download', message: 'Download failed');
        });
    await expectLater(
      translate(),
      throwsA(predicate((e) => e.toString() == 'Download failed')),
    );
  });
  test('Empty native response is rejected', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(VeyaApi.channel, (call) async => '');
    await expectLater(translate(), throwsA(isA<VeyaException>()));
  });
}
