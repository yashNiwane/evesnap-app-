import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/eve_palette.dart';

class EveCameraScreen extends StatefulWidget {
  const EveCameraScreen({
    super.key,
    this.onPhotoAccepted,
    this.closeAfterAccept = true,
  });

  final Future<void> Function(XFile image)? onPhotoAccepted;
  final bool closeAfterAccept;

  @override
  State<EveCameraScreen> createState() => _EveCameraScreenState();
}

class _EveCameraScreenState extends State<EveCameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  _TimerMode _timerMode = _TimerMode.off;
  double _maxZoom = 1;
  double _zoom = 1;
  double _minExposure = 0;
  double _maxExposure = 0;
  double _exposure = 0;
  bool _showGrid = false;
  bool _initializing = true;
  bool _capturing = false;
  int _timerCountdown = 0;
  Offset? _focusPoint;
  bool _showFocusHud = false;
  double _scaleStartZoom = 1;
  Timer? _focusHudTimer;
  
  // Video Recording State
  bool _isRecordingVideo = false;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  
  // Real-time Device Orientation
  DeviceOrientation _deviceOrientation = DeviceOrientation.portraitUp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera(_cameraIndex);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusHudTimer?.cancel();
    _recordingTimer?.cancel();
    _controller?.removeListener(_onCameraControllerValueChange);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      _cameras = await availableCameras();
      final backIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      _cameraIndex = backIndex < 0 ? 0 : backIndex;
      await _startCamera(_cameraIndex);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not open camera: $e');
      setState(() => _initializing = false);
    }
  }

  Future<void> _startCamera(int index) async {
    if (_cameras.isEmpty) {
      setState(() => _initializing = false);
      return;
    }

    setState(() => _initializing = true);
    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      oldController.removeListener(_onCameraControllerValueChange);
      await oldController.dispose();
    }

    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      controller.addListener(_onCameraControllerValueChange);
      await controller.setFlashMode(_flashMode);
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final zoom = 1.0.clamp(minZoom, maxZoom);
      await controller.setZoomLevel(zoom);
      
      final minExposure = await controller.getMinExposureOffset();
      final maxExposure = await controller.getMaxExposureOffset();
      final exposure = 0.0.clamp(minExposure, maxExposure);
      if (maxExposure > minExposure) {
        await controller.setExposureOffset(exposure);
      }
      
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraIndex = index;
        _controller = controller;
        _maxZoom = maxZoom;
        _zoom = zoom;
        _minExposure = minExposure;
        _maxExposure = maxExposure;
        _exposure = exposure;
        _initializing = false;
      });
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _initializing = false);
      _showMessage('Camera failed to start: $e');
    }
  }

  void _onCameraControllerValueChange() {
    if (!mounted) return;
    final newOrientation = _controller?.value.deviceOrientation;
    if (newOrientation != null && newOrientation != _deviceOrientation) {
      setState(() {
        _deviceOrientation = newOrientation;
      });
    }
  }

  double get _iconTurns {
    return switch (_deviceOrientation) {
      DeviceOrientation.portraitUp => 0.0,
      DeviceOrientation.landscapeLeft => -0.25,
      DeviceOrientation.landscapeRight => 0.25,
      DeviceOrientation.portraitDown => 0.5,
    };
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_capturing || controller == null || !controller.value.isInitialized) {
      return;
    }

    setState(() => _capturing = true);
    try {
      if (_timerMode.seconds > 0) {
        for (var seconds = _timerMode.seconds; seconds > 0; seconds -= 1) {
          if (!mounted) return;
          setState(() => _timerCountdown = seconds);
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (mounted) setState(() => _timerCountdown = 0);
      }
      
      final image = await controller.takePicture();
      if (!mounted) return;
      
      final accepted = await Navigator.push<XFile>(
        context,
        MaterialPageRoute(
          builder: (_) => _EveCameraReviewScreen(photo: image),
        ),
      );
      
      if (accepted != null) {
        final onPhotoAccepted = widget.onPhotoAccepted;
        if (onPhotoAccepted != null) {
          await onPhotoAccepted(accepted);
          if (mounted) {
            final isLandscape = _deviceOrientation == DeviceOrientation.landscapeLeft ||
                _deviceOrientation == DeviceOrientation.landscapeRight;
            final photoType = isLandscape ? 'Landscape' : 'Portrait';
            _showMessage('Added $photoType Moment.');
          }
        }
        if (widget.closeAfterAccept && mounted) {
          Navigator.pop(context, accepted);
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not capture photo: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    final accepted = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(
        builder: (_) => _EveCameraReviewScreen(photo: picked),
      ),
    );
    if (!mounted) return;
    if (accepted != null) {
      final onPhotoAccepted = widget.onPhotoAccepted;
      if (onPhotoAccepted != null) {
        await onPhotoAccepted(accepted);
      }
      if (widget.closeAfterAccept && mounted) {
        Navigator.pop(context, accepted);
      }
    }
  }

  Future<void> _startVideoRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isRecordingVideo) {
      return;
    }

    try {
      Feedback.forLongPress(context);
      
      await controller.startVideoRecording();
      if (!mounted) return;
      
      _recordingTimer?.cancel();
      setState(() {
        _isRecordingVideo = true;
        _recordingDuration = 0;
      });
      
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDuration++;
          });
        } else {
          timer.cancel();
        }
      });
    } catch (e) {
      _showMessage('Could not start video recording: $e');
    }
  }

  Future<void> _stopVideoRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || !_isRecordingVideo) {
      return;
    }

    _recordingTimer?.cancel();
    
    try {
      final video = await controller.stopVideoRecording();
      if (!mounted) return;
      
      setState(() {
        _isRecordingVideo = false;
      });

      if (_recordingDuration < 1) {
        _showMessage('Video must be at least 1 second.');
        return;
      }

      final accepted = await Navigator.push<XFile>(
        context,
        MaterialPageRoute(
          builder: (_) => _EveCameraReviewScreen(photo: video, isVideo: true),
        ),
      );
      
      if (!mounted) return;
      if (accepted != null) {
        final onPhotoAccepted = widget.onPhotoAccepted;
        if (onPhotoAccepted != null) {
          await onPhotoAccepted(accepted);
          if (mounted) {
            _showMessage('Moment added.');
          }
        }
        if (widget.closeAfterAccept && mounted) {
          Navigator.pop(context, accepted);
        }
      }
    } catch (e) {
      _showMessage('Could not stop video recording: $e');
      if (mounted) {
        setState(() {
          _isRecordingVideo = false;
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _initializing) return;
    final nextIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera(nextIndex);
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;

    final nextMode = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
    };
    try {
      await controller.setFlashMode(nextMode);
      if (mounted) setState(() => _flashMode = nextMode);
    } catch (_) {
      _showMessage('Flash is not available on this camera.');
    }
  }

  Future<void> _setZoom(double value) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final zoom = value.clamp(1.0, _maxZoom);
    setState(() => _zoom = zoom);
    try {
      await controller.setZoomLevel(zoom);
    } catch (_) {}
  }

  Future<void> _setExposure(double value) async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _maxExposure <= _minExposure) {
      return;
    }

    final exposure = value.clamp(_minExposure, _maxExposure);
    setState(() => _exposure = exposure);
    try {
      await controller.setExposureOffset(exposure);
    } catch (_) {}
  }

  void _cycleTimer() {
    final values = _TimerMode.values;
    final next = values[(values.indexOf(_timerMode) + 1) % values.length];
    setState(() => _timerMode = next);
  }

  Future<void> _focusAt(
    TapDownDetails details,
    BoxConstraints constraints,
  ) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    setState(() {
      _focusPoint = details.localPosition;
      _showFocusHud = true;
    });
    
    _focusHudTimer?.cancel();
    _focusHudTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showFocusHud = false);
    });

    try {
      await controller.setFocusPoint(offset);
      await controller.setExposurePoint(offset);
    } catch (_) {}
  }

  void _startZoom(ScaleStartDetails details) {
    _scaleStartZoom = _zoom;
  }

  Future<void> _updateZoom(ScaleUpdateDetails details) async {
    if (details.pointerCount < 2) return;
    await _setZoom(_scaleStartZoom * details.scale);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  IconData get _flashIcon {
    return switch (_flashMode) {
      FlashMode.off => Icons.flash_off_rounded,
      FlashMode.auto => Icons.flash_auto_rounded,
      FlashMode.always => Icons.flash_on_rounded,
      FlashMode.torch => Icons.highlight_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final screenSize = MediaQuery.sizeOf(context);
    final focusLeft = _focusPoint == null
        ? 0.0
        : (_focusPoint!.dx - 68).clamp(10.0, screenSize.width - 146.0);
    final focusTop = _focusPoint == null
        ? 0.0
        : (_focusPoint!.dy - 56).clamp(96.0, screenSize.height - 220.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _initializing ||
                      controller == null ||
                      !controller.value.isInitialized
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          onTapDown: (details) =>
                              _focusAt(details, constraints),
                          onScaleStart: _startZoom,
                          onScaleUpdate: _updateZoom,
                          child: ClipRect(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: controller.value.previewSize?.height ?? 1080.0,
                                  height: controller.value.previewSize?.width ?? 1920.0,
                                  child: CameraPreview(controller),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CameraOverlayPainter(showGrid: _showGrid),
                ),
              ),
            ),
            if (_timerCountdown > 0)
              Center(
                child: Text(
                  '$_timerCountdown',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 86,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            if (_showFocusHud && _focusPoint != null)
              Positioned(
                left: focusLeft,
                top: focusTop,
                child: _FocusHud(
                  exposure: _exposure,
                  exposureAvailable: _maxExposure > _minExposure,
                  minExposure: _minExposure,
                  maxExposure: _maxExposure,
                  onExposure: _setExposure,
                ),
              ),
            if (_isRecordingVideo)
              Positioned(
                left: 0,
                right: 0,
                top: 24,
                child: Center(
                  child: _VideoRecordingHUD(durationSeconds: _recordingDuration),
                ),
              )
            else
              Positioned(
                left: 18,
                right: 18,
                top: 16,
                child: Row(
                  children: [
                    _CameraIconButton(
                      tooltip: 'Close',
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.pop(context),
                      turns: _iconTurns,
                    ),
                    const Spacer(),
                    _CameraIconButton(
                      tooltip: 'Flash',
                      icon: _flashIcon,
                      onTap: _toggleFlash,
                      turns: _iconTurns,
                    ),
                    const SizedBox(width: 8),
                    _CameraIconButton(
                      tooltip: 'Timer',
                      icon: Icons.timer_rounded,
                      selected: _timerMode != _TimerMode.off,
                      onTap: _cycleTimer,
                      turns: _iconTurns,
                    ),
                    const SizedBox(width: 8),
                    _CameraIconButton(
                      tooltip: 'Grid',
                      icon: Icons.grid_3x3_rounded,
                      selected: _showGrid,
                      onTap: () => setState(() => _showGrid = !_showGrid),
                      turns: _iconTurns,
                    ),
                  ],
                ),
              ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 22,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CameraIconButton(
                    tooltip: 'Gallery',
                    icon: Icons.photo_library_rounded,
                    onTap: _pickFromGallery,
                    turns: _iconTurns,
                  ),
                  GestureDetector(
                    onTap: _capturing || _isRecordingVideo ? null : _capture,
                    onLongPressStart: _capturing ? null : (_) => _startVideoRecording(),
                    onLongPressEnd: _capturing ? null : (_) => _stopVideoRecording(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: _isRecordingVideo ? 92 : (_capturing ? 76 : 84),
                      height: _isRecordingVideo ? 92 : (_capturing ? 76 : 84),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isRecordingVideo ? Colors.red : Colors.white,
                          width: _isRecordingVideo ? 7 : 5,
                        ),
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: _isRecordingVideo ? 32 : (_capturing ? 46 : 62),
                          height: _isRecordingVideo ? 32 : (_capturing ? 46 : 62),
                          decoration: BoxDecoration(
                            color: _isRecordingVideo ? Colors.red : Colors.white,
                            borderRadius: BorderRadius.circular(_isRecordingVideo ? 8 : 999),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _CameraIconButton(
                    tooltip: 'Switch camera',
                    icon: Icons.cameraswitch_rounded,
                    onTap: _switchCamera,
                    turns: _iconTurns,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TimerMode {
  off('Timer', 0),
  three('3s', 3),
  ten('10s', 10);

  const _TimerMode(this.label, this.seconds);

  final String label;
  final int seconds;
}

class _EveCameraReviewScreen extends StatelessWidget {
  const _EveCameraReviewScreen({required this.photo, this.isVideo = false});

  final XFile photo;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isVideo)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.videocam_rounded,
                      color: Colors.white,
                      size: 80,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Video Moment Captured',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        photo.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Image.file(
                File(photo.path),
                fit: BoxFit.contain,
              ),
            Positioned(
              left: 18,
              right: 18,
              top: 16,
              child: Row(
                children: [
                  _CameraIconButton(
                    tooltip: 'Retake',
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, photo),
                    style: FilledButton.styleFrom(
                      backgroundColor: EvePalette.bone,
                      foregroundColor: EvePalette.ink,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      isVideo ? 'Use video' : 'Use photo',
                      style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraIconButton extends StatelessWidget {
  const _CameraIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.turns = 0.0,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final double turns;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.88)
                : Colors.black.withValues(alpha: 0.42),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Center(
            child: AnimatedRotation(
              turns: turns,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: Icon(
                icon,
                color: selected ? Colors.black : Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusHud extends StatelessWidget {
  const _FocusHud({
    required this.exposure,
    required this.exposureAvailable,
    required this.minExposure,
    required this.maxExposure,
    required this.onExposure,
  });

  final double exposure;
  final bool exposureAvailable;
  final double minExposure;
  final double maxExposure;
  final ValueChanged<double> onExposure;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 136,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(74, 74),
            painter: const _FocusReticlePainter(),
          ),
          if (exposureAvailable) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.wb_sunny_rounded,
                      color: Color(0xFFFFD400),
                      size: 16,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 1.5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                      ),
                      child: Slider(
                        value: exposure.clamp(minExposure, maxExposure),
                        min: minExposure,
                        max: maxExposure,
                        onChanged: onExposure,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FocusReticlePainter extends CustomPainter {
  const _FocusReticlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const arm = 20.0;
    const gap = 12.0;
    final left = (size.width - 52) / 2;
    final top = (size.height - 52) / 2;
    final right = left + 52;
    final bottom = top + 52;
    canvas.drawLine(Offset(left, top + arm), Offset(left, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left + arm, top), paint);
    canvas.drawLine(Offset(right - arm, top), Offset(right, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + arm), paint);
    canvas.drawLine(Offset(left, bottom - arm), Offset(left, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left + arm, bottom), paint);
    canvas.drawLine(Offset(right - arm, bottom), Offset(right, bottom), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - arm), paint);
    canvas.drawLine(
      Offset(size.width / 2 - gap, size.height / 2),
      Offset(size.width / 2 - 3, size.height / 2),
      paint,
    );
    canvas.drawLine(
      Offset(size.width / 2 + 3, size.height / 2),
      Offset(size.width / 2 + gap, size.height / 2),
      paint,
    );
    canvas.drawLine(
      Offset(size.width / 2, size.height / 2 - gap),
      Offset(size.width / 2, size.height / 2 - 3),
      paint,
    );
    canvas.drawLine(
      Offset(size.width / 2, size.height / 2 + 3),
      Offset(size.width / 2, size.height / 2 + gap),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FocusReticlePainter oldDelegate) => false;
}

class _CameraOverlayPainter extends CustomPainter {
  const _CameraOverlayPainter({required this.showGrid});

  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showGrid) return;
    
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final thirdW = size.width / 3;
    final thirdH = size.height / 3;
    canvas.drawLine(Offset(thirdW, 0), Offset(thirdW, size.height), paint);
    canvas.drawLine(
      Offset(thirdW * 2, 0),
      Offset(thirdW * 2, size.height),
      paint,
    );
    canvas.drawLine(Offset(0, thirdH), Offset(size.width, thirdH), paint);
    canvas.drawLine(
      Offset(0, thirdH * 2),
      Offset(size.width, thirdH * 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CameraOverlayPainter oldDelegate) {
    return oldDelegate.showGrid != showGrid;
  }
}

class _VideoRecordingHUD extends StatefulWidget {
  const _VideoRecordingHUD({required this.durationSeconds});

  final int durationSeconds;

  @override
  State<_VideoRecordingHUD> createState() => _VideoRecordingHUDState();
}

class _VideoRecordingHUDState extends State<_VideoRecordingHUD>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _pulseAnimation,
            child: const Icon(
              Icons.circle,
              color: Colors.red,
              size: 10,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'REC',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 12,
            color: Colors.white.withValues(alpha: 0.28),
          ),
          const SizedBox(width: 12),
          Text(
            _formatDuration(widget.durationSeconds),
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
