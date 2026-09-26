import 'package:flutter/material.dart';

import '../services/kiosk_settings_service.dart';
import '../services/pin_verification_service.dart';

/// Numeric PIN pad guarding the hidden enrollment entry point on
/// CameraScreen. Pops the verified PIN (as a String) once
/// verify_enrollment_pin() (the RPC in 0007_kiosk_enrollment.sql) accepts
/// it, or null on cancel. The PIN is carried forward (not re-prompted) so
/// MemberListScreen/AddMemberScreen can pass it to enroll_member(), which
/// re-verifies it server-side as the real authorization gate -- this
/// screen's check is only for fast UI feedback and lockout messaging.
///
/// Works offline too, via PinVerificationService's local bcrypt fallback --
/// note that reaching this screen doesn't mean everything behind it works
/// offline: MemberListScreen's add/edit/delete actions still need a live
/// connection (those RPCs genuinely write server-side records), only
/// DeviceSettingsScreen (attendance mode + sync) is fully usable offline.
class PinEntryScreen extends StatefulWidget {
  const PinEntryScreen({super.key, required this.settingsService});

  final KioskSettingsService settingsService;

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  late final _pinVerification = PinVerificationService(settingsService: widget.settingsService);

  String _pin = '';
  bool _checking = false;
  String? _error;

  static const _maxLength = 8;

  void _onDigit(String digit) {
    if (_checking || _pin.length >= _maxLength) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _onBackspace() {
    if (_checking || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _onSubmit() async {
    if (_pin.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    final enteredPin = _pin;
    try {
      final ok = await _pinVerification.verify(enteredPin);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(enteredPin);
        return;
      }
      setState(() {
        _error = 'Incorrect PIN. Try again.';
        _pin = '';
      });
    } on PinVerificationUnavailable {
      if (!mounted) return;
      setState(() {
        _error = 'No PIN cached yet -- connect to WiFi once, then this works offline too.';
        _pin = '';
      });
    } on PinVerificationLocked catch (e) {
      if (!mounted) return;
      final minutesLeft = e.lockedUntil.difference(DateTime.now()).inMinutes + 1;
      setState(() {
        _error = 'Too many attempts. Try again in $minutesLeft minute${minutesLeft == 1 ? '' : 's'}.';
        _pin = '';
      });
    } catch (e) {
      // Log the real error since it's otherwise invisible on a kiosk with
      // no attached console.
      debugPrint('verifyEnrollmentPin failed: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not verify PIN. Check the connection and try again.';
        _pin = '';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Spacer(),
            const Icon(Icons.lock_outline, color: Colors.white70, size: 40),
            const SizedBox(height: 16),
            const Text(
              'Enter enrollment PIN',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            _PinDots(length: _pin.length, maxLength: _maxLength),
            const SizedBox(height: 16),
            SizedBox(
              height: 20,
              child: _checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                    )
                  : Text(
                      _error ?? '',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                    ),
            ),
            const Spacer(),
            _Keypad(onDigit: _onDigit, onBackspace: _onBackspace, onSubmit: _onSubmit),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.length, required this.maxLength});

  final int length;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final shown = length.clamp(0, 6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(6, (i) {
        final filled = i < shown;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? Colors.tealAccent : Colors.white24,
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace, required this.onSubmit});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final digit in row) _KeypadButton(label: digit, onTap: () => onDigit(digit))],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _KeypadButton(icon: Icons.backspace_outlined, onTap: onBackspace),
            _KeypadButton(label: '0', onTap: () => onDigit('0')),
            _KeypadButton(icon: Icons.check_circle, onTap: onSubmit, color: Colors.tealAccent),
          ],
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({this.label, this.icon, required this.onTap, this.color});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.white10,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Center(
              child: label != null
                  ? Text(
                      label!,
                      style: TextStyle(color: color ?? Colors.white, fontSize: 26),
                    )
                  : Icon(icon, color: color ?? Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
