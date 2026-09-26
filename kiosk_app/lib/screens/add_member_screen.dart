import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../services/embedding_service.dart';
import '../services/face_image_utils.dart';
import '../services/kiosk_backend.dart';

class _Capture {
  _Capture({required this.jpegBytes, required this.embedding});
  final Uint8List jpegBytes;
  final List<double> embedding;
}

/// Guided on-device enrollment: a form plus a live camera feed that
/// auto-captures a face crop (+ its embedding, via the same EmbeddingService
/// CameraScreen uses) whenever it's centered and stable, the same
/// stability-frame-counting shape as CameraScreen._processFrame. On submit,
/// walks the same enroll_member -> upload photo -> record_member_photo ->
/// record_face_embedding sequence EnrollmentSyncService performs for
/// admin-captured photos, just synchronously and with locally-computed
/// embeddings instead of a background poll.
class AddMemberScreen extends StatefulWidget {
  const AddMemberScreen({
    super.key,
    required this.pin,
    required this.memberLabel,
    required this.embeddingService,
  });

  final String pin;
  final String memberLabel;
  final EmbeddingService embeddingService;

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> {
  static const _minPhotos = 3;
  static const _maxPhotos = 5;
  static const _stabilityFramesRequired = 4;
  static const _captureCooldown = Duration(seconds: 2);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _groupController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _motherNameController = TextEditingController();
  final _motherPhoneController = TextEditingController();
  final _motherEmailController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _fatherPhoneController = TextEditingController();
  final _fatherEmailController = TextEditingController();

  CameraController? _controller;
  CameraDescription? _camera;
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast, minFaceSize: 0.2),
  );

  final List<_Capture> _captures = [];
  int _consecutiveDetections = 0;
  bool _busy = false;
  bool _cameraReady = false;
  bool _submitting = false;
  DateTime? _cooldownUntil;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _error = 'No camera found on this device.');
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
    setState(() => _cameraReady = true);
  }

  void _onFrame(CameraImage image) {
    if (_busy || _submitting || _camera == null) return;
    if (_captures.length >= _maxPhotos) return;
    final cooldown = _cooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) return;

    _busy = true;
    _processFrame(image).whenComplete(() => _busy = false);
  }

  Future<void> _processFrame(CameraImage image) async {
    final inputImage = FaceImageUtils.toInputImage(image, _camera!);
    if (inputImage == null) return;

    final faces = await _detector.processImage(inputImage);
    if (faces.length != 1) {
      _consecutiveDetections = 0;
      return;
    }

    _consecutiveDetections++;
    if (_consecutiveDetections < _stabilityFramesRequired) return;
    _consecutiveDetections = 0;

    try {
      final rgb = FaceImageUtils.toUprightRgbImage(image, _camera!);
      final cropped = FaceImageUtils.cropToFace(rgb, faces.first.boundingBox);
      final embedding = widget.embeddingService.embed(cropped);
      final jpegBytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 90));

      if (!mounted) return;
      setState(() {
        _captures.add(_Capture(jpegBytes: jpegBytes, embedding: embedding));
        _cooldownUntil = DateTime.now().add(_captureCooldown);
      });
    } catch (_) {
      // Transient decode/embed failure -- just skip this frame and let the
      // stability counter build back up on the next one.
    }
  }

  void _removeCapture(int index) {
    setState(() => _captures.removeAt(index));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_captures.length < _minPhotos) {
      setState(() => _error = 'Capture at least $_minPhotos photos from different angles.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final employeeId = await KioskBackend.instance.enrollMember(
        pin: widget.pin,
        fullName: _nameController.text.trim(),
        code: _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
        group: _groupController.text.trim().isEmpty ? null : _groupController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        motherName:
            _motherNameController.text.trim().isEmpty ? null : _motherNameController.text.trim(),
        motherPhone: _motherPhoneController.text.trim().isEmpty
            ? null
            : _motherPhoneController.text.trim(),
        motherEmail: _motherEmailController.text.trim().isEmpty
            ? null
            : _motherEmailController.text.trim(),
        fatherName:
            _fatherNameController.text.trim().isEmpty ? null : _fatherNameController.text.trim(),
        fatherPhone: _fatherPhoneController.text.trim().isEmpty
            ? null
            : _fatherPhoneController.text.trim(),
        fatherEmail: _fatherEmailController.text.trim().isEmpty
            ? null
            : _fatherEmailController.text.trim(),
      );

      for (final capture in _captures) {
        final storagePath =
            await KioskBackend.instance.uploadMemberPhoto(employeeId, capture.jpegBytes);
        final photoId = await KioskBackend.instance.recordMemberPhoto(
          employeeId: employeeId,
          storagePath: storagePath,
        );
        await KioskBackend.instance.recordFaceEmbedding(
          employeeId: employeeId,
          photoId: photoId,
          embedding: capture.embedding,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_nameController.text.trim()} added.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not save ${widget.memberLabel.toLowerCase()}: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detector.close();
    _nameController.dispose();
    _codeController.dispose();
    _groupController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _motherNameController.dispose();
    _motherPhoneController.dispose();
    _motherEmailController.dispose();
    _fatherNameController.dispose();
    _fatherPhoneController.dispose();
    _fatherEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: Text('Add ${widget.memberLabel}')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: '${widget.memberLabel} name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(labelText: 'ID / code (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _groupController,
                  decoration: const InputDecoration(labelText: 'Group / department (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 20),
                Text('Parent / guardian details', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Used to contact a parent about attendance. Optional, but at least one '
                  'phone number is recommended.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text('Mother', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _motherNameController,
                  decoration: const InputDecoration(labelText: 'Name (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _motherPhoneController,
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _motherEmailController,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                Text('Father', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _fatherNameController,
                  decoration: const InputDecoration(labelText: 'Name (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fatherPhoneController,
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fatherEmailController,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),
                Text(
                  'Photos (${_captures.length}/$_maxPhotos)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Container(
                      color: Colors.black,
                      child: controller != null && controller.value.isInitialized
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                CameraPreview(controller),
                                if (_captures.length < _maxPhotos)
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      width: double.infinity,
                                      color: Colors.black54,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: const Text(
                                        'Hold still and face the camera',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_captures.isNotEmpty)
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _captures.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _captures[index].jpegBytes,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: IconButton(
                              icon: const Icon(Icons.cancel, size: 20),
                              onPressed: () => _removeCapture(index),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_captures.length < _minPhotos)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Capture at least $_minPhotos photos from different angles.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submitting || !_cameraReady ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('Save ${widget.memberLabel.toLowerCase()}'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
