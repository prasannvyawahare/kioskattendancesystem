import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../services/attendance_service.dart';
import '../services/embedding_service.dart';
import '../services/enrollment_sync_service.dart';
import '../services/face_image_utils.dart';
import '../services/face_matcher.dart';
import '../services/supabase_service.dart';

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

  EmbeddingService? _embeddingService;
  EnrollmentSyncService? _enrollmentSync;
  Timer? _employeeRefreshTimer;

  _ScanState _state = _ScanState.initializing;
  bool _busy = false;
  int _consecutiveDetections = 0;
  String? _statusMessage;
  String _resultTitle = '';
  String _resultSubtitle = '';
  Color _resultColor = Colors.teal;

  static const _stabilityFramesRequired = 4;
  static const _resultDisplayDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    setState(() => _statusMessage = 'Loading recognition model...');
    final embeddingService = await EmbeddingService.load();
    _embeddingService = embeddingService;

    _enrollmentSync = EnrollmentSyncService(embeddingService: embeddingService)..start();

    await _refreshEmployees();
    _employeeRefreshTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _refreshEmployees());

    setState(() => _statusMessage = 'Starting camera...');
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _statusMessage = 'No camera found on this device.');
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
          _showResult(
            title: 'Welcome, ${match.employee.fullName}',
            subtitle: 'Checked in at ${_formatNow()}',
            color: Colors.teal,
          );
          break;
        case 'check_out':
          _showResult(
            title: 'Goodbye, ${match.employee.fullName}',
            subtitle: 'Checked out at ${_formatNow()}',
            color: Colors.blueGrey,
          );
          break;
        default:
          _showResult(
            title: match.employee.fullName,
            subtitle: 'Attendance already completed for today',
            color: Colors.grey,
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

  void _showResult({required String title, required String subtitle, required Color color}) {
    if (!mounted) return;
    setState(() {
      _state = _ScanState.result;
      _resultTitle = title;
      _resultSubtitle = subtitle;
      _resultColor = color;
    });

    Future<void>.delayed(_resultDisplayDuration, () {
      if (!mounted) return;
      setState(() => _state = _ScanState.scanning);
    });
  }

  @override
  void dispose() {
    _employeeRefreshTimer?.cancel();
    _controller?.dispose();
    _liveDetector.close();
    _enrollmentSync?.dispose();
    _embeddingService?.dispose();
    super.dispose();
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
            _ResultOverlay(
              title: _resultTitle,
              subtitle: _resultSubtitle,
              color: _resultColor,
            ),
        ],
      ),
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: color, size: 96),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
