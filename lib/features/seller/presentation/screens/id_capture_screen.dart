import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/id_camera_input_image.dart';
import '../../data/id_document_evidence_reader.dart';
import '../../data/id_image_quality_analyzer.dart';
import '../../data/id_photo_cropper.dart';
import '../../data/id_preview_luma.dart';
import '../../domain/id_document_classification.dart';
import '../../domain/id_image_quality.dart';
import '../widgets/id_capture_overlay.dart';

class IdCaptureResult {
  const IdCaptureResult({
    required this.frontBytes,
    required this.backBytes,
    required this.frontQuality,
    required this.backQuality,
  });

  final Uint8List frontBytes;
  final Uint8List backBytes;
  final IdQualityResult frontQuality;
  final IdQualityResult backQuality;
}

/// Camera capture + on-device review for both sides of the selected ID.
///
/// Auto-capture still uses live luma as a framing guide. The JPEG still
/// only asks whether the photo is an ID, not which government type or side.
class IdCaptureScreen extends StatefulWidget {
  const IdCaptureScreen({
    super.key,
    this.autoCaptureHold = IdCaptureGuide.autoCaptureHold,
  });

  /// Exposed so device testing can tune the hold without a rebuild of domain.
  final Duration autoCaptureHold;

  @override
  State<IdCaptureScreen> createState() => _IdCaptureScreenState();
}

class _IdCaptureScreenState extends State<IdCaptureScreen> {
  CameraController? _controller;
  late final LiveCaptureStability _stability;
  late final IdDocumentEvidenceReader _evidenceReader;
  late final IdImageQualityAnalyzer _qualityAnalyzer;
  IdCaptureSide _side = IdCaptureSide.front;
  Uint8List? _frontBytes;
  IdQualityResult? _frontQuality;
  IdQualityResult? _acceptedQuality;
  bool _ready = false;
  bool _capturing = false;
  bool _validating = false;
  String? _error;
  bool _permissionDenied = false;
  Uint8List? _preview;
  bool _busyFrame = false;
  DateTime? _lastAnalyzed;
  DateTime? _lastTextConfirm;
  LiveIdStatus? _confirmStatus;
  double? _confirmOccupancy;
  LiveIdStatus _status = LiveIdStatus.searching;
  String? _guidanceOverride;

  String get _placementTitle =>
      _side == IdCaptureSide.front ? 'FRONT OF ID' : 'BACK OF ID';

  bool get _reviewing => _preview != null && !_validating;

  @override
  void initState() {
    super.initState();
    _stability = LiveCaptureStability(hold: widget.autoCaptureHold);
    _evidenceReader = IdDocumentEvidenceReader(persistDetectors: true);
    _qualityAnalyzer = IdImageQualityAnalyzer(evidenceReader: _evidenceReader);
    _start();
  }

