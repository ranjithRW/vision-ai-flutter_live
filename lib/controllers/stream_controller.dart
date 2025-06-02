import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'package:tflite_v2/tflite_v2.dart';
import 'package:vision_ai_app/model_classes/recognized_object.dart';
import 'package:vision_ai_app/widgets/general_snackbars.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:image/image.dart' as img;

class StreamCameraController extends GetxController {
  final Logger logger =
      Logger(printer: PrettyPrinter(methodCount: 1, lineLength: 100));
  final bool isLive;
  StreamCameraController({this.isLive = false});

  // Observables
  var isModelLoaded = false.obs;
  var isCameraInitialized = false.obs;
  var isDetecting = false.obs;
  var detectedObjects = <RecognizedObject>[].obs;
  var isStreaming = false.obs;

  late CameraController cameraController;
  DateTime? lastInference;
  final Duration throttleDuration = const Duration(milliseconds: 300);

  GlobalKey? widgetKey;

  // Streaming related - ultra-low latency optimizations
  static FFmpegSession? session;
  HttpServer? httpServer;
  Timer? frameTimer;
  final Set<StreamController<List<int>>> activeStreams = {};

  // Optimized frame management
  final List<int> _frameBuffer = <int>[];
  final List<int> _boundaryBytes = utf8.encode('--boundarydonotcross\r\n');
  final List<int> _contentTypeBytes =
      utf8.encode('Content-Type: image/jpeg\r\n');
  final List<int> _newlineBytes = utf8.encode('\r\n');

  // Dual buffer system for zero-copy streaming
  Uint8List? _frontBuffer;
  Uint8List? _backBuffer;
  bool _frontBufferReady = false;
  bool _isCapturing = false;

  // Frame rate control
  static const int targetFPS = 30;
  static const int frameIntervalMs = 1000 ~/ targetFPS; // ~33ms for 30fps

  // Quality control
  static const int jpegQuality = 80; // Reduced for lower latency
  static const double pixelRatio = 0.8; // Slight reduction for performance

  void setWidgetKey(GlobalKey key) {
    widgetKey = key;
    logger.i("WidgetKey has been set.");
  }

  @override
  void onInit() async {
    super.onInit();
    await initializeCamera();
    // await loadModel();
  }

  Future<void> startHttpStreamServer(GlobalKey widgetKey) async {
    try {
      await stopHttpServer();

      handler(shelf.Request request) {
        late StreamController<List<int>> controller;
        controller = StreamController<List<int>>(
          // Optimize buffer size for immediate delivery
          onListen: () => logger.i("Client connected"),
          onCancel: () {
            activeStreams.remove(controller);
            logger.i("Client disconnected");
          },
        );

        activeStreams.add(controller);

        final headers = {
          HttpHeaders.contentTypeHeader:
              'multipart/x-mixed-replace; boundary=--boundarydonotcross',
          HttpHeaders.cacheControlHeader: 'no-cache, no-store, must-revalidate',
          HttpHeaders.pragmaHeader: 'no-cache',
          HttpHeaders.expiresHeader: '0',
          HttpHeaders.connectionHeader: 'keep-alive',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
          // Additional headers for lower latency
          'X-Accel-Buffering': 'no',
          'Cache-Control': 'no-cache, no-store, max-age=0',
        };

        _startUltraLowLatencyFrameGeneration(controller, widgetKey);
        return shelf.Response.ok(controller.stream, headers: headers);
      }

      httpServer = await shelf_io.serve(
        handler,
        "172.16.0.149",
        8081,
        poweredByHeader: null,
      );

      // Optimize server settings for streaming
      httpServer!.autoCompress = false;
      httpServer!.idleTimeout = const Duration(hours: 24);

      logger.i(
          'Ultra-low latency MJPEG server started at http://${httpServer!.address.host}:${httpServer!.port}');
    } catch (e) {
      logger.e('Error starting HTTP server: $e');
      rethrow;
    }
  }

