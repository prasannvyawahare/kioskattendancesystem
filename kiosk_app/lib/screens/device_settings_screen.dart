import 'package:flutter/material.dart';

import '../models/attendance_mode.dart';
import '../services/attendance_mode_service.dart';
import '../services/sync_service.dart';
import 'error_log_screen.dart';

const _modeLabels = {
  AttendanceMode.both: 'Both (check-in then check-out)',
  AttendanceMode.checkInOnly: 'Check-in only',
  AttendanceMode.checkOutOnly: 'Check-out only',
};

const _modeDescriptions = {
  AttendanceMode.both: 'First scan of the day checks in, the next checks out.',
  AttendanceMode.checkInOnly: 'Every scan only ever records a check-in.',
  AttendanceMode.checkOutOnly: 'Every scan only ever records a check-out.',
};

/// Reached from MemberListScreen's app bar (same PIN-gated flow as
/// enrollment). Lets this kiosk's operator restrict scans to check-in-only
/// or check-out-only (AttendanceModeService, device-local -- not synced to
/// admin_panel) and trigger a manual sync of anything queued while offline
/// (SyncService).
class DeviceSettingsScreen extends StatelessWidget {
  const DeviceSettingsScreen({
    super.key,
    required this.attendanceModeService,
    required this.syncService,
  });

  final AttendanceModeService attendanceModeService;
  final SyncService syncService;

  Future<void> _sync(BuildContext context) async {
    final result = await syncService.syncNow(manual: true);
    if (!context.mounted) return;

    final message = switch (result.outcome) {
      SyncOutcome.ok => 'Synced successfully.',
      SyncOutcome.alreadyInProgress => 'A sync is already in progress.',
      SyncOutcome.failed => 'Sync failed -- will retry automatically. (${result.error})',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kiosk settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Attendance mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'Controls what a recognized scan records on this kiosk. Device-only -- '
            'other kiosks are unaffected.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<AttendanceMode>(
            valueListenable: attendanceModeService.mode,
            builder: (context, mode, _) {
              return RadioGroup<AttendanceMode>(
                groupValue: mode,
                onChanged: (value) {
                  if (value != null) attendanceModeService.setMode(value);
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
            valueListenable: syncService.status,
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
        ],
      ),
    );
  }
}
