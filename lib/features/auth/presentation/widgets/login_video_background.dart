import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_colors.dart';

/// Full-screen looping MP4 used behind the Login and Sign Up UI.
///
/// Place the clip at [assetPath]. If the file is missing or playback fails,
/// a branded static gradient is shown so the screen never breaks.
class LoginVideoBackground extends StatefulWidget {
  const LoginVideoBackground({super.key});

  static const String assetPath =
      'assets/videos/thriftline_loadingscreen_login.mp4';

  @override
  State<LoginVideoBackground> createState() => _LoginVideoBackgroundState();
}

class _LoginVideoBackgroundState extends State<LoginVideoBackground>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  bool get _runningInTest {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'TestWidgetsFlutterBinding',
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_runningInTest) {
      _failed = true;
      return;
    }
    _initVideo();
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.asset(
      LoginVideoBackground.assetPath,
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      await controller.setVolume(0);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (error, stack) {
      debugPrint('Login video failed to load: $error\n$stack');
      await controller.dispose();
      if (_controller == controller) _controller = null;
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !_ready) return;
    if (state == AppLifecycleState.resumed) {
      controller.setVolume(0);
      controller.play();
    } else {
      controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    controller?.pause();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _failed || _controller == null) {
      return const _StaticFallback();
    }

    final size = _controller!.value.size;
    if (size.width == 0 || size.height == 0) {
      return const _StaticFallback();
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}

class _StaticFallback extends StatelessWidget {
  const _StaticFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primaryDark,
            Color(0xFF0F172A),
          ],
        ),
      ),
    );
  }
}