  void _startUltraLowLatencyFrameGeneration(
      StreamController<List<int>> controller, GlobalKey widgetKey) {
    // Start background frame capture immediately
    _startBackgroundFrameCapture(widgetKey);

    frameTimer =
        Timer.periodic(Duration(milliseconds: frameIntervalMs), (timer) async {
      if (controller.isClosed || !activeStreams.contains(controller)) {
        timer.cancel();
        return;
      }

      try {
        Uint8List? bytes;

        // Use front buffer if ready, otherwise skip frame to maintain timing
        if (_frontBufferReady && _frontBuffer != null) {
          bytes = _frontBuffer;
          _frontBufferReady = false;

          // Swap buffers
          final temp = _frontBuffer;
          _frontBuffer = _backBuffer;
          _backBuffer = temp;
        } else {
          // Skip frame rather than blocking - maintains smooth timing
          return;
        }

        if (bytes == null || controller.isClosed) return;

        // Optimized frame construction
        _frameBuffer.clear();
        _frameBuffer.addAll(_boundaryBytes);
        _frameBuffer.addAll(_contentTypeBytes);
        _frameBuffer
            .addAll(utf8.encode('Content-Length: ${bytes.length}\r\n\r\n'));
        _frameBuffer.addAll(bytes);
        _frameBuffer.addAll(_newlineBytes);

        // Immediate delivery without buffering
        if (!controller.isClosed) {
          controller.add(List.from(_frameBuffer));
        }
      } catch (e) {
        logger.e('Error generating frame: $e');
        if (!controller.isClosed) {
          controller.close();
        }
        timer.cancel();
      }
    });
  }

  void _startBackgroundFrameCapture(GlobalKey widgetKey) {
    // Continuous background capture for zero-latency frame delivery
    Timer.periodic(Duration(milliseconds: frameIntervalMs - 5), (timer) async {
      if (!isStreaming.value || _isCapturing) {
        if (!isStreaming.value) timer.cancel();
        return;
      }

      _isCapturing = true;
      try {
        final bytes = await _ultraFastCaptureWidgetToJPEG(widgetKey);
        if (bytes != null && !_frontBufferReady) {
          _backBuffer = bytes;
          // Atomic swap
          if (!_frontBufferReady) {
            final temp = _frontBuffer;
            _frontBuffer = _backBuffer;
            _backBuffer = temp;
            _frontBufferReady = true;
          }
        }
      } catch (e) {
        logger.w('Background capture error: $e');
      } finally {
        _isCapturing = false;
      }
    });
  }

  Future<void> startStreaming() async {
    if (isStreaming.value) {
      logger.w("Streaming already active");
      return;
    }

    try {
      isStreaming.value = true;

      // Start HTTP server first
      await startHttpStreamServer(widgetKey!);

      // Minimal delay for server binding
      await Future.delayed(const Duration(milliseconds: 50));

      // Ultra-optimized FFmpeg command for minimal latency
      final command = [
        '-f', 'mjpeg',
        '-i', 'http://172.16.0.149:8081',
        '-c:v', 'libx264',
        '-preset', 'ultrafast',
        '-tune', 'zerolatency',
        '-profile:v', 'baseline',
        '-level:v', '3.1',
        '-pix_fmt', 'yuv420p',
        '-r', '$targetFPS',
        '-g', '60', // Reduced GOP size for lower latency
        '-keyint_min', '60',
        '-sc_threshold', '0',
        '-b:v', '2000k', // Optimized bitrate
        '-maxrate', '2500k',
        '-bufsize', '500k', // Very small buffer for ultra-low latency
        '-fflags', '+nobuffer+flush_packets',
        '-flags', '+low_delay+global_header',
        '-avioflags', 'direct',
        '-flush_packets', '1',
        '-max_delay', '0',
        '-f', 'rtsp',
        '-rtsp_transport', 'tcp',
        '-rtsp_flags', '+prefer_tcp',
        'rtsp://172.16.1.162:8554/mystream'
      ].join(' ');

      logger.i('Starting ultra-low latency FFmpeg with command: $command');

      session = await FFmpegKit.executeAsync(command, (session) async {
        final returnCode = await session.getReturnCode();
        logger.i('FFmpeg session completed with return code: $returnCode');

        if (Get.isRegistered<StreamCameraController>()) {
          isStreaming.value = false;
          await stopHttpServer();
        }
      });

      logger.i("Ultra-low latency RTSP streaming started successfully");
    } catch (e) {
      logger.e('Error starting streaming: $e');
      isStreaming.value = false;
      await stopHttpServer();
      GeneralSnackbars.showSnackBarAtTop(
          'Streaming Error', 'Failed to start streaming: $e', 'error');
    }
  }

  Future<void> stopStreaming() async {
    logger.i("Stopping streaming...");
    isStreaming.value = false;

    try {
      if (session != null) {
        await session!.cancel();
        session = null;
      }
      await stopHttpServer();
      logger.i("Streaming stopped successfully");
    } catch (e) {
      logger.e("Error stopping streaming: $e");
    }
  }

