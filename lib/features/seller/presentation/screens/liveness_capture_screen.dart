import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/id_camera_input_image.dart';
import '../../data/id_preview_luma.dart';
import '../../data/selfie_face_reader.dart';
import '../../data/selfie_image_quality_analyzer.dart';
import '../../domain/id_image_quality.dart';
import '../../domain/liveness_challenge.dart';
import '../../domain/liveness_result.dart';
import '../../domain/selfie_image_quality.dart';
import '../widgets/selfie_capture_overlay.dart';

export '../../domain/liveness_result.dart';

class LivenessCaptureScreen extends StatefulWidget {
  const LivenessCaptureScreen({
    super.key,
    this.qualityAnalyzer,
    this.autoCaptureHold = SelfieCaptureGuide.autoCaptureHold,
  });

  final SelfieImageQualityAnalyzer? qualityAnalyzer;
  final Duration autoCaptureHold;

  @override
  State<LivenessCaptureScreen> createState() => _LivenessCaptureScreenState();
}

class _LivenessCaptureScreenState extends State<LivenessCaptureScreen> {
  CameraController? _controller;
  FaceDetector? _detector;
  late final SelfieImageQualityAnalyzer _qualityAnalyzer;
  late final LiveCaptureStability _stability;
  late final LivenessChallengeSession _challenge;
  bool _busy = false;
  bool _ready = false;
  bool _checking = false;
  bool _capturing = false;
  bool _permissionDenied = false;
  bool _holdingPose = false;
  String? _error;
  String? _retakeHint;
  LivenessChallengeStep _shownStep = LivenessChallengeStep.face;
  LiveSelfieStatus _liveStatus = LiveSelfieStatus.noFace;
  DateTime? _lastAnalyzed;
  final Map<String, bool> _shownDone = {
    'face': false,
    'lookRight': false,
    'lookLeft': false,
    'blink': false,
  };

  bool get _livenessComplete => _challenge.isComplete;

  @override
  void initState() {
    super.initState();
    _qualityAnalyzer = widget.qualityAnalyzer ?? SelfieImageQualityAnalyzer();
    _challenge = LivenessChallengeSession();
    _stability = LiveCaptureStability(
      hold: widget.autoCaptureHold,
      motionDelta: SelfieCaptureGuide.motionCoverageDelta,
    );
    _start();
  }

