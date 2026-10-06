import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/device_identity.dart';
import '../services/device_credentials_store.dart';
import '../services/kiosk_backend.dart';
import 'camera_screen.dart';

/// Shown instead of CameraScreen when this tablet has no paired identity
/// yet (DeviceCredentialsStore is empty and no --dart-define KIOSK_EMAIL/
/// PASSWORD fallback was built in -- see main.dart). The admin panel's
/// Devices page creates a device and shows a one-time "setup code"
/// (base64 of {email, password}) to paste here; "Enter manually" below is
/// the fallback for when copy/paste isn't available (e.g. reading off a
/// printed sheet).
class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  final _codeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _manualEntry = false;
  bool _pairing = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  ({String email, String password})? _decodeSetupCode(String code) {
    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(code.trim()))) as Map<String, dynamic>;
      final email = decoded['email'] as String?;
      final password = decoded['password'] as String?;
      if (email == null || password == null) return null;
      return (email: email, password: password);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pair() async {
    String email;
    String password;

    if (_manualEntry) {
      email = _emailController.text.trim();
      password = _passwordController.text;
      if (email.isEmpty || password.isEmpty) {
        setState(() => _error = 'Enter both the device email and password.');
        return;
      }
    } else {
      final decoded = _decodeSetupCode(_codeController.text);
      if (decoded == null) {
        setState(() => _error = 'That setup code doesn\'t look right. Check it and try again.');
        return;
      }
      email = decoded.email;
      password = decoded.password;
    }

    setState(() {
      _pairing = true;
      _error = null;
    });

    try {
      final identity = await KioskBackend.instance.verifyDeviceCredentials(
        email: email,
        password: password,
      );
      await DeviceCredentialsStore.instance.save(email: email, password: password);
      if (!mounted) return;
      await _showPairedConfirmation(identity);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CameraScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not pair: could not sign in with those credentials.');
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  Future<void> _showPairedConfirmation(DeviceIdentity identity) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Device paired'),
        content: Text(
          'Paired as "${identity.label}"'
          '${identity.classLabel != null ? ' -- Class ${identity.classLabel}' : ' -- all classes'}.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tablet_mac, color: Colors.white70, size: 40),
                  const SizedBox(height: 16),
                  const Text(
                    'Set up this kiosk',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the setup code shown on the admin panel\'s Devices page for this '
                    'tablet.',
                    style: TextStyle(color: Colors.white60, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (!_manualEntry)
                    _DarkField(
                      controller: _codeController,
                      label: 'Setup code',
                      maxLines: 3,
                    )
                  else ...[
                    _DarkField(controller: _emailController, label: 'Device email'),
                    const SizedBox(height: 12),
                    _DarkField(controller: _passwordController, label: 'Device password', obscure: true),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _pairing ? null : () => setState(() => _manualEntry = !_manualEntry),
                    child: Text(
                      _manualEntry ? 'Paste a setup code instead' : 'Enter email/password manually',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _pairing ? null : _pair,
                      child: _pairing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Pair this device'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    required this.label,
    this.obscure = false,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        enabledBorder: const OutlineInputBorder(),
        border: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
      ),
    );
  }
}
