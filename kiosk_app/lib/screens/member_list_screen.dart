import 'package:flutter/material.dart';

import '../models/member_summary.dart';
import '../services/embedding_service.dart';
import '../services/kiosk_settings_service.dart';
import '../services/supabase_service.dart';
import 'add_member_screen.dart';

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
  });

  final KioskSettingsService settingsService;

  /// The PIN verified on the way in here -- carried forward so
  /// AddMemberScreen can pass it to enroll_member() without re-prompting.
  final String pin;

  /// The same loaded model CameraScreen uses for live recognition --
  /// reused rather than loading a second ~93MB interpreter instance.
  final EmbeddingService embeddingService;

  @override
  State<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<MemberListScreen> {
  List<MemberSummary>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final members = await SupabaseService.instance.fetchAllMembers();
      if (!mounted) return;
      setState(() {
        _members = members;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load members. Pull down to retry.');
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
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${widget.settingsService.current.memberLabel.toLowerCase()}'),
        content: Form(
          key: formKey,
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
            ],
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
      await SupabaseService.instance.updateMember(
        pin: widget.pin,
        employeeId: member.id,
        fullName: nameController.text.trim(),
        code: codeController.text.trim().isEmpty ? null : codeController.text.trim(),
        group: groupController.text.trim().isEmpty ? null : groupController.text.trim(),
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
      await SupabaseService.instance.deleteMember(pin: widget.pin, employeeId: member.id);
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
          const SizedBox(height: 80),
          Center(child: Text('No ${label.toLowerCase()}s enrolled yet.')),
        ],
      );
    }

    return ListView.separated(
      itemCount: members.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
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
