import 'package:flutter/services.dart';

/// Bridges to MainActivity's Android lock-task (screen pinning) control.
/// The app re-pins itself automatically on every `Activity.onResume` (see
/// `MainActivity.startKioskLockIfPossible`), so this only exposes the
/// deliberate escape hatch -- there's no corresponding "pin" call to make
/// from Dart.
class KioskLockTaskService {
  static const _channel = MethodChannel('kiosk/lock_task');

  /// Releases lock task and hands off to the device's launcher. Reopening
  /// the kiosk app re-pins it automatically.
  static Future<void> unpinAndExitToHome() async {
    await _channel.invokeMethod<void>('unpinAndExitToHome');
  }

  /// True only once the tablet has been provisioned via
  /// `adb shell dpm set-device-owner ...` (see ANDROID_KIOSK_SETUP.md step
  /// 5). Until then, `startLockTask()` still works but as plain Android
  /// screen pinning -- which always shows the system "app is pinned, touch
  /// & hold Back and Overview to unpin" banner and lets that gesture
  /// unpin it. Neither can be suppressed from app code; Device Owner status
  /// is the only thing that removes them.
  static Future<bool> isDeviceOwner() async {
    final result = await _channel.invokeMethod<bool>('isDeviceOwner');
    return result ?? false;
  }
}
