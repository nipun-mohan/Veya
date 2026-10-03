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

  static Future<bool> launchUpiIntent(
    String intentUrl,
    String packageName,
  ) async {
    if (!assistantAvailable) return false;
    return await call<bool>('launchUpiIntent', {
          'intentUrl': intentUrl,
          'packageName': packageName,
        }) ??
        false;
  }

  static Future<List<Map<String, String>>> installedUpiApps() async {
    if (!assistantAvailable) return const [];
    final raw = await call<List<dynamic>>('installedUpiApps');
    return (raw ?? const [])
        .whereType<Map>()
        .map(
          (app) => app.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        )
        .toList();
  }
}

/// Requests microphone access on platforms that can record inside Veya.
/// Android uses the assistant bridge; iOS uses its own small native channel.
class MicrophonePermissions {
  static const _iosChannel = MethodChannel('app.veya/permissions');

  static bool get available =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<bool> isGranted() async {
    if (!available) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await AndroidBridge.call<bool>('isMicrophoneGranted') ?? false;
    }
    return await _iosChannel.invokeMethod<bool>('isMicrophoneGranted') ?? false;
  }

  static Future<bool> request() async {
    if (!available) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await AndroidBridge.call<bool>('requestMicrophone') ?? false;
    }
    return await _iosChannel.invokeMethod<bool>('requestMicrophone') ?? false;
  }
}
