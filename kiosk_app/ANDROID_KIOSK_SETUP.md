# Android kiosk / lock-task setup

`lib/main.dart` already puts the app in immersive fullscreen
(`SystemUiMode.immersiveSticky`) and locks orientation. This document covers
the native Android side: preventing the tablet from leaving the app at all.

The `android/` platform folder doesn't exist yet in this repo (there's no
Flutter SDK available in the environment this project was generated in, so
`flutter create` was never run). Do this once, locally:

## 1. Generate the platform folders

From `kiosk_app/`:

```sh
flutter create --org com.yourorg --project-name kiosk_app .
```

Run against an *existing* package directory, this only adds the missing
`android/` (and `ios/`, etc.) folders — it will not overwrite `lib/` or
`pubspec.yaml`. Replace `com.yourorg` with your actual reverse-domain org;
it determines the package path in the steps below (e.g. `com.yourorg` →
`android/app/src/main/kotlin/com/yourorg/kiosk_app/`).

Then run `flutter pub get`.

## 2. Add permissions

In `android/app/src/main/AndroidManifest.xml`, inside the `<manifest>` tag
(as siblings of `<application>`):

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-feature android:name="android.hardware.camera" android:required="true" />
```

## 3. Add the device admin receiver

Create `android/app/src/main/kotlin/com/yourorg/kiosk_app/KioskDeviceAdminReceiver.kt`
(adjust the package path to match your org):

```kotlin
package com.yourorg.kiosk_app

import android.app.admin.DeviceAdminReceiver

class KioskDeviceAdminReceiver : DeviceAdminReceiver()
```

Create `android/app/src/main/res/xml/device_admin.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<device-admin xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-policies>
        <force-lock />
    </uses-policies>
</device-admin>
```

Register the receiver in `AndroidManifest.xml`, inside `<application>`:

```xml
<receiver
    android:name=".KioskDeviceAdminReceiver"
    android:permission="android.permission.BIND_DEVICE_ADMIN"
    android:exported="true">
    <meta-data
        android:name="android.app.device_admin"
        android:resource="@xml/device_admin" />
    <intent-filter>
        <action android:name="android.app.action.DEVICE_ADMIN_ENABLED" />
    </intent-filter>
</receiver>
```

## 4. Start lock task mode from MainActivity

Replace the generated `android/app/src/main/kotlin/com/yourorg/kiosk_app/MainActivity.kt`
with:

```kotlin
package com.yourorg.kiosk_app

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Kept in sync with KioskLockTaskService._channel on the Dart side.
    private val lockTaskChannel = "kiosk/lock_task"

    override fun onResume() {
        super.onResume()
        startKioskLockIfPossible()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, lockTaskChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "unpinAndExitToHome" -> {
                        unpinAndExitToHome()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startKioskLockIfPossible() {
        val dpm = getSystemService(DevicePolicyManager::class.java)
        val adminComponent = ComponentName(this, KioskDeviceAdminReceiver::class.java)

        if (dpm.isDeviceOwnerApp(packageName)) {
            // Device Owner: lock task mode with no exit UI, no system dialog.
            dpm.setLockTaskPackages(adminComponent, arrayOf(packageName))
        }

        try {
            startLockTask()
        } catch (e: IllegalStateException) {
            // Already locked, or lock task isn't permitted yet -- safe to ignore.
        }
    }

    // The deliberate escape hatch: releases lock task and hands off to the
    // launcher so the operator can reach Settings or any other app. Re-
    // opening this app triggers onResume -> startKioskLockIfPossible() again,
    // so it re-pins itself automatically -- there's no separate "pin" call.
    // Wired to the "Unpin kiosk" button on DeviceSettingsScreen (PIN-gated,
    // same as enrollment) via KioskLockTaskService.unpinAndExitToHome().
    private fun unpinAndExitToHome() {
        try {
            stopLockTask()
        } catch (e: IllegalStateException) {
            // Not currently locked -- fine to ignore.
        }

        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
    }
}
```


## 5. Provision the tablet as Device Owner

**This step is what suppresses Android's own "screen pinning" warning** —
without it, `startLockTask()` still works but shows the system "app is
pinned" dialog/banner and the user can back out via a long-press-back/
overview gesture. With Device Owner status, there is no dialog, and the
*only* way out is the in-app "Unpin kiosk" button on `DeviceSettingsScreen`
(PIN-gated, reached the same way as enrollment) — there is no system
gesture that works instead. That button calls `stopLockTask()` and hands
off to the launcher; reopening the kiosk app re-locks it automatically via
`onResume`.

Requirements (Device Owner can only be set on a device with **no accounts**
added — Google, email, etc.):

1. Factory reset the tablet (or use a device that's never had an account
   added).
2. Skip account setup during the Android setup wizard entirely.
3. Enable Developer Options + USB debugging.
4. Install the app via `flutter install` or `adb install path/to/app.apk`
   — but do **not** open it yet.
5. Set it as device owner:

   ```sh
   adb shell dpm set-device-owner com.yourorg.kiosk_app/.KioskDeviceAdminReceiver
   ```

6. Launch the app. It will now lock itself to the foreground on `onResume`.

For a fleet of kiosks, look into Android's zero-touch enrollment or QR-code
provisioning instead of doing this by hand over USB for every device.
