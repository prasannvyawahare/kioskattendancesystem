import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'kiosk_settings_service.dart';

/// Speaks the admin-managed check-in/check-out greeting templates
/// (kiosk_settings.checkin_greeting_template / checkout_greeting_template)
/// using the device's on-board TTS engine. Template placeholders:
/// {name}, {time_greeting} (computed locally from the clock), {institution}.
class GreetingService {
  GreetingService(this._settingsService) {
    _tts.setSpeechRate(0.45);
    _tts.setStartHandler(() => caption.value = _pendingText);
    _tts.setCompletionHandler(() => caption.value = null);
    _tts.setCancelHandler(() => caption.value = null);
    _tts.setErrorHandler((_) => caption.value = null);
  }

  final KioskSettingsService _settingsService;
  final FlutterTts _tts = FlutterTts();
  String? _pendingText;

  /// Non-null exactly while the device is speaking -- CameraScreen's mascot
  /// shows this as a speech-bubble caption near its mouth (MascotSpeechBubble)
  /// and animates talking while it's set.
  final ValueNotifier<String?> caption = ValueNotifier<String?>(null);

  Future<void> speakCheckIn(String name) => _speak(
        _settingsService.current.checkinGreetingTemplate,
        name,
      );

  Future<void> speakCheckOut(String name) => _speak(
        _settingsService.current.checkoutGreetingTemplate,
        name,
      );

  Future<void> _speak(String template, String name) async {
    final settings = _settingsService.current;
    if (!settings.voiceEnabled) return;

    final text = template
        .replaceAll('{name}', name)
        .replaceAll('{time_greeting}', _timeGreeting())
        .replaceAll('{institution}', settings.institutionName);

    _pendingText = text;
    await _tts.stop();
    await _tts.speak(text);
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void dispose() {
    _tts.stop();
    caption.dispose();
  }
}
