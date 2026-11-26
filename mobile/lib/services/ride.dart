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

  /// One short vibration, no sound, no notification.
  static Future<void> vibrate() => _ch.invokeMethod('vibrate');

  /// Opens the dialer with the number filled in. The user still presses call.
  static Future<void> dial(String number) =>
      _ch.invokeMethod('dial', {'number': number});

  /// Writes the bytes encrypted (AES-GCM, Android Keystore key that never leaves the phone).
  static Future<void> seal(String path, Uint8List bytes) =>
      _ch.invokeMethod('seal', {'path': path, 'bytes': bytes});
  static Future<Uint8List> open(String path) async =>
      (await _ch.invokeMethod<Uint8List>('open', {'path': path}))!;
}
