import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../services/attendance_service.dart';
import '../services/embedding_service.dart';
import '../services/enrollment_sync_service.dart';
import '../services/face_image_utils.dart';
import '../services/face_matcher.dart';
import '../services/greeting_service.dart';
import '../services/kiosk_settings_service.dart';
import '../services/supabase_service.dart';
import '../widgets/mascot_avatar.dart';
import 'member_list_screen.dart';
import 'pin_entry_screen.dart';

enum _ScanState { initializing, scanning, processing, result }

/// The kiosk's only real screen: a live camera preview that continuously
/// looks for a stable, well-framed face, matches it against the synced-down
/// embeddings, and calls the attendance RPC on a match.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  CameraDescription? _camera;

  final FaceDetector _liveDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.2,
    ),
  );
  final FaceMatcher _matcher = FaceMatcher();
  final AttendanceService _attendanceService = AttendanceService();
  final KioskSettingsService _settingsService = KioskSettingsService();

  EmbeddingService? _embeddingService;
  EnrollmentSyncService? _enrollmentSync;
  GreetingService? _greetingService;
  Timer? _employeeRefreshTimer;

  _ScanState _state = _ScanState.initializing;
  bool _busy = false;
  int _consecutiveDetections = 0;
  String? _statusMessage;
  String? _modelLoadError;
  String _resultTitle = '';
  String _resultSubtitle = '';
  Color _resultColor = Colors.teal;
  MascotExpression _mascotExpression = MascotExpression.neutral;

  static const _stabilityFramesRequired = 4;
  static const _resultDisplayDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    setState(() => _statusMessage = 'Loading recognition model...');
    try {
      final embeddingService = await EmbeddingService.load();
      _embeddingService = embeddingService;
      _greetingService = GreetingService(_settingsService);

      _enrollmentSync = EnrollmentSyncService(embeddingService: embeddingService)..start();

      await _refreshEmployees();
      _employeeRefreshTimer =
          Timer.periodic(const Duration(seconds: 60), (_) => _refreshEmployees());
    } catch (e) {
      // No .tflite model at assets/models/face_embedding.tflite yet (see
      // README) -- camera preview and face detection still work without
      // it, matching/attendance just won't. Surfaced as a banner instead of
      // crashing so the rest of the pipeline stays testable.
      _modelLoadError = 'Recognition model not loaded: $e';
    }

    await _settingsService.start();

    setState(() => _statusMessage = 'Starting camera...');
    await _startCamera();
  }

  Future<void> _startCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (mounted) setState(() => _statusMessage = 'No camera found on this device.');
      return;
    }

    _camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      _camera!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = controller;
    await controller.initialize();
    await controller.startImageStream(_onFrame);

    if (!mounted) return;
    setState(() {
      _state = _ScanState.scanning;
      _statusMessage = null;
    });
  }

  /// Releases the camera hardware so AddMemberScreen's own CameraController
  /// can claim it -- Android only allows one controller on a camera at a
  /// time. Paired with _startCamera() when enrollment screens are popped.
  Future<void> _stopCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Already stopped/disposed -- fine to ignore.
    }
    await controller.dispose();
  }

  /// Hidden enrollment entry point (long-press gesture in build()). Gated
  /// on both the embedding model being loaded and
  /// KioskSettingsService.enrollmentAllowed (hardware build flag AND the
  /// admin's kiosk_settings.enrollment_enabled toggle).
  Future<void> _openEnrollment() async {
    final embeddingService = _embeddingService;
    if (embeddingService == null || !_settingsService.enrollmentAllowed) return;

    await _stopCamera();
    if (!mounted) return;
    setState(() {
      _state = _ScanState.initializing;
      _statusMessage = null;
    });

    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PinEntryScreen()),
    );

    if (pin != null && mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MemberListScreen(
            settingsService: _settingsService,
            pin: pin,
            embeddingService: embeddingService,
          ),
        ),
      );
    }

    if (!mounted) return;
    await _startCamera();
    await _refreshEmployees();
  }

  Future<void> _refreshEmployees() async {
    try {
      final employees = await SupabaseService.instance.fetchEnrolledEmployees();
      _matcher.updateEmployees(employees);
    } catch (_) {
      // Keep using whatever was last cached; retried on the next tick.
    }
  }

  void _onFrame(CameraImage image) {
    if (_busy || _state != _ScanState.scanning || _camera == null) return;
    _busy = true;
    _processFrame(image).whenComplete(() => _busy = false);
  }

  Future<void> _processFrame(CameraImage image) async {
    final inputImage = FaceImageUtils.toInputImage(image, _camera!);
    if (inputImage == null) return;

    final faces = await _liveDetector.processImage(inputImage);

    if (faces.length != 1) {
      _consecutiveDetections = 0;
      return;
    }

    _consecutiveDetections++;
    if (_consecutiveDetections < _stabilityFramesRequired) return;
    _consecutiveDetections = 0;

    final embeddingService = _embeddingService;
    if (embeddingService == null) return;

    final face = faces.first;

    if (!mounted) return;
    setState(() => _state = _ScanState.processing);

    try {
      final rgb = FaceImageUtils.toUprightRgbImage(image, _camera!);
      final cropped = FaceImageUtils.cropToFace(rgb, face.boundingBox);
      final embedding = embeddingService.embed(cropped);
      final match = _matcher.match(embedding);

      if (match == null) {
        _showResult(
          title: 'Not recognized',
          subtitle: "Ask an admin to register you if you're a new employee.",
          color: Colors.orange,
          expression: MascotExpression.confused,
        );
        return;
      }

      final result = await _attendanceService.handleMatch(match.employee, match.similarity);
      if (result == null) {
        // Within cooldown of a previous scan for this person -- ignore.
        if (mounted) setState(() => _state = _ScanState.scanning);
        return;
      }

      switch (result.status) {
        case 'check_in':
          _greetingService?.speakCheckIn(match.employee.fullName);
          _showResult(
            title: 'Welcome, ${match.employee.fullName}',
            subtitle: 'Checked in at ${_formatNow()}',
            color: Colors.teal,
            expression: MascotExpression.happy,
          );
          break;
        case 'check_out':
          _greetingService?.speakCheckOut(match.employee.fullName);
          _showResult(
            title: 'Goodbye, ${match.employee.fullName}',
            subtitle: 'Checked out at ${_formatNow()}',
            color: Colors.blueGrey,
            expression: MascotExpression.happy,
          );
          break;
        default:
          _showResult(
            title: match.employee.fullName,
            subtitle: 'Attendance already completed for today',
            color: Colors.grey,
            expression: MascotExpression.neutral,
          );
      }
    } catch (_) {
      if (mounted) setState(() => _state = _ScanState.scanning);
    }
  }

  String _formatNow() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _showResult({
    required String title,
    required String subtitle,
    required Color color,
    required MascotExpression expression,
  }) {
    if (!mounted) return;
    setState(() {
      _state = _ScanState.result;
      _resultTitle = title;
      _resultSubtitle = subtitle;
      _resultColor = color;
      _mascotExpression = expression;
    });

    Future<void>.delayed(_resultDisplayDuration, () {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.scanning;
        _mascotExpression = MascotExpression.neutral;
      });
    });
  }

  @override
  void dispose() {
    _employeeRefreshTimer?.cancel();
    _controller?.dispose();
    _liveDetector.close();
    _enrollmentSync?.dispose();
    _embeddingService?.dispose();
    _settingsService.dispose();
    _greetingService?.dispose();
    super.dispose();
  }

  /// The school-boy mascot in the top-right corner: its expression tracks
  /// the last scan result (see _mascotExpression, set alongside _showResult)
  /// and it "talks" -- mouth animation plus a MascotSpeechBubble caption --
  /// in sync with whatever GreetingService is currently speaking.
  Widget _buildMascot() {
    final greetingService = _greetingService;
    if (greetingService == null) {
      return MascotAvatar(expression: _mascotExpression, isTalking: false);
    }
    return ValueListenableBuilder<String?>(
      valueListenable: greetingService.caption,
      builder: (context, caption, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (caption != null) MascotSpeechBubble(text: caption),
            MascotAvatar(expression: _mascotExpression, isTalking: caption != null),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            CameraPreview(controller),
          // Hidden enrollment entry point: long-press the top-left corner.
          // No visible affordance on purpose -- this is an unattended
          // public kiosk; the PIN pad is the real gate.
          Positioned(
            top: 0,
            left: 0,
            width: 72,
            height: 72,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: _openEnrollment,
            ),
          ),
          Positioned(
            top: 24,
            right: 16,
            child: SafeArea(child: _buildMascot()),
          ),
          if (_statusMessage != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          if (_state == _ScanState.processing)
            const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 32),
                child: LinearProgressIndicator(minHeight: 4),
              ),
            ),
          if (_state == _ScanState.result)
            Align(
              alignment: Alignment.bottomCenter,
              child: _ResultPanel(
                title: _resultTitle,
                subtitle: _resultSubtitle,
                color: _resultColor,
              ),
            ),
          if (_modelLoadError != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: Colors.red.shade900,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  _modelLoadError!,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet-style result panel -- the camera preview stays visible
/// above it (unlike the old full-screen overlay), matching the look of a
/// typical turnstile/Face-ID check-in kiosk.
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.32;

    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: color, width: 4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: color, size: 56),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
