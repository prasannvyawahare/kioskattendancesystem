package com.kioskattendance.kiosk_app

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
