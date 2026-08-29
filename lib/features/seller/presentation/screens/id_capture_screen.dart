import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../domain/seller_id_type.dart';
import '../widgets/id_capture_overlay.dart';

enum IdCaptureSide { front, back }

class IdCaptureResult {
  const IdCaptureResult({required this.side, required this.bytes});

  final IdCaptureSide side;
  final Uint8List bytes;
}

/// Camera capture + on-device review for one side of an ID.
class IdCaptureScreen extends StatefulWidget {
  const IdCaptureScreen({
    super.key,
    required this.side,
    required this.idType,
  });

  final IdCaptureSide side;
  final SellerIdType idType;

  @override
  State<IdCaptureScreen> createState() => _IdCaptureScreenState();
}

class _IdCaptureScreenState extends State<IdCaptureScreen> {
  CameraController? _controller;
  bool _ready = false;
  bool _capturing = false;
  String? _error;
  bool _permissionDenied = false;
  Uint8List? _preview;

  String get _sideLabel =>
      widget.side == IdCaptureSide.front ? 'Front of ID' : 'Back of ID';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _permissionDenied = false;
      _ready = false;
      _preview = null;
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
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _ready = true);
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.toLowerCase().contains('access') ||
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

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    String? tempPath;
    try {
      final file = await controller.takePicture();
      tempPath = file.path;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _preview = bytes;
        _capturing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _capturing = false);
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

  void _retake() {
    setState(() => _preview = null);
  }

  void _usePhoto() {
    final bytes = _preview;
    if (bytes == null || bytes.isEmpty) return;
    Navigator.of(context).pop(
      IdCaptureResult(side: widget.side, bytes: bytes),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(_sideLabel),
        ),
        body: SafeArea(
          child: _preview != null ? _buildReview() : _buildCamera(),
        ),
      ),
    );
  }

  Widget _buildCamera() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _permissionDenied ? Icons.lock_outline : Icons.videocam_off_outlined,
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
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(
            'Align the ${widget.idType.label} inside the frame. Avoid glare and hold still.',
            style: AppTypography.body.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AspectRatio(
              aspectRatio: 1.6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_ready && _controller != null)
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _controller!.value.previewSize?.height ?? 100,
                          height: _controller!.value.previewSize?.width ?? 100,
                          child: CameraPreview(_controller!),
                        ),
                      )
                    else
                      const ColoredBox(
                        color: Colors.black,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    const IdCaptureOverlay(),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: ThriftButton(
            label: _capturing ? 'Capturing…' : 'Capture $_sideLabel',
            isLoading: _capturing,
            onPressed: _ready && !_capturing ? _capture : null,
          ),
        ),
      ],
    );
  }

  Widget _buildReview() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(
            'Review this photo. Retake if the text is hard to read.',
            style: AppTypography.body.copyWith(color: Colors.white),
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
    );
  }
}
