import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/selfie_image_quality_analyzer.dart';
import '../../domain/liveness_result.dart';

export '../../domain/liveness_result.dart';

enum _Challenge { face, lookRight, lookLeft, blink, capture }

class LivenessCaptureScreen extends StatefulWidget {
  const LivenessCaptureScreen({
    super.key,
    this.qualityAnalyzer,
  });

  final SelfieImageQualityAnalyzer? qualityAnalyzer;

  @override
  State<LivenessCaptureScreen> createState() => _LivenessCaptureScreenState();
}

class _LivenessCaptureScreenState extends State<LivenessCaptureScreen> {
  CameraController? _controller;
  FaceDetector? _detector;
  late final SelfieImageQualityAnalyzer _qualityAnalyzer;
  bool _busy = false;
  bool _ready = false;
  bool _checking = false;
  bool _faceVisible = false;
  String? _error;
  String? _retakeHint;
  _Challenge _step = _Challenge.face;
  bool _eyesWereOpen = false;
  final Map<String, bool> _done = {
    'face': false,
    'lookRight': false,
    'lookLeft': false,
    'blink': false,
  };

  bool get _livenessComplete =>
      _done['face'] == true &&
      _done['lookRight'] == true &&
      _done['lookLeft'] == true &&
      _done['blink'] == true;

  @override
  void initState() {
    super.initState();
    _qualityAnalyzer = widget.qualityAnalyzer ?? SelfieImageQualityAnalyzer();
    _start();
  }

  Future<void> _start() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      setState(() {
        _error = 'Face verification needs a real Android or iPhone camera.';
      });
      return;
    }
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
      _controller = controller;
      await controller.startImageStream(_onFrame);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not open the camera. $e');
      }
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _checking || _detector == null || !_ready) return;
    _busy = true;
    try {
      final input = _toInputImage(image, _controller!.description);
      if (input == null) return;
      final faces = await _detector!.processImage(input);
      if (!mounted) return;
      if (faces.isEmpty) {
        if (_faceVisible) setState(() => _faceVisible = false);
        return;
      }
      if (!_faceVisible) {
        setState(() => _faceVisible = true);
      }
      _evaluate(faces.first);
    } catch (_) {
      // Frame conversion can fail on some devices; keep streaming.
    } finally {
      _busy = false;
    }
  }

  void _evaluate(Face face) {
    final yaw = face.headEulerAngleY ?? 0;
    final leftEye = face.leftEyeOpenProbability ?? 1;
    final rightEye = face.rightEyeOpenProbability ?? 1;
    final eyesOpen = (leftEye + rightEye) / 2 > 0.55;
    final eyesClosed = (leftEye + rightEye) / 2 < 0.25;

    setState(() {
      if (_step == _Challenge.face && yaw.abs() < 15) {
        _done['face'] = true;
        _step = _Challenge.lookRight;
      } else if (_step == _Challenge.lookRight && yaw < -16) {
        _done['lookRight'] = true;
        _step = _Challenge.lookLeft;
      } else if (_step == _Challenge.lookLeft && yaw > 16) {
        _done['lookLeft'] = true;
        _eyesWereOpen = eyesOpen;
        _step = _Challenge.blink;
      } else if (_step == _Challenge.blink) {
        if (eyesOpen) _eyesWereOpen = true;
        if (_eyesWereOpen && eyesClosed) {
          _done['blink'] = true;
          _step = _Challenge.capture;
        }
      }
    });
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _checking ||
        !_livenessComplete) {
      return;
    }

    setState(() {
      _checking = true;
      _retakeHint = null;
    });

    String? capturePath;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final file = await controller.takePicture();
      capturePath = file.path;
      final bytes = await file.readAsBytes();
      if (!mounted) {
        await _deleteQuietly(capturePath);
        return;
      }

      final quality = await _qualityAnalyzer.analyze(
        bytes,
        filePath: capturePath,
      );
      await _deleteQuietly(capturePath);
      capturePath = null;

      if (!mounted) return;

      if (!quality.passed) {
        setState(() {
          _checking = false;
          _retakeHint = quality.message;
        });
        showThriftSnackBar(context, quality.message, isError: true);
        await _restartStream();
        return;
      }

      Navigator.pop(
        context,
        LivenessResult(
          imageBytes: bytes,
          fileName: 'liveness.jpg',
          challenges: Map<String, bool>.from(_done),
          imageQualityPassed: true,
        ),
      );
    } catch (_) {
      await _deleteQuietly(capturePath);
      if (!mounted) return;
      setState(() => _checking = false);
      showThriftSnackBar(context, 'Could not capture the photo.', isError: true);
      await _restartStream();
    }
  }

  Future<void> _restartStream() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !mounted ||
        controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.startImageStream(_onFrame);
    } catch (_) {}
  }

  Future<void> _deleteQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    try {
      final bytes = image.planes.length == 1
          ? image.planes.first.bytes
          : _concatPlanes(image.planes);
      final rotation = InputImageRotationValue.fromRawValue(
            camera.sensorOrientation,
          ) ??
          InputImageRotation.rotation270deg;
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Uint8List _concatPlanes(List<Plane> planes) {
    final write = WriteBuffer();
    for (final plane in planes) {
      write.putUint8List(plane.bytes);
    }
    return write.done().buffer.asUint8List();
  }

  String get _prompt => switch (_step) {
        _Challenge.face => 'Center your face in the circle',
        _Challenge.lookRight => 'Slowly look to your right',
        _Challenge.lookLeft => 'Slowly look to your left',
        _Challenge.blink => 'Blink both eyes',
        _Challenge.capture => _faceVisible
            ? 'Hold still, then capture'
            : 'Keep your face in the circle, then capture',
      };

  @override
  void dispose() {
    _controller?.dispose();
    _detector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face verification')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(_prompt, style: AppTypography.subheading, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Expanded(
                child: ClipOval(
                  child: ColoredBox(
                    color: Colors.black,
                    child: _ready && _controller != null
                        ? CameraPreview(_controller!)
                        : Center(
                            child: Text(
                              _error ?? 'Starting camera…',
                              style: AppTypography.body.copyWith(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  _chip('Face', _done['face'] == true),
                  _chip('Look right', _done['lookRight'] == true),
                  _chip('Look left', _done['lookLeft'] == true),
                  _chip('Blink', _done['blink'] == true),
                ],
              ),
              if (_retakeHint != null) ...[
                const SizedBox(height: 12),
                Text(
                  _retakeHint!,
                  style: AppTypography.body.copyWith(color: AppColors.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              ThriftButton(
                label: _checking ? 'Checking selfie…' : 'Capture face photo',
                isLoading: _checking,
                onPressed: _step == _Challenge.capture && !_checking
                    ? _capture
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool done) {
    return Chip(
      label: Text(label),
      backgroundColor: done
          ? AppColors.success.withValues(alpha: 0.15)
          : AppColors.surfaceVariant,
      avatar: Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 18,
        color: done ? AppColors.success : AppColors.textHint,
      ),
    );
  }
}
