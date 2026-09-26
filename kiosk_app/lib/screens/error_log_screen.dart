import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/local_database.dart';

/// Reached from DeviceSettingsScreen -- the last ~50 entries from
/// LocalDatabase's error_logs table (written by services/error_logger.dart
/// from main.dart's global error handlers plus a handful of previously
/// bare-catch call sites), so field issues on an unattended kiosk are
/// diagnosable without a laptop attached via adb logcat.
class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({super.key});

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  List<Map<String, Object?>>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await LocalDatabase.instance.recentErrorLogs();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _clear() async {
    await LocalDatabase.instance.clearErrorLogs();
    await _load();
  }

  Future<void> _copyAll() async {
    final entries = _entries ?? const [];
    final text = entries
        .map((e) => '[${e['logged_at']}] ${e['context'] ?? ''} :: ${e['message']}')
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied to clipboard.')));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent errors'),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_outlined),
            onPressed: entries == null || entries.isEmpty ? null : _copyAll,
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: entries == null || entries.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const Center(child: Text('No errors logged.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${entry['logged_at']}${entry['context'] != null ? '  ·  ${entry['context']}' : ''}',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(entry['message'] as String? ?? ''),
                      ],
                    );
                  },
                ),
    );
  }
}
