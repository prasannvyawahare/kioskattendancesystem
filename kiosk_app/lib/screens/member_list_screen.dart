import 'package:flutter/material.dart';

import '../models/member_summary.dart';
import '../services/attendance_mode_service.dart';
import '../services/embedding_service.dart';
import '../services/kiosk_backend.dart';
import '../services/kiosk_settings_service.dart';
import '../services/local_database.dart';
import '../services/sync_service.dart';
import 'add_member_screen.dart';
import 'device_settings_screen.dart';

const _statusColors = {
  'pending': Colors.amber,
  'processing': Colors.blueAccent,
  'completed': Colors.teal,
  'failed': Colors.redAccent,
};

/// Reached via the hidden PIN gesture on CameraScreen. Lists every active
/// member with their recognition status; "Add {member_label}" (top-right,
/// hidden unless enrollment is currently allowed) pushes AddMemberScreen.
/// Popping this screen returns to CameraScreen, which resumes scanning.
class MemberListScreen extends StatefulWidget {
  const MemberListScreen({
    super.key,
    required this.settingsService,
    required this.pin,
    required this.embeddingService,
    required this.attendanceModeService,
    required this.syncService,
  });

  final KioskSettingsService settingsService;

  /// The PIN verified on the way in here -- carried forward so
  /// AddMemberScreen can pass it to enroll_member() without re-prompting.
  final String pin;

  /// The same loaded model CameraScreen uses for live recognition --
  /// reused rather than loading a second ~93MB interpreter instance.
  final EmbeddingService embeddingService;

  /// Passed through to DeviceSettingsScreen (reached via the app bar
  /// settings icon below) -- same instances CameraScreen drives.
  final AttendanceModeService attendanceModeService;
  final SyncService syncService;

