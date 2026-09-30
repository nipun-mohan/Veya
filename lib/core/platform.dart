import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidBridge {
  static const channel = MethodChannel('app.veya/assistant');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  // The Play-distributed standard flavor includes the same native assistant
  // implementation as the local assistant flavor.
  static bool get assistantAvailable =>
      supported && (appFlavor == 'assistant' || appFlavor == 'standard');
  static Future<T?> call<T>(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (!assistantAvailable) return null;
    return channel.invokeMethod<T>(method, arguments);
  }
}
