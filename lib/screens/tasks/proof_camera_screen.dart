import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// In-app camera locked to a 4:3 capture frame so proof photos always match
/// the 4:3 verification preview automatically with zero unexpected cropping.
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
  FlashMode _flashMode = FlashMode.auto;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startController(_cameras[_cameraIdx]);
    }
  }

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      final cams = await availableCameras();
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not open camera. Please check camera permission.';
      });
    }
  }

  Future<void> _startController(CameraDescription cam) async {
    final old = _controller;
    final ctrl = CameraController(
      cam,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = ctrl;
    await old?.dispose();
    try {
      await ctrl.initialize();
      try {
        await ctrl.setFlashMode(_flashMode);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Camera access denied or unavailable.';
        });
      }
    }
  }

  Future<void> _cycleFlash() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final next = _flashMode == FlashMode.auto
        ? FlashMode.always
        : _flashMode == FlashMode.always
            ? FlashMode.off
            : FlashMode.auto;
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

  /// Captures a photo and center-frames it to exact 4:3 matching the viewfinder.
  Future<void> _capture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final raw = await ctrl.takePicture();
      final croppedPath = await _cropToFourThree(raw.path);
      if (mounted) {
        Navigator.of(context).pop(croppedPath);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to capture photo. Please try again.')),
        );
      }
    }
  }

  Future<String> _cropToFourThree(String sourcePath) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;

      final srcW = src.width.toDouble();
      final srcH = src.height.toDouble();
      const targetRatio = 4.0 / 3.0;

      // Center-crop source image to exact 4:3 matching what the user framed
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
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final outImg = await picture.toImage(outW, outH);
      final byteData = await outImg.toByteData(format: ui.ImageByteFormat.png);
      src.dispose();
      outImg.dispose();

      if (byteData != null) {
        final outFile = File(
          '${Directory.systemTemp.path}/proof_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await outFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
        return outFile.path;
      }
    } catch (_) {
      // Fallback to raw captured file if software crop fails
    }
    return sourcePath;
  }

  Future<void> _fallbackSystemCamera() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (!mounted) return;
    if (f != null) {
      final croppedPath = await _cropToFourThree(f.path);
      if (mounted) Navigator.of(context).pop(croppedPath);
    }
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.always:
        return Icons.flash_on_rounded;
      case FlashMode.off:
        return Icons.flash_off_rounded;
      default:
        return Icons.flash_auto_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const Expanded(
                    child: Text(
                      'Capture Proof Photo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _cycleFlash,
                    icon: Icon(_flashIcon, color: Colors.white, size: 24),
                    tooltip: 'Flash',
                  ),
                ],
              ),
            ),

            // 4:3 Live Viewfinder
            Expanded(
              child: Center(
                child: _initializing
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
                                      color: Colors.white70, fontSize: 14),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _fallbackSystemCamera,
                                  icon: const Icon(Icons.camera_alt_rounded),
                                  label: const Text('Open Camera'),
                                ),
                              ],
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                                        width: ctrl.value.previewSize?.height ??
                                            4,
                                        height:
                                            ctrl.value.previewSize?.width ?? 3,
                                        child: CameraPreview(ctrl),
                                      ),
                                    ),
                                    // Subtle corner frame border
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

            // Bottom shutter controls
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const SizedBox(width: 48),
                  GestureDetector(
                    onTap: _capturing ? null : _capture,
                    child: Container(
                      width: 74,
                      height: 74,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _capturing ? Colors.white54 : Colors.white,
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
                            icon: const Icon(Icons.cameraswitch_rounded,
                                color: Colors.white, size: 28),
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
    );
  }
}
