package com.kioskattendance.kiosk_app

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
                    "isDeviceOwner" -> {
                        val dpm = getSystemService(DevicePolicyManager::class.java)
                        result.success(dpm.isDeviceOwnerApp(packageName))
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
