import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// In-app camera locked to a 4:3 capture frame with normal capture → review
/// (Retake / Use Photo) flow and low-memory downscaled 4:3 encoding.
class ProofCameraScreen extends StatefulWidget {
  const ProofCameraScreen({super.key});

  @override
  State<ProofCameraScreen> createState() => _ProofCameraScreenState();
}

class _ProofCameraScreenState extends State<ProofCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIdx = 0;
  bool _initializing = true;
  bool _capturing = false;
  FlashMode _flashMode = FlashMode.off;
  String? _error;
  String? _capturedPath; // When non-null, shows normal Retake / Use Photo preview

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    super.dispose();
  }

  Future<void> _disposeController() async {
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      try {
        await ctrl.dispose();
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_initializing || _capturing || _capturedPath != null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _disposeController();
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        _cameras.isNotEmpty) {
      _startController(_cameras[_cameraIdx]);
    }
  }

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      // Request camera permission cleanly BEFORE initializing CameraX so
      // permission dialogs never interrupt CameraController.initialize().
      final perm = await Permission.camera.request();
      if (!mounted) return;
      if (!perm.isGranted) {
        setState(() {
          _initializing = false;
          _error = 'Camera permission is required to capture proof photo.';
        });
        return;
      }

      final cams = await availableCameras();
      if (!mounted) return;
      if (cams.isEmpty) {
        setState(() {
          _initializing = false;
          _error = 'No camera found on this device.';
        });
        return;
      }
      _cameras = cams;
      final backIdx =
          cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _cameraIdx = backIdx >= 0 ? backIdx : 0;
      await _startController(_cameras[_cameraIdx]);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not open camera. Please check camera permission.';
      });
    }
  }

  Future<void> _startController(CameraDescription cam) async {
    await _disposeController();
    final ctrl = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = ctrl;
    try {
      await ctrl.initialize();
      try {
        await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      try {
        await ctrl.setFlashMode(_flashMode);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = null;
        });
      }
    } catch (_) {
      await _disposeController();
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Camera could not start. Tap below to retry.';
        });
      }
    }
  }

  Future<void> _cycleFlash() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final next = _flashMode == FlashMode.off
        ? FlashMode.auto
        : _flashMode == FlashMode.auto
            ? FlashMode.always
            : FlashMode.off;
    try {
      await ctrl.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _capturing) return;
    _cameraIdx = (_cameraIdx + 1) % _cameras.length;
    setState(() => _initializing = true);
    await _startController(_cameras[_cameraIdx]);
  }

  /// Captures a photo, safely frames it to exact 4:3 with low memory usage,
  /// and shows the normal preview screen (Retake / Use Photo).
  Future<void> _capture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final raw = await ctrl.takePicture();
      final croppedPath = await _cropToFourThreeSafe(raw.path);
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _capturedPath = croppedPath;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to capture photo. Please try again.'),
          ),
        );
      }
    }
  }

  /// Decodes with a bounded targetWidth (960px) so high-MP Android sensors
  /// never spike RAM / OOM-kill the app, then center-frames to exact 4:3.
  Future<String> _cropToFourThreeSafe(String sourcePath) async {
    ui.Codec? codec;
    ui.Image? src;
    ui.Picture? picture;
    ui.Image? outImg;
    try {
      final bytes = await File(sourcePath).readAsBytes();
      codec = await ui.instantiateImageCodec(bytes, targetWidth: 960);
      final frame = await codec.getNextFrame();
      src = frame.image;

      final srcW = src.width.toDouble();
      final srcH = src.height.toDouble();
      const targetRatio = 4.0 / 3.0;

      double cropW = srcW;
      double cropH = srcH;
      if (srcW / srcH > targetRatio) {
        cropW = srcH * targetRatio;
      } else {
        cropH = srcW / targetRatio;
      }
      final left = (srcW - cropW) / 2.0;
      final top = (srcH - cropH) / 2.0;

      const outW = 960;
      const outH = 720;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        src,
        Rect.fromLTWH(left, top, cropW, cropH),
        const Rect.fromLTWH(0, 0, 960, 720),
        Paint()..filterQuality = FilterQuality.medium,
      );
      picture = recorder.endRecording();
      outImg = await picture.toImage(outW, outH);
      final byteData = await outImg.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final outFile = File(
          '${Directory.systemTemp.path}/proof_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await outFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
        return outFile.path;
      }
    } catch (_) {
      // Fall back to original file safely
    } finally {
      outImg?.dispose();
      picture?.dispose();
      src?.dispose();
      codec?.dispose();
    }
    return sourcePath;
  }

  Future<void> _fallbackSystemCamera() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (!mounted || f == null) return;
    final croppedPath = await _cropToFourThreeSafe(f.path);
    if (!mounted) return;
    setState(() => _capturedPath = croppedPath);
  }

  void _retake() {
    setState(() => _capturedPath = null);
    if (_controller == null && _cameras.isNotEmpty) {
      _startController(_cameras[_cameraIdx]);
    }
  }

  Future<void> _confirmUsePhoto() async {
    final path = _capturedPath;
    if (path == null) return;
    await _disposeController();
    if (mounted) {
      Navigator.of(context).pop(path);
    }
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.always:
        return Icons.flash_on_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      default:
        return Icons.flash_off_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final reviewing = _capturedPath != null;

    return PopScope(
      canPop: !reviewing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && reviewing) {
          _retake();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // Top bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (reviewing) {
                          _retake();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: Icon(
                        reviewing
                            ? Icons.arrow_back_ios_new_rounded
                            : Icons.close_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        reviewing ? 'Review Proof Photo' : 'Capture Proof Photo',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (!reviewing)
                      IconButton(
                        onPressed: _cycleFlash,
                        icon: Icon(_flashIcon, color: Colors.white, size: 24),
                        tooltip: 'Flash',
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),

              // Center 4:3 frame (either live viewfinder or captured review)
              Expanded(
                child: Center(
                  child: reviewing
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: Image.file(
                                File(_capturedPath!),
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        )
                      : _initializing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : (_error != null ||
                                  ctrl == null ||
                                  !ctrl.value.isInitialized)
                              ? Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.camera_alt_outlined,
                                          color: Colors.white54, size: 52),
                                      const SizedBox(height: 12),
                                      Text(
                                        _error ?? 'Camera unavailable',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 14),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: _fallbackSystemCamera,
                                        icon: const Icon(
                                            Icons.camera_alt_rounded),
                                        label: const Text('Open Camera'),
                                      ),
                                    ],
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: AspectRatio(
                                      aspectRatio: 4 / 3,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          FittedBox(
                                            fit: BoxFit.cover,
                                            clipBehavior: Clip.hardEdge,
                                            child: SizedBox(
                                              width: ctrl.value.previewSize
                                                      ?.height ??
                                                  4,
                                              height: ctrl.value.previewSize
                                                      ?.width ??
                                                  3,
                                              child: CameraPreview(ctrl),
                                            ),
                                          ),
                                          IgnorePointer(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.45),
                                                  width: 1.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                ),
              ),

              // Bottom controls: either Retake / Use Photo OR Shutter bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: reviewing
                    ? Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: _retake,
                                icon: const Icon(Icons.refresh_rounded,
                                    size: 20),
                                label: const Text(
                                  'Retake',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                      color: Colors.white54, width: 1.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: _confirmUsePhoto,
                                icon:
                                    const Icon(Icons.check_rounded, size: 20),
                                label: const Text(
                                  'Use Photo',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF16A34A),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          const SizedBox(width: 48),
                          GestureDetector(
                            onTap: (_capturing || _initializing)
                                ? null
                                : _capture,
                            child: Container(
                              width: 74,
                              height: 74,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 4),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _capturing
                                      ? Colors.white54
                                      : Colors.white,
                                ),
                                child: _capturing
                                    ? const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.black,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: _cameras.length > 1
                                ? IconButton(
                                    onPressed: _switchCamera,
                                    icon: const Icon(
                                        Icons.cameraswitch_rounded,
                                        color: Colors.white,
                                        size: 28),
                                    tooltip: 'Switch Camera',
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
