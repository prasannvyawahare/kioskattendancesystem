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
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
        startKioskLockIfPossible()
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
}
```

## 5. Provision the tablet as Device Owner

**This step is what makes lock task mode actually unbreakable** — without
it, `startLockTask()` still works but shows Android's "screen pinning"
system dialog and the user can back out via a long-press-back/overview
gesture. With Device Owner status, there is no dialog and no way to leave
the app short of a factory reset.

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