  Future<void> _start() async {
    _stability.reset();
    _resetTextConfirm();
    setState(() {
      _error = null;
      _permissionDenied = false;
      _ready = false;
      _preview = null;
      _status = LiveIdStatus.searching;
    });

    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      setState(() {
        _error = 'ID capture needs a real Android or iPhone camera.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera is available on this device.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
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
      _controller = controller;
      await _beginStream();
      if (!mounted) return;
      setState(() => _ready = true);
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
            ? 'Camera permission is required to capture your ID. Enable it in Settings, then try again.'
            : 'The camera is unavailable right now. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The camera is unavailable right now. Please try again.';
      });
    }
  }

  Future<void> _beginStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) return;
    try {
      await controller.startImageStream(_onFrame);
    } catch (_) {
      _applyAssessment(const LiveIdAssessment.searching());
    }
  }

  Future<void> _stopStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isStreamingImages) return;
    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  void _onFrame(CameraImage image) {
    if (_busyFrame ||
        _capturing ||
        _validating ||
        _preview != null ||
        !_ready) {
      return;
    }
    final now = DateTime.now();
    final last = _lastAnalyzed;
    if (last != null &&
        now.difference(last) < IdCaptureGuide.liveAnalyzeInterval) {
      return;
    }
    _lastAnalyzed = now;
    _busyFrame = true;
    try {
      final sampled = IdPreviewLuma.sample(
        image,
        rotationDegrees: _controller?.description.sensorOrientation ?? 0,
      );
      if (sampled == null) {
        _resetTextConfirm();
        _applyAssessment(const LiveIdAssessment.searching());
        _busyFrame = false;
        return;
      }
      final luma = IdImageMetrics.assessLivePreview(
        luma: sampled.luma,
        width: sampled.width,
        height: sampled.height,
      );
      if (!luma.isAligned) {
        _resetTextConfirm();
        _guidanceOverride = null;
        _applyAssessment(luma);
        _busyFrame = false;
        return;
      }

      if (_confirmStatus != null &&
          _confirmOccupancy != null &&
          (luma.occupancy - _confirmOccupancy!).abs() >
              IdCaptureGuide.motionOccupancyDelta) {
        _resetTextConfirm();
      }

      final lastConfirm = _lastTextConfirm;
      final confirmFresh =
          lastConfirm != null &&
          now.difference(lastConfirm) <
              IdCaptureGuide.liveTextConfirmInterval &&
          _confirmStatus != null;
      if (confirmFresh) {
        _applyAssessment(
          LiveIdAssessment(status: _confirmStatus!, occupancy: luma.occupancy),
        );
        _busyFrame = false;
        return;
      }

      final controller = _controller;
      final input = controller == null
          ? null
          : IdCameraInputImage.fromCamera(image, controller.description);
      _confirmPrintedId(input: input, lumaAssessment: luma);
    } catch (_) {
      _resetTextConfirm();
      _applyAssessment(const LiveIdAssessment.searching());
      _busyFrame = false;
    }
  }

  void _resetTextConfirm() {
    _confirmStatus = null;
    _lastTextConfirm = null;
    _confirmOccupancy = null;
  }

  Future<void> _confirmPrintedId({
    required InputImage? input,
    required LiveIdAssessment lumaAssessment,
  }) async {
    try {
      var evidence = const DocumentEvidence.unknown();
      if (input != null) {
        evidence = await _evidenceReader.inspectInputImage(
          input,
          overlay: OverlayNormRect.full,
          detectFaces: true,
        );
      }
      if (!mounted || _capturing || _validating || _preview != null) return;
      _lastTextConfirm = DateTime.now();
      _confirmOccupancy = lumaAssessment.occupancy;
      final confirmed = IdImageMetrics.confirmLiveDocument(
        lumaAssessment,
        evidence: evidence,
      );
      if (kDebugMode && evidence.available) {
        debugPrint(
          'ID_CAPTURE live id=${confirmed.isAligned} '
          'ocrChars=${evidence.alphanumericChars} '
          'face=${evidence.faceCoverage.toStringAsFixed(2)} '
          'ocr="${evidence.recognizedText.length > 80 ? evidence.recognizedText.substring(0, 80) : evidence.recognizedText}"',
        );
      }
      _guidanceOverride = confirmed.status == LiveIdStatus.notId
          ? 'No ID detected. Place your ID inside the frame.'
          : null;
      _confirmStatus = confirmed.status;
      _applyAssessment(confirmed);
    } catch (_) {
      if (!mounted || _capturing || _validating || _preview != null) return;
      _resetTextConfirm();
      _applyAssessment(lumaAssessment);
    } finally {
      _busyFrame = false;
    }
  }

  void _applyAssessment(LiveIdAssessment assessment) {
    if (!mounted || _capturing || _validating || _preview != null) return;
    final shouldCapture = _stability.observe(assessment, DateTime.now());
    if (assessment.status != _status) {
      setState(() => _status = assessment.status);
    }
    if (shouldCapture) {
      _capture();
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _capturing ||
        _validating ||
        _preview != null) {
      return;
    }
    _capturing = true;
    _stability.reset();
    if (mounted) setState(() {});
    String? tempPath;
    try {
      await _stopStream();
      final file = await controller.takePicture();
      tempPath = file.path;
      final bytes = await file.readAsBytes();
      final cropped = await IdPhotoCropper.cropToId(bytes);
      if (!mounted) return;

      setState(() {
        _capturing = false;
        _validating = true;
      });

      IdQualityResult quality;
      try {
        quality = await _qualityAnalyzer.analyze(cropped);
      } catch (_) {
        quality = IdQualityResult.fail(IdQualityIssue.uncertain);
      }
      if (!mounted) return;

      if (!quality.passed) {
        setState(() {
          _validating = false;
          _guidanceOverride = quality.message;
          _status = switch (quality.issue) {
            IdQualityIssue.blurry ||
            IdQualityIssue.slightlySoft => LiveIdStatus.blurry,
            IdQualityIssue.tooDark => LiveIdStatus.tooDark,
            _ => LiveIdStatus.notId,
          };
        });
        await _beginStream();
        if (!mounted) return;
        showThriftSnackBar(context, quality.message, isError: true);
        return;
      }

      setState(() {
        _preview = cropped;
        _acceptedQuality = quality;
        _validating = false;
        _status = LiveIdStatus.searching;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _validating = false;
      });
      await _beginStream();
      if (!mounted) return;
      showThriftSnackBar(
        context,
        'Could not capture the photo. Please try again.',
        isError: true,
      );
    } finally {
      final path = tempPath;
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _retake() async {
    _stability.reset();
    _resetTextConfirm();
    setState(() {
      _preview = null;
      _acceptedQuality = null;
      _capturing = false;
      _validating = false;
      _status = LiveIdStatus.searching;
    });
    await _beginStream();
  }

  Future<void> _usePhoto() async {
    final bytes = _preview;
    final quality = _acceptedQuality;
    if (bytes == null || bytes.isEmpty || quality == null || !quality.passed) {
      return;
    }

    if (_side == IdCaptureSide.front) {
      _stability.reset();
      _resetTextConfirm();
      setState(() {
        _frontBytes = bytes;
        _frontQuality = quality;
        _side = IdCaptureSide.back;
        _preview = null;
        _acceptedQuality = null;
        _capturing = false;
        _validating = false;
        _status = LiveIdStatus.searching;
      });
      await _beginStream();
      return;
    }

    final frontBytes = _frontBytes;
    final frontQuality = _frontQuality;
    if (frontBytes == null || frontQuality == null || !frontQuality.passed) {
      return;
    }
    Navigator.of(context).pop(
      IdCaptureResult(
        frontBytes: frontBytes,
        backBytes: bytes,
        frontQuality: frontQuality,
        backQuality: quality,
      ),
    );
  }

  Future<void> _handleBack() async {
    if (_validating || _capturing) return;
    if (_preview != null) {
      await _retake();
      return;
    }
    if (_side == IdCaptureSide.back &&
        _frontBytes != null &&
        _frontQuality != null) {
      await _stopStream();
      _stability.reset();
      _resetTextConfirm();
      setState(() {
        _side = IdCaptureSide.front;
        _preview = _frontBytes;
        _acceptedQuality = _frontQuality;
        _status = LiveIdStatus.searching;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  void _showHelp() {
    final sideCopy = _side == IdCaptureSide.front ? 'front' : 'back';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How to capture your ID'),
        content: Text(
          'Use an accepted government ID. Place the $sideCopy of the ID '
          'inside the frame so all four edges are visible. Hold it still. '
          'The photo is taken automatically when an ID is clear and aligned '
          '— you do not need to tap a button.\n\n'
          'Use a well-lit area and avoid glare on the card.',
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
  void dispose() {
    _evidenceReader.close();
    final controller = _controller;
    _controller = null;
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _reviewing ? _buildReview() : _buildCamera(),
      ),
    );
  }

  Widget _buildCamera() {
    if (_error != null) {
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
        IdCaptureOverlay(
          status: _status,
          capturing: _capturing || _validating,
          statusMessage: _validating ? 'Checking the ID…' : _guidanceOverride,
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: _handleBack,
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                  ),
                ),
                Expanded(
                  child: Text(
                    _placementTitle,
                    style: AppTypography.subheading.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      shadows: const [
                        Shadow(blurRadius: 8, color: Colors.black54),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: 'Help',
                  onPressed: _showHelp,
                  icon: const Icon(Icons.help_outline, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReview() {
    final sideLabel = _side == IdCaptureSide.front ? 'front' : 'back';
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: _handleBack,
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Review this photo',
                    style: AppTypography.subheading.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'This $sideLabel photo looks like an ID. '
              'Use it to continue, or retake if it is hard to read.',
              style: AppTypography.body.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  _preview!,
                  fit: BoxFit.contain,
                  width: double.infinity,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              children: [
                ThriftButton(label: 'Use this photo', onPressed: _usePhoto),
                const SizedBox(height: 10),
                ThriftButton(
                  label: 'Retake',
                  variant: ThriftButtonVariant.outline,
                  onPressed: _retake,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