  Future<void> stopHttpServer() async {
    try {
      frameTimer?.cancel();
      frameTimer = null;

      // Quick cleanup of streams
      final streamsCopy = List.from(activeStreams);
      activeStreams.clear();

      for (final controller in streamsCopy) {
        if (!controller.isClosed) {
          controller.close();
        }
      }

      if (httpServer != null) {
        await httpServer!.close(force: true);
        httpServer = null;
        logger.i("HTTP server stopped");
      }

      // Clear buffers
      _frontBuffer = null;
      _backBuffer = null;
      _frontBufferReady = false;
      _isCapturing = false;
    } catch (e) {
      logger.e("Error stopping HTTP server: $e");
    }
  }

  Future<Uint8List?> _ultraFastCaptureWidgetToJPEG(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      // Use reduced pixel ratio for better performance
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData == null) {
        image.dispose();
        return null;
      }

      final bytes = byteData.buffer.asUint8List();
      image.dispose();

      // Optimized image processing
      final imgPkg = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: bytes.buffer,
        format: img.Format.uint8,
        numChannels: 4,
      );

      if (imgPkg == null) return null;

      // Fast JPEG encoding with optimized settings
      return Uint8List.fromList(img.encodeJpg(
        imgPkg,
        quality: jpegQuality,
        chroma: img.JpegChroma.yuv420, // More efficient chroma subsampling
      ));
    } catch (e) {
      logger.e('Error in ultra-fast capture: $e');
      return null;
    }
  }

  // Keep original method as fallback
  Future<Uint8List?> captureWidgetToJPEG(GlobalKey key) async {
    return _ultraFastCaptureWidgetToJPEG(key);
  }

  @override
  void onClose() async {
    logger.i("StreamCameraController onClose called");
    await stopStreaming();
    await stopCamera();
    super.onClose();
  }

  Future<void> initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        logger.e('No cameras available');
        GeneralSnackbars.showSnackBarAtTop(
            'Camera Error', 'No cameras available', 'error');
        return;
      }

      cameraController = CameraController(
        cameras[0],
        ResolutionPreset.medium, // Reduced for better performance
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await cameraController.initialize();
      await cameraController
          .setFocusMode(FocusMode.locked); // Avoid focus hunting
      await cameraController
          .setExposureMode(ExposureMode.locked); // Stable exposure

      // Set optimal FPS if supported
      try {
        await cameraController.setExposureOffset(0.0);
      } catch (e) {
        logger.w('Could not set exposure offset: $e');
      }

      isCameraInitialized.value = true;

      logger.i(
          'Camera initialized with optimized settings. Preview size: ${cameraController.value.previewSize}');

      if (cameraController.value.isInitialized &&
          !cameraController.value.isStreamingImages) {
        cameraController.startImageStream(_processFrame);
        logger.i('Camera image stream started for object detection.');
      }
    } catch (e) {
      logger.e('Camera initialization error: $e');
      GeneralSnackbars.showSnackBarAtTop(
          'Camera Error', 'Camera init failed: $e', 'error');
      isCameraInitialized.value = false;
    }
  }

  void _processFrame(CameraImage image) {
    if (!isModelLoaded.value ||
        isDetecting.value ||
        !Get.isRegistered<StreamCameraController>()) {
      return;
    }

    final now = DateTime.now();
    if (lastInference == null ||
        now.difference(lastInference!) >= throttleDuration) {
      lastInference = now;
      isDetecting.value = true;
    }
  }

  Future<void> stopCamera() async {
    logger.i("Stopping camera...");
    if (cameraController.value.isInitialized) {
      if (cameraController.value.isStreamingImages) {
        try {
          await cameraController.stopImageStream();
          logger.i("Camera image stream stopped.");
        } catch (e) {
          logger.e("Error stopping image stream: $e");
        }
      }
      try {
        await cameraController.dispose();
        logger.i("Camera controller disposed.");
      } catch (e) {
        logger.e("Error disposing camera controller: $e");
      }
    }
    isCameraInitialized.value = false;
  }

  Future<void> toggleStreaming() async {
    if (isStreaming.value) {
      await stopStreaming();
      return;
    }

    if (widgetKey?.currentContext == null) {
      logger.e("Toggle Streaming: Preview widget not ready.");
      GeneralSnackbars.showSnackBarAtTop(
        "Error",
        "Preview widget not ready for streaming.",
        "error",
      );
      return;
    }

    await startStreaming();
  }
}
