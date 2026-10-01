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
import '../../domain/seller_id_type.dart';
import '../widgets/id_capture_overlay.dart';

class IdCaptureResult {
  const IdCaptureResult({
    required this.frontBytes,
    this.backBytes,
    required this.frontQuality,
    this.backQuality,
  });

  final Uint8List frontBytes;
  final Uint8List? backBytes;
  final IdQualityResult frontQuality;
  final IdQualityResult? backQuality;
}

/// Camera capture and review for the sides the selected ID actually uses.
///
/// Live luma only decides whether the frame is worth a document check.
/// The frame turns valid after the selected type and side agree, and the
/// saved JPEG is checked again. This does not prove the ID is authentic.
class IdCaptureScreen extends StatefulWidget {
  const IdCaptureScreen({
    super.key,
    required this.idType,
    this.autoCaptureHold = IdCaptureGuide.autoCaptureHold,
  });

  final SellerIdType idType;

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

  /// Clockwise turns that last read the on-screen ID upright.
  int _liveQuarterTurns = 0;
  int _probeCursor = 0;

  double get _aspect => IdCaptureGuide.aspectFor(widget.idType);

  bool get _needsBack => widget.idType.requiresBackCapture;

  String get _sideInstruction {
    if (widget.idType == SellerIdType.passport) {
      return 'Capture the photo page';
    }
    if (!_needsBack) return 'Capture the front';
    return _side == IdCaptureSide.front
        ? 'Capture the front'
        : 'Capture the back';
  }

