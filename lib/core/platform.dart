import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidBridge {
  static const channel = MethodChannel('app.veya/assistant');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get assistantAvailable => supported && appFlavor == 'assistant';
  static Future<T?> call<T>(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!assistantAvailable) return null;
    return channel.invokeMethod<T>(method, arguments);
  }
}
