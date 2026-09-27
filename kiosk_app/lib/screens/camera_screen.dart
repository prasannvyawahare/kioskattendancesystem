import 'dart:async';

import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../services/attendance_mode_service.dart';
import '../services/attendance_service.dart';
import '../services/embedding_service.dart';
import '../services/enrollment_sync_service.dart';
import '../services/error_logger.dart';
import '../services/face_image_utils.dart';
import '../services/face_matcher.dart';
import '../services/greeting_service.dart';
import '../services/kiosk_settings_service.dart';
import '../services/sync_service.dart';
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
  final KioskSettingsService _settingsService = KioskSettingsService();

  // Constructed in _setup() -- AttendanceService depends on
  // AttendanceModeService's persisted value being loaded first, and
  // SyncService needs _matcher, so these can't be simple field initializers.
  late final AttendanceModeService _attendanceModeService;
  late final SyncService _syncService;
  late final AttendanceService _attendanceService;

  EmbeddingService? _embeddingService;
  EnrollmentSyncService? _enrollmentSync;
  GreetingService? _greetingService;
  Timer? _employeeRefreshTimer;
  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  DateTime? _lastConnectivitySync;
  bool _timersRunning = false;

  // Avoids re-triggering a sync on every flappy connectivity blip.
  static const _connectivitySyncCooldown = Duration(minutes: 2);

  _ScanState _state = _ScanState.initializing;
  bool _busy = false;
  int _consecutiveDetections = 0;
  bool _personPresent = false;
  Timer? _presenceLostTimer;
  String? _statusMessage;
  String? _modelLoadError;
  String _resultTitle = '';
  String _resultSubtitle = '';
  Color _resultColor = Colors.teal;
  MascotExpression _mascotExpression = MascotExpression.neutral;

  static const _stabilityFramesRequired = 4;
  static const _resultDisplayDuration = Duration(seconds: 3);
  // Grace period before we drop back to the idle clock screen after the
  // camera briefly stops seeing a face (blinking, head turn, ML Kit missing
  // a frame) -- avoids flicker between the clock and camera views.
  static const _presenceLostGrace = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    setState(() => _statusMessage = 'Loading recognition model...');

    // Settings load first (and start polling) so the timing knobs below
    // (refresh/sync intervals, online timeout, min scan gap -- all
    // admin-configurable, see KioskSettings) are populated from the real
    // fetched row, not just defaults, by the time anything reads them.
    await _settingsService.start();

    _attendanceModeService = AttendanceModeService();
    await _attendanceModeService.load();
    _syncService = SyncService(matcher: _matcher);
    await _syncService.loadInitialStatus();
    _attendanceService = AttendanceService(
      attendanceModeService: _attendanceModeService,
      settingsService: _settingsService,
    );

    try {
      final embeddingService = await EmbeddingService.load();
      _embeddingService = embeddingService;
      _greetingService = GreetingService(_settingsService);

      _enrollmentSync = EnrollmentSyncService(embeddingService: embeddingService)..start();

      await _refreshEmployees();
      _timersRunning = true;
      _scheduleEmployeeRefresh();
      _scheduleSync();
      _connectivitySub =
          Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    } catch (e) {
      // No .tflite model at assets/models/face_embedding.tflite yet (see
      // README) -- camera preview and face detection still work without
      // it, matching/attendance just won't. Surfaced as a banner instead of
      // crashing so the rest of the pipeline stays testable.
      _modelLoadError = 'Recognition model not loaded: $e';
    }

    setState(() => _statusMessage = 'Starting camera...');
    await _startCamera();
  }

  /// Self-rescheduling rather than Timer.periodic -- each tick reads
  /// _settingsService.current.refreshInterval fresh, so an admin's change
  /// to that admin-configurable value takes effect from the next tick
  /// onward instead of requiring an app restart.
  void _scheduleEmployeeRefresh() {
    if (!_timersRunning) return;
    _employeeRefreshTimer = Timer(_settingsService.current.refreshInterval, () async {
      await _refreshEmployees();
      _scheduleEmployeeRefresh();
    });
  }

  /// Same self-rescheduling pattern as above, driven by
  /// _settingsService.current.syncInterval.
  void _scheduleSync() {
    if (!_timersRunning) return;
    _syncTimer = Timer(_settingsService.current.syncInterval, () async {
      await _syncService.syncNow();
      _scheduleSync();
    });
  }

  /// Triggers an opportunistic sync as soon as the kiosk regains a
  /// connection, in addition to the manual button and the background timer
  /// -- cooldown-guarded so a flapping connection doesn't spam syncNow()
  /// (which is also internally guarded against overlapping runs, but no
  /// point attempting network calls back-to-back on an unstable link).
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (results.every((r) => r == ConnectivityResult.none)) return;
    final last = _lastConnectivitySync;
    if (last != null && DateTime.now().difference(last) < _connectivitySyncCooldown) return;
    _lastConnectivitySync = DateTime.now();
    _syncService.syncNow();
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
    if (controller == null) return;
    _controller = null;
    // Unmount CameraPreview *before* awaiting the async stop/dispose calls
    // below -- on some Android camera backends, disposing a controller while
    // its Texture widget is still in the tree flashes a stale/garbage frame
    // (seen as a red screen flash) during the teardown handshake.
    if (mounted) setState(() {});
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
    _presenceLostTimer?.cancel();
    _presenceLostTimer = null;
    _personPresent = false;

    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => PinEntryScreen(settingsService: _settingsService)),
    );

    if (pin != null && mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MemberListScreen(
            settingsService: _settingsService,
            pin: pin,
            embeddingService: embeddingService,
            attendanceModeService: _attendanceModeService,
            syncService: _syncService,
          ),
        ),
      );
    }

    if (!mounted) return;
    await _startCamera();
    await _refreshEmployees();
  }

  Future<void> _refreshEmployees() => _syncService.refreshEmployeesOnly();

  void _onFrame(CameraImage image) {
    if (_busy || _state != _ScanState.scanning || _camera == null) return;
    _busy = true;
    _processFrame(image).whenComplete(() => _busy = false);
  }

  /// Drives the idle clock screen vs. live camera view: goes true the
  /// instant any face appears, and only goes false after _presenceLostGrace
  /// of seeing nobody, so momentary detection gaps don't flicker the UI.
  void _setPersonPresent(bool seen) {
    if (seen) {
      _presenceLostTimer?.cancel();
      _presenceLostTimer = null;
      if (!_personPresent && mounted) setState(() => _personPresent = true);
      return;
    }

    if (_personPresent && _presenceLostTimer == null) {
      _presenceLostTimer = Timer(_presenceLostGrace, () {
        _presenceLostTimer = null;
        if (mounted) setState(() => _personPresent = false);
      });
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    final inputImage = FaceImageUtils.toInputImage(image, _camera!);
    if (inputImage == null) return;

    final faces = await _liveDetector.processImage(inputImage);
    _setPersonPresent(faces.isNotEmpty);

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
            subtitle: 'Timed in at ${_formatNow()}',
            color: Colors.teal,
            expression: MascotExpression.happy,
          );
          break;
        case 'check_out':
          _greetingService?.speakCheckOut(match.employee.fullName);
          _showResult(
            title: 'Goodbye, ${match.employee.fullName}',
            subtitle: 'Timed out at ${_formatNow()}',
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
    } catch (e, st) {
      ErrorLogger.log(e, stackTrace: st, context: 'CameraScreen._processFrame');
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
    // Stops _scheduleEmployeeRefresh/_scheduleSync from rescheduling
    // themselves if a tick is in flight right as this disposes.
    _timersRunning = false;
    _employeeRefreshTimer?.cancel();
    _syncTimer?.cancel();
    _connectivitySub?.cancel();
    _presenceLostTimer?.cancel();
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
    // The camera keeps streaming frames (and ML Kit keeps scanning them)
    // even while this is showing -- it's a pure UI overlay, not a pause.
    final showIdleClock = _state == _ScanState.scanning && !_personPresent;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            CameraPreview(controller),
          if (showIdleClock) const Positioned.fill(child: _IdleClockScreen()),
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
          if (!showIdleClock)
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

/// Idle screen shown whenever nobody is standing in front of the camera --
/// a plain white clock face rather than the live camera preview, so the
/// kiosk doesn't sit there broadcasting an empty hallway. CameraScreen swaps
/// this out for the live view the instant a face is detected (see
/// _setPersonPresent). Keeps its own ticking timer so the clock updates
/// without rebuilding the rest of CameraScreen every second.
class _IdleClockScreen extends StatefulWidget {
  const _IdleClockScreen();

  @override
  State<_IdleClockScreen> createState() => _IdleClockScreenState();
}

class _IdleClockScreenState extends State<_IdleClockScreen> {
  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _timeText {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    final second = _now.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String get _dateText {
    final weekday = _weekdayNames[_now.weekday - 1];
    final month = _monthNames[_now.month - 1];
    return '$weekday, ${_now.day} $month ${_now.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _timeText,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 88,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _dateText,
            style: const TextStyle(color: Colors.black54, fontSize: 22),
          ),
          const SizedBox(height: 40),
          const Text(
            'Stand in front of the camera to mark attendance',
            style: TextStyle(color: Colors.black45, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