  String get _sideNoun {
    if (widget.idType == SellerIdType.passport) return 'photo page';
    if (!_needsBack) return 'front';
    return _side == IdCaptureSide.front ? 'front' : 'back';
  }

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
      // Digital National ID labels are tiny on a phone screen; 720p frames
      // leave them a few pixels tall, too small for on-device OCR.
      final controller = CameraController(
        back,
        widget.idType.presentedOnScreen
            ? ResolutionPreset.veryHigh
            : ResolutionPreset.high,
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
        cardAspect: _aspect,
      );
      if (!luma.isAligned) {
        _resetTextConfirm();
        _guidanceOverride = _placementHint(luma);
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

  String _captureFeedback(IdQualityResult quality) {
    if (!widget.idType.presentedOnScreen) return quality.message;
    return switch (quality.issue) {
      IdQualityIssue.glare => 'Reduce glare on the screen.',
      IdQualityIssue.blurry ||
      IdQualityIssue.slightlySoft => 'Hold the camera steady.',
      IdQualityIssue.tooFar => 'Move closer so the details are visible.',
      IdQualityIssue.poorFraming =>
        'Make sure the full Digital National ID is visible.',
      _ => quality.message,
    };
  }

  String _placementHint(LiveIdAssessment assessment) {
    final label = widget.idType.label;
    return assessment.message ??
        switch (assessment.status) {
          LiveIdStatus.tooFar =>
            widget.idType.presentedOnScreen
                ? 'Move closer so the details are visible.'
                : 'Move your $label closer.',
          LiveIdStatus.tooDark => 'Move to a brighter spot.',
          LiveIdStatus.blurry =>
            widget.idType.presentedOnScreen
                ? 'Hold the camera steady.'
                : 'Image is too blurry.',
          LiveIdStatus.poorlyFramed =>
            widget.idType.presentedOnScreen
                ? 'Make sure the full Digital National ID is visible.'
                : 'Fit the whole $label inside the frame.',
          LiveIdStatus.wrongSide => IdDocumentClassifier.wrongSideMessage(
            _side,
            widget.idType,
          ),
          LiveIdStatus.aligned => 'Hold your $label steady.',
          _ =>
            widget.idType.presentedOnScreen
                ? 'Turn the phone showing your ID sideways to fill the frame.'
                : 'Place your $label in the frame.',
        };
  }

  /// Guide hole in [input] (camera upright), then turned with the frame.
  OverlayNormRect _guideOverlay(InputImage input, {int quarterTurns = 0}) {
    final metadata = input.metadata;
    final size = metadata?.size;
    if (size == null || size.width < 8 || size.height < 8) {
      return OverlayNormRect.full;
    }
    final upright = IdDocumentEvidenceReader.displaySize(
      width: size.width,
      height: size.height,
      rotation: metadata?.rotation,
    );
    return IdImageMetrics.guideOverlay(
      width: upright.width.round(),
      height: upright.height.round(),
      aspect: _aspect,
    ).rotatedClockwise(quarterTurns);
  }

  Future<LiveIdAssessment> _confirmAt(
    InputImage input,
    int quarterTurns,
    LiveIdAssessment lumaAssessment,
  ) async {
    final turned = IdCameraInputImage.turned(input, quarterTurns);
    final evidence = turned == null
        ? const DocumentEvidence.unknown()
        : await _evidenceReader.inspectInputImage(
            turned,
            overlay: _guideOverlay(input, quarterTurns: quarterTurns),
            detectFaces: true,
          );
    final confirmed = IdDocumentClassifier.confirmLive(
      luma: lumaAssessment,
      evidence: evidence,
      expectedType: widget.idType,
      expectedSide: _side,
      sessionTypeConfirmed:
          _side == IdCaptureSide.back && _frontQuality?.passed == true,
    );
    if (kDebugMode && evidence.available) {
      debugPrint(
        'ID_CAPTURE live aligned=${confirmed.isAligned} '
        'expected_type=${widget.idType.storageValue} '
        'expected_side=${_side.name} '
        'turns=$quarterTurns '
        'ocr_chars=${evidence.alphanumericChars} '
        'face=${evidence.faceCoverage.toStringAsFixed(2)} '
        'status=${confirmed.status.name}',
      );
    }
    return confirmed;
  }

  /// Next orientation to probe when the on-screen ID was not recognized.
  int _nextProbeTurns() {
    const turns = IdImageQualityAnalyzer.screenQuarterTurns;
    for (var i = 0; i < turns.length; i++) {
      final candidate = turns[_probeCursor % turns.length];
      _probeCursor++;
      if (candidate != _liveQuarterTurns) return candidate;
    }
    return _liveQuarterTurns;
  }

  Future<void> _confirmPrintedId({
    required InputImage? input,
    required LiveIdAssessment lumaAssessment,
  }) async {
    try {
      var confirmed = input == null
          ? IdDocumentClassifier.confirmLive(
              luma: lumaAssessment,
              evidence: const DocumentEvidence.unknown(),
              expectedType: widget.idType,
              expectedSide: _side,
            )
          : await _confirmAt(input, _liveQuarterTurns, lumaAssessment);
      // One extra orientation per frame keeps the preview responsive while
      // still cycling through every way the phone can be held.
      if (input != null &&
          widget.idType.presentedOnScreen &&
          !confirmed.isAligned &&
          confirmed.status == LiveIdStatus.notId &&
          mounted &&
          !_capturing &&
          !_validating &&
          _preview == null) {
        final probe = _nextProbeTurns();
        if (probe != _liveQuarterTurns) {
          final turned = await _confirmAt(input, probe, lumaAssessment);
          if (turned.isAligned || turned.status == LiveIdStatus.wrongSide) {
            _liveQuarterTurns = probe;
            confirmed = turned;
          }
        }
      }
      if (!mounted || _capturing || _validating || _preview != null) return;
      _lastTextConfirm = DateTime.now();
      _confirmOccupancy = lumaAssessment.occupancy;
      _guidanceOverride = confirmed.message ?? _placementHint(confirmed);
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
      final cropped = await IdPhotoCropper.cropToId(bytes, cardAspect: _aspect);
      if (!mounted) return;

      setState(() {
        _capturing = false;
        _validating = true;
      });

      IdQualityResult quality;
      var accepted = cropped;
      try {
        final result = await _qualityAnalyzer.analyzeOriented(
          cropped,
          expectedType: widget.idType,
          expectedSide: _side,
          sessionTypeConfirmed:
              _side == IdCaptureSide.back && _frontQuality?.passed == true,
          requireIdPhoto: _side == IdCaptureSide.front,
          preferredQuarterTurns: _liveQuarterTurns,
        );
        quality = result.quality;
        if (quality.passed) {
          accepted = result.bytes;
          _liveQuarterTurns = result.quarterTurns;
        }
      } catch (_) {
        quality = IdQualityResult.fail(IdQualityIssue.uncertain);
      }
      if (!mounted) return;

      if (!quality.passed) {
        setState(() {
          _validating = false;
          _guidanceOverride = _captureFeedback(quality);
          _status = switch (quality.issue) {
            IdQualityIssue.blurry ||
            IdQualityIssue.slightlySoft => LiveIdStatus.blurry,
            IdQualityIssue.tooDark ||
            IdQualityIssue.lowContrast => LiveIdStatus.tooDark,
            IdQualityIssue.tooFar => LiveIdStatus.tooFar,
            IdQualityIssue.poorFraming => LiveIdStatus.poorlyFramed,
            IdQualityIssue.wrongSide => LiveIdStatus.wrongSide,
            IdQualityIssue.glare => LiveIdStatus.blurry,
            _ => LiveIdStatus.notId,
          };
        });
        await _beginStream();
        if (!mounted) return;
        showThriftSnackBar(context, _captureFeedback(quality), isError: true);
        return;
      }

      setState(() {
        _preview = accepted;
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
      _guidanceOverride = null;
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
      if (!_needsBack) {
        Navigator.of(
          context,
        ).pop(IdCaptureResult(frontBytes: bytes, frontQuality: quality));
        return;
      }
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
        _guidanceOverride = null;
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
    final label = widget.idType.label;
    final sideCopy = _sideNoun;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Capture your $label'),
        content: Text(
          widget.idType.presentedOnScreen
              ? 'Open your Digital National ID in the eGov app, or a '
                    'screenshot of it, on another phone. Turn that phone '
                    'sideways so the $sideCopy fills the frame. The photo, '
                    'details, and code should be visible. Turn the screen '
                    'brightness up, hold steady, and avoid glare.\n\n'
                    'This check does not prove the ID is genuine. ThriftLine '
                    'still reviews your application.'
              : widget.idType == SellerIdType.passport
              ? 'Place the photo page of your passport inside the frame so '
                    'the edges, photo, and details are visible. Hold it still. '
                    'The photo is taken automatically when it matches this '
                    'page and is clear.\n\n'
                    'Use a well-lit area and avoid glare. A photo of a screen '
                    'is not accepted. This check does not prove the passport '
                    'is genuine — ThriftLine still reviews your application.'
              : 'Place the $sideCopy of your $label inside the frame so the edges '
                    'are visible. Hold it still. The photo is taken automatically when '
                    'it matches this ID and is clear.\n\n'
                    'Use a well-lit area and avoid glare. A photo of a screen is not '
                    'accepted. This check does not prove the ID is genuine — ThriftLine '
                    'still reviews your application.',
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
          cardAspect: _aspect,
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.idType.label,
                        style: AppTypography.subheading.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: const [
                            Shadow(blurRadius: 8, color: Colors.black54),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _sideInstruction,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          shadows: const [
                            Shadow(blurRadius: 8, color: Colors.black54),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
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
    final sideWord = _sideNoun;
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
              'ID image accepted for the $sideWord '
              'of your ${widget.idType.label}. Use it, or retake if it is hard to read.',
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