  Future<void> _start() async {
    _stability.reset();
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      setState(() {
        _error = 'Face verification needs a real Android or iPhone camera.';
      });
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera is available on this device.');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
      _controller = controller;
      await controller.startImageStream(_onFrame);
      if (mounted) {
        setState(() {
          _ready = true;
          _error = null;
          _permissionDenied = false;
        });
      }
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied =
          e.code.toLowerCase().contains('access') ||
          e.code.toLowerCase().contains('denied') ||
          e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'CameraAccessRestricted';
      setState(() {
        _permissionDenied = denied;
        _error = denied
            ? 'Camera permission is required for face verification. Enable it in Settings, then try again.'
            : 'The camera is unavailable right now. Please try again.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'The camera is unavailable right now. Please try again.';
        });
      }
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy ||
        _checking ||
        _capturing ||
        _detector == null ||
        !_ready ||
        _controller == null) {
      return;
    }
    final now = DateTime.now();
    final last = _lastAnalyzed;
    if (last != null &&
        now.difference(last) < SelfieCaptureGuide.liveAnalyzeInterval) {
      return;
    }
    _lastAnalyzed = now;
    _busy = true;
    try {
      // Copy luma and ML Kit bytes before the first await. CameraImage
      // planes are recycled when this stream callback yields, so sampling
      // after processImage would score a stale (often still-capped) frame
      // while the preview already shows the current face.
      final sampled = IdPreviewLuma.sample(image);
      final input = IdCameraInputImage.fromCamera(
        image,
        _controller!.description,
      );
      if (input == null) return;
      final detected = await _detector!.processImage(input);
      if (!mounted || _capturing || _checking) return;

      final faces = [
        for (final face in detected)
          selfieFaceFromMlKit(
            face,
            imageWidth: image.width.toDouble(),
            imageHeight: image.height.toDouble(),
          ),
      ];

      if (!_challenge.isComplete) {
        _evaluateChallenge(
          detected,
          faces: faces,
          imageWidth: image.width,
          imageHeight: image.height,
          sampled: sampled,
          now: now,
        );
        return;
      }

      double? faceMean;
      double? blur;
      final people = SelfieImageMetrics.selectPeople(faces);
      if (people.length == 1 && sampled != null) {
        final stats = SelfieImageMetrics.faceRegionStats(
          sampled.luma,
          sampled.width,
          sampled.height,
          people.first,
        );
        faceMean = stats.mean;
        blur = stats.blur;
      }

      final assessment = SelfieImageMetrics.assessLive(
        faces: faces,
        faceMean: faceMean,
        blur: blur,
        luma: sampled?.luma,
        lumaWidth: sampled?.width,
        lumaHeight: sampled?.height,
      );
      _setLiveStatus(assessment.status);

      final shouldCapture = _stability.observe(
        LiveIdAssessment(
          status: assessment.isAligned
              ? LiveIdStatus.aligned
              : LiveIdStatus.searching,
          occupancy: assessment.coverage,
        ),
        now,
      );
      if (shouldCapture) {
        await _capture();
      }
    } catch (_) {
      // Frame conversion can fail on some devices; keep streaming.
    } finally {
      _busy = false;
    }
  }

  void _evaluateChallenge(
    List<Face> mlKitFaces, {
    required List<SelfieDetectedFace> faces,
    required int imageWidth,
    required int imageHeight,
    ({List<int> luma, int width, int height})? sampled,
    required DateTime now,
  }) {
    final people = SelfieImageMetrics.selectPeople(faces);
    var yaw = 0.0;
    var eyesOpen = true;
    var eyesClosed = false;
    if (people.length == 1) {
      final mlKit = _primaryMlKitFace(
        mlKitFaces,
        primary: people.first,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      yaw = mlKit?.headEulerAngleY ?? people.first.yaw ?? 0;
      final leftEye = mlKit?.leftEyeOpenProbability ?? 1;
      final rightEye = mlKit?.rightEyeOpenProbability ?? 1;
      eyesOpen = (leftEye + rightEye) / 2 > 0.55;
      eyesClosed = (leftEye + rightEye) / 2 < 0.25;
    }

    final result = _challenge.observe(
      faces: faces,
      yaw: yaw,
      eyesOpen: eyesOpen,
      eyesClosed: eyesClosed,
      luma: sampled?.luma,
      lumaWidth: sampled?.width,
      lumaHeight: sampled?.height,
      now: now,
    );
    _applyChallenge(result);
  }

  void _applyChallenge(LivenessChallengeResult result) {
    final doneChanged =
        result.done['face'] != _shownDone['face'] ||
        result.done['lookRight'] != _shownDone['lookRight'] ||
        result.done['lookLeft'] != _shownDone['lookLeft'] ||
        result.done['blink'] != _shownDone['blink'];
    if (result.status == _liveStatus &&
        result.holdingPose == _holdingPose &&
        result.step == _shownStep &&
        !doneChanged) {
      return;
    }
    setState(() {
      _liveStatus = result.status;
      _holdingPose = result.holdingPose;
      _shownStep = result.step;
      _shownDone
        ..clear()
        ..addAll(result.done);
    });
    if (result.livenessComplete) {
      _stability.reset();
    }
  }

  Face? _primaryMlKitFace(
    List<Face> faces, {
    required SelfieDetectedFace primary,
    required int imageWidth,
    required int imageHeight,
  }) {
    Face? match;
    var bestIou = -1.0;
    for (final face in faces) {
      final mapped = selfieFaceFromMlKit(
        face,
        imageWidth: imageWidth.toDouble(),
        imageHeight: imageHeight.toDouble(),
      );
      final iou = mapped.iou(primary);
      if (iou > bestIou) {
        bestIou = iou;
        match = face;
      }
    }
    return match;
  }

  void _setLiveStatus(LiveSelfieStatus status) {
    if (_liveStatus == status) return;
    setState(() => _liveStatus = status);
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _checking ||
        _capturing ||
        !_livenessComplete) {
      return;
    }

    _capturing = true;
    _stability.reset();
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
        _capturing = false;
        _stability.reset();
        setState(() {
          _checking = false;
          _retakeHint = quality.message;
          _liveStatus = LiveSelfieStatus.noFace;
        });
        showThriftSnackBar(context, quality.message, isError: true);
        _lastAnalyzed = null;
        await _restartStream();
        return;
      }

      Navigator.pop(
        context,
        LivenessResult(
          imageBytes: bytes,
          fileName: 'liveness.jpg',
          challenges: Map<String, bool>.from(_challenge.done),
          imageQualityPassed: true,
        ),
      );
    } catch (_) {
      await _deleteQuietly(capturePath);
      if (!mounted) return;
      _capturing = false;
      _stability.reset();
      setState(() => _checking = false);
      showThriftSnackBar(
        context,
        'Could not capture the photo.',
        isError: true,
      );
      _lastAnalyzed = null;
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

  String get _prompt {
    if (_checking) return 'Checking selfie…';
    if (_isCoveringStatus(_liveStatus) ||
        _liveStatus == LiveSelfieStatus.noFace ||
        _liveStatus == LiveSelfieStatus.multipleFaces ||
        _liveStatus == LiveSelfieStatus.tooFar) {
      return LiveSelfieAssessment(status: _liveStatus).feedbackMessage;
    }
    if (!_livenessComplete) {
      return switch (_shownStep) {
        LivenessChallengeStep.face => 'Look directly at the camera',
        LivenessChallengeStep.lookRight => 'Slowly look to your right',
        LivenessChallengeStep.lookLeft => 'Slowly look to your left',
        LivenessChallengeStep.blink => 'Blink both eyes',
        LivenessChallengeStep.capture => 'Position your face within the frame',
      };
    }
    return LiveSelfieAssessment(status: _liveStatus).feedbackMessage;
  }

  String? get _overlaySubtitle {
    if (_checking ||
        _isCoveringStatus(_liveStatus) ||
        _liveStatus == LiveSelfieStatus.noFace ||
        _liveStatus == LiveSelfieStatus.multipleFaces ||
        _liveStatus == LiveSelfieStatus.tooFar) {
      return null;
    }
    if (!_livenessComplete) {
      if (_holdingPose &&
          (_shownStep == LivenessChallengeStep.lookRight ||
              _shownStep == LivenessChallengeStep.lookLeft)) {
        return 'Hold that pose';
      }
      return 'Keep your face uncovered through every step';
    }
    if (_liveStatus == LiveSelfieStatus.aligned) {
      return 'Photo will be taken automatically';
    }
    return _retakeHint;
  }

  bool _isCoveringStatus(LiveSelfieStatus status) {
    return status == LiveSelfieStatus.occluded ||
        status == LiveSelfieStatus.headCovering ||
        status == LiveSelfieStatus.eyeCovering;
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    _detector?.close();
    _detector = null;
    if (controller != null) {
      if (controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        controller.stopImageStream().whenComplete(controller.dispose);
      } else {
        controller.dispose();
      }
    }
    super.dispose();
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How to verify your face'),
        content: const Text(
          'Look at the camera, then look right, look left, and blink when asked. '
          'Hold each head turn for a couple of seconds.\n\n'
          'Remove caps, hats, glasses, and masks before you start, and keep them '
          'off until the photo is taken. If you put one on during a step, '
          'verification pauses until you remove it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null ? _buildError() : _buildCamera(),
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _permissionDenied
                  ? Icons.lock_outline
                  : Icons.videocam_off_outlined,
              color: Colors.white,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: AppTypography.body.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ThriftButton(
              label: _permissionDenied ? 'Try again' : 'Retry',
              onPressed: _start,
            ),
            const SizedBox(height: 12),
            ThriftButton(
              label: 'Cancel',
              variant: ThriftButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCamera() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: _ready && _controller != null
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.previewSize?.height ?? 100,
                    height: _controller!.value.previewSize?.width ?? 100,
                    child: CameraPreview(_controller!),
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        ),
        SelfieCaptureOverlay(
          message: _prompt,
          aligned: _livenessComplete && _liveStatus == LiveSelfieStatus.aligned,
          capturing: _capturing || _checking,
          subtitle: _overlaySubtitle,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        'Take a selfie',
                        textAlign: TextAlign.center,
                        style: AppTypography.subheading.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Help',
                      onPressed: _showHelp,
                      icon: const Icon(Icons.help_outline, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    _chip('Face', _shownDone['face'] == true),
                    _chip('Right', _shownDone['lookRight'] == true),
                    _chip('Left', _shownDone['lookLeft'] == true),
                    _chip('Blink', _shownDone['blink'] == true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, bool done) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: done ? AppColors.success : Colors.white,
        ),
      ),
      backgroundColor: done
          ? AppColors.success.withValues(alpha: 0.2)
          : Colors.white.withValues(alpha: 0.12),
      avatar: Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 16,
        color: done ? AppColors.success : Colors.white70,
      ),
    );
  }
}
