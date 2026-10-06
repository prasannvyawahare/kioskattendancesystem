import 'package:flutter/material.dart';

import '../models/attendance_mode.dart';
import '../models/device_identity.dart';
import '../services/attendance_mode_service.dart';
import '../services/device_credentials_store.dart';
import '../services/kiosk_backend.dart';
import '../services/kiosk_lock_task_service.dart';
import '../services/sync_service.dart';
import 'device_setup_screen.dart';
import 'error_log_screen.dart';

const _modeLabels = {
  AttendanceMode.both: 'Both (Time In then Time Out)',
  AttendanceMode.checkInOnly: 'Time In only',
  AttendanceMode.checkOutOnly: 'Time Out only',
};

const _modeDescriptions = {
  AttendanceMode.both: 'First scan of the day times in, the next times out.',
  AttendanceMode.checkInOnly: 'Every scan only ever records a Time In.',
  AttendanceMode.checkOutOnly: 'Every scan only ever records a Time Out.',
};

/// Reached from MemberListScreen's app bar (same PIN-gated flow as
/// enrollment). Lets this kiosk's operator restrict scans to check-in-only
/// or check-out-only (AttendanceModeService, device-local -- not synced to
/// admin_panel) and trigger a manual sync of anything queued while offline
/// (SyncService).
class DeviceSettingsScreen extends StatefulWidget {
  const DeviceSettingsScreen({
    super.key,
    required this.attendanceModeService,
    required this.syncService,
  });

  final AttendanceModeService attendanceModeService;
  final SyncService syncService;

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  DeviceIdentity? _deviceIdentity;

  @override
  void initState() {
    super.initState();
    KioskBackend.instance.fetchDeviceIdentity().then((identity) {
      if (mounted) setState(() => _deviceIdentity = identity);
    }).catchError((_) {});
  }

  Future<void> _sync(BuildContext context) async {
    final result = await widget.syncService.syncNow(manual: true);
    if (!context.mounted) return;

    final message = switch (result.outcome) {
      SyncOutcome.ok => 'Synced successfully.',
      SyncOutcome.alreadyInProgress => 'A sync is already in progress.',
      SyncOutcome.failed => 'Sync failed -- will retry automatically. (${result.error})',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Clears this device's paired identity and returns to
  /// DeviceSetupScreen, as the new navigation root -- used when a tablet
  /// is being handed off to a different class (or otherwise needs a fresh
  /// setup code from the admin panel's Devices page).
  Future<void> _rePair(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-pair this device?'),
        content: const Text(
          'Signs this tablet out of its current device identity. You\'ll need a new '
          'setup code from the admin panel\'s Devices page to use it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Re-pair'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await DeviceCredentialsStore.instance.clear();
    try {
      await KioskBackend.instance.signOut();
    } catch (_) {
      // Best-effort -- credentials are already cleared locally, which is
      // what actually matters for falling back to DeviceSetupScreen.
    }
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DeviceSetupScreen()),
      (route) => false,
    );
  }

  Future<void> _unpin(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unpin kiosk?'),
        content: const Text(
          'This releases lock task mode and exits to the home screen, so '
          'anyone with the device can reach other apps or system settings. '
          'Reopening this app re-locks it automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unpin'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await KioskLockTaskService.unpinAndExitToHome();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not unpin: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kiosk settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Device identity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            _deviceIdentity == null
                ? 'Loading...'
                : _deviceIdentity!.classLabel != null
                    ? '${_deviceIdentity!.label} -- assigned to Class ${_deviceIdentity!.classLabel}'
                    : '${_deviceIdentity!.label} -- sees all classes',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _rePair(context),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Re-pair this device'),
          ),
          const Divider(height: 40),
          const Text('Attendance mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'Controls what a recognized scan records on this kiosk. Device-only -- '
            'other kiosks are unaffected.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<AttendanceMode>(
            valueListenable: widget.attendanceModeService.mode,
            builder: (context, mode, _) {
              return RadioGroup<AttendanceMode>(
                groupValue: mode,
                onChanged: (value) {
                  if (value != null) widget.attendanceModeService.setMode(value);
                },
                child: Column(
                  children: AttendanceMode.values.map((option) {
                    return RadioListTile<AttendanceMode>(
                      value: option,
                      title: Text(_modeLabels[option]!),
                      subtitle: Text(_modeDescriptions[option]!),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const Divider(height: 40),
          const Text('Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ValueListenableBuilder<SyncStatus>(
            valueListenable: widget.syncService.status,
            builder: (context, status, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.lastSyncedAt == null
                        ? 'Never synced yet.'
                        : 'Last synced: ${status.lastSyncedAt}',
                  ),
                  const SizedBox(height: 4),
                  Text('Pending (not yet synced): ${status.pendingCount}'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: status.isSyncing ? null : () => _sync(context),
                    icon: status.isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(status.isSyncing ? 'Syncing...' : 'Sync now'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'The kiosk also syncs automatically every few hours, and as soon as it '
            'regains a connection.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const Divider(height: 40),
          const Text('Diagnostics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            'Recent app errors, kept on-device for troubleshooting without a laptop attached.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ErrorLogScreen()),
            ),
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('View error log'),
          ),
          const Divider(height: 40),
          const Text('Exit kiosk mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'The kiosk auto-pins itself every time it opens. Use this to step out to '
            'the home screen -- for example to reach Android settings -- without '
            'disabling that.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FutureBuilder<bool>(
            future: KioskLockTaskService.isDeviceOwner(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final isDeviceOwner = snapshot.data!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isDeviceOwner ? Icons.verified_user_outlined : Icons.warning_amber_outlined,
                      size: 18,
                      color: isDeviceOwner ? Colors.tealAccent : Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isDeviceOwner
                            ? 'Fully locked (Device Owner): no system "unpin" banner or '
                                  'Back/Overview gesture -- only this button exits.'
                            : 'Not yet set up as Device Owner: Android will still show its '
                                  'own "app is pinned" banner and let Back+Overview unpin it. '
                                  'See ANDROID_KIOSK_SETUP.md step 5 to close that off.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          OutlinedButton.icon(
            onPressed: () => _unpin(context),
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Unpin kiosk'),
          ),
        ],
      ),
    );
  }
}
