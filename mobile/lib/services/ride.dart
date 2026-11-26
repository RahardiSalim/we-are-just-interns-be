import 'package:flutter/services.dart';

/// The Android side of a ride (android/app/src/main/kotlin/.../MainActivity.kt). Android only:
/// callers skip it on the web preview.
abstract final class Ride {
  static const _ch = MethodChannel('gosafe/ride');

  /// Starts the foreground service that keeps the microphone on with the screen locked.
  static Future<void> startListening(String title, String body) =>
      _ch.invokeMethod('startListening', {'title': title, 'body': body});
  static Future<void> stopListening() => _ch.invokeMethod('stopListening');

  /// "Are you okay?" on the lock screen. `loud`: alarm sound, repeating until answered.
  static Future<void> alert(String title, String body, {required bool loud}) =>
      _ch.invokeMethod('alert', {'title': title, 'body': body, 'loud': loud});
  static Future<void> clearAlert() => _ch.invokeMethod('clearAlert');

  /// AES-GCM with an Android Keystore key. Returns the encrypted file's path; the plain file is deleted.
  static Future<String> encrypt(String path) async =>
      (await _ch.invokeMethod<String>('encrypt', {'path': path}))!;
  static Future<Uint8List> decrypt(String path) async =>
      (await _ch.invokeMethod<Uint8List>('decrypt', {'path': path}))!;
}