  @override
  State<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<MemberListScreen> {
  List<MemberSummary>? _members;
  String? _error;

  /// Non-blocking, unlike [_error] -- set alongside a successfully-loaded
  /// (cached) [_members] list, so _buildBody still renders it instead of
  /// swallowing the list behind an error screen.
  String? _offlineNotice;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final members = await KioskBackend.instance.fetchAllMembers();
      if (!mounted) return;
      setState(() {
        _members = members;
        _error = null;
        _offlineNotice = null;
      });
      await LocalDatabase.instance.replaceCachedMembers(members);
    } catch (_) {
      // Offline (or a transient failure) -- fall back to whatever
      // SyncService's periodic poll (or an earlier successful visit to
      // this screen) last cached, same pattern as the face-matching
      // roster's offline fallback.
      final cached = await LocalDatabase.instance.loadCachedMembers();
      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _members = cached;
          _error = null;
          _offlineNotice = 'Offline -- showing the last synced list. Pull down to retry.';
        });
      } else {
        setState(() {
          _error = 'Could not load members. Pull down to retry.';
          _offlineNotice = null;
        });
      }
    }
  }

  Future<void> _openAddMember() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AddMemberScreen(
          pin: widget.pin,
          memberLabel: widget.settingsService.current.memberLabel,
          embeddingService: widget.embeddingService,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _editMember(MemberSummary member) async {
    final nameController = TextEditingController(text: member.fullName);
    final codeController = TextEditingController(text: member.code ?? '');
    final groupController = TextEditingController(text: member.group ?? '');
    final emailController = TextEditingController(text: member.email ?? '');
    final phoneController = TextEditingController(text: member.phone ?? '');
    final motherNameController = TextEditingController(text: member.motherName ?? '');
    final motherPhoneController = TextEditingController(text: member.motherPhone ?? '');
    final motherEmailController = TextEditingController(text: member.motherEmail ?? '');
    final fatherNameController = TextEditingController(text: member.fatherName ?? '');
    final fatherPhoneController = TextEditingController(text: member.fatherPhone ?? '');
    final fatherEmailController = TextEditingController(text: member.fatherEmail ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${widget.settingsService.current.memberLabel.toLowerCase()}'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: codeController,
                    decoration: const InputDecoration(labelText: 'ID / code (optional)'),
                  ),
                  TextFormField(
                    controller: groupController,
                    decoration: const InputDecoration(labelText: 'Group / department (optional)'),
                  ),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email (optional)'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(labelText: 'Phone (optional)'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Mother', style: Theme.of(dialogContext).textTheme.labelLarge),
                  ),
                  TextFormField(
                    controller: motherNameController,
                    decoration: const InputDecoration(labelText: 'Name (optional)'),
                  ),
                  TextFormField(
                    controller: motherPhoneController,
                    decoration: const InputDecoration(labelText: 'Phone (optional)'),
                    keyboardType: TextInputType.phone,
                  ),
                  TextFormField(
                    controller: motherEmailController,
                    decoration: const InputDecoration(labelText: 'Email (optional)'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Father', style: Theme.of(dialogContext).textTheme.labelLarge),
                  ),
                  TextFormField(
                    controller: fatherNameController,
                    decoration: const InputDecoration(labelText: 'Name (optional)'),
                  ),
                  TextFormField(
                    controller: fatherPhoneController,
                    decoration: const InputDecoration(labelText: 'Phone (optional)'),
                    keyboardType: TextInputType.phone,
                  ),
                  TextFormField(
                    controller: fatherEmailController,
                    decoration: const InputDecoration(labelText: 'Email (optional)'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    try {
      await KioskBackend.instance.updateMember(
        pin: widget.pin,
        employeeId: member.id,
        fullName: nameController.text.trim(),
        code: codeController.text.trim().isEmpty ? null : codeController.text.trim(),
        group: groupController.text.trim().isEmpty ? null : groupController.text.trim(),
        email: emailController.text.trim().isEmpty ? null : emailController.text.trim(),
        phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
        motherName:
            motherNameController.text.trim().isEmpty ? null : motherNameController.text.trim(),
        motherPhone:
            motherPhoneController.text.trim().isEmpty ? null : motherPhoneController.text.trim(),
        motherEmail:
            motherEmailController.text.trim().isEmpty ? null : motherEmailController.text.trim(),
        fatherName:
            fatherNameController.text.trim().isEmpty ? null : fatherNameController.text.trim(),
        fatherPhone:
            fatherPhoneController.text.trim().isEmpty ? null : fatherPhoneController.text.trim(),
        fatherEmail:
            fatherEmailController.text.trim().isEmpty ? null : fatherEmailController.text.trim(),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save changes: $e')));
    }
  }

  Future<void> _deleteMember(MemberSummary member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${member.fullName}?'),
        content: const Text('This removes them and their enrollment photos. This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await KioskBackend.instance.deleteMember(pin: widget.pin, employeeId: member.id);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsService.current;
    final label = settings.memberLabel;

    return Scaffold(
      appBar: AppBar(
        title: Text('${label}s'),
        actions: [
          IconButton(
            tooltip: 'Kiosk settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => DeviceSettingsScreen(
                  attendanceModeService: widget.attendanceModeService,
                  syncService: widget.syncService,
                ),
              ),
            ),
          ),
          if (widget.settingsService.enrollmentAllowed)
            TextButton.icon(
              onPressed: _openAddMember,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text('Add $label'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(label),
      ),
    );
  }

  Widget _buildBody(String label) {
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(child: Text(_error!)),
        ],
      );
    }

    final members = _members;
    if (members == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (members.isEmpty) {
      return ListView(
        children: [
          if (_offlineNotice != null) _OfflineNoticeBanner(_offlineNotice!),
          const SizedBox(height: 80),
          Center(child: Text('No ${label.toLowerCase()}s enrolled yet.')),
        ],
      );
    }

    return ListView.separated(
      itemCount: members.length + (_offlineNotice != null ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, rawIndex) {
        if (_offlineNotice != null) {
          if (rawIndex == 0) return _OfflineNoticeBanner(_offlineNotice!);
        }
        final index = _offlineNotice != null ? rawIndex - 1 : rawIndex;
        final member = members[index];
        final color = _statusColors[member.embeddingStatus] ?? Colors.grey;
        return ListTile(
          title: Text(member.fullName),
          subtitle: Text([
            if (member.code != null && member.code!.isNotEmpty) member.code!,
            if (member.group != null && member.group!.isNotEmpty) member.group!,
          ].join(' · ')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Chip(
                label: Text(member.embeddingStatus),
                backgroundColor: color.withValues(alpha: 0.15),
                labelStyle: TextStyle(color: color),
                side: BorderSide(color: color.withValues(alpha: 0.4)),
              ),
              if (widget.settingsService.enrollmentAllowed) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit',
                  onPressed: () => _editMember(member),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () => _deleteMember(member),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _OfflineNoticeBanner extends StatelessWidget {
  const _OfflineNoticeBanner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}
