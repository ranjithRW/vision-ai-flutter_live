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

  // Streaming related - optimized for low latency
  static FFmpegSession? session;
  HttpServer? httpServer;
  Timer? frameTimer;
  final Set<StreamController<List<int>>> activeStreams = {};

  // Pre-allocated buffers for performance
  final List<int> _frameBuffer = <int>[];
  final List<int> _boundaryBytes = utf8.encode('--boundarydonotcross\r\n');
  final List<int> _contentTypeBytes =
      utf8.encode('Content-Type: image/jpeg\r\n');
  final List<int> _newlineBytes = utf8.encode('\r\n');

  // Frame cache for immediate response
  Uint8List? _cachedFrame;
  bool _frameReady = false;

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
        final controller = StreamController<List<int>>();
        activeStreams.add(controller);

        controller.onCancel = () {
          activeStreams.remove(controller);
          logger.i("Client disconnected");
        };

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
        };

        _startOptimizedFrameGeneration(controller, widgetKey);
        return shelf.Response.ok(controller.stream, headers: headers);
      }

      httpServer = await shelf_io.serve(
        handler,
        "172.16.0.149",
        8081,
        poweredByHeader: null,
      );

      httpServer!.autoCompress = false;
      httpServer!.idleTimeout = const Duration(minutes: 10);

      logger.i(
          'MJPEG server started at http://${httpServer!.address.host}:${httpServer!.port}');
    } catch (e) {
      logger.e('Error starting HTTP server: $e');
      rethrow;
    }
  }

  void _startOptimizedFrameGeneration(
      StreamController<List<int>> controller, GlobalKey widgetKey) {
    // Pre-capture first frame to avoid initial delay
    _precaptureFrame(widgetKey);

    frameTimer =
        Timer.periodic(const Duration(milliseconds: 42), (timer) async {
      if (controller.isClosed || !activeStreams.contains(controller)) {
        timer.cancel();
        return;
      }

      try {
        // Use cached frame if available, otherwise capture new one
        Uint8List? bytes;
        if (_frameReady && _cachedFrame != null) {
          bytes = _cachedFrame;
          _frameReady = false;
          // Immediately start capturing next frame
          _precaptureFrame(widgetKey);
        } else {
          bytes = await _fastCaptureWidgetToJPEG(widgetKey);
        }

        if (bytes == null || controller.isClosed) return;

        // Use pre-allocated buffer for better performance
        _frameBuffer.clear();
        _frameBuffer.addAll(_boundaryBytes);
        _frameBuffer.addAll(_contentTypeBytes);
        _frameBuffer
            .addAll(utf8.encode('Content-Length: ${bytes.length}\r\n\r\n'));
        _frameBuffer.addAll(bytes);
        _frameBuffer.addAll(_newlineBytes);

        // Send frame immediately without queuing
        controller.add(List.from(_frameBuffer));
      } catch (e) {
        logger.e('Error generating frame: $e');
        if (!controller.isClosed) {
          controller.close();
        }
        timer.cancel();
      }
    });
  }

  void _precaptureFrame(GlobalKey widgetKey) {
    // Capture frame asynchronously to have it ready for next request
    _fastCaptureWidgetToJPEG(widgetKey).then((bytes) {
      if (bytes != null) {
        _cachedFrame = bytes;
        _frameReady = true;
      }
    }).catchError((e) {
      logger.w('Precapture error: $e');
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

      // Minimal delay - just enough for server to bind
      await Future.delayed(const Duration(milliseconds: 100));

      // Optimized FFmpeg command for ultra-low latency
      final command = [
        '-f', 'mjpeg',
        '-i', 'http://172.16.0.149:8081',
        '-c:v', 'libx264',
        '-preset', 'ultrafast',
        '-tune', 'zerolatency',
        '-profile:v', 'baseline',
        '-level:v', '3.0',
        '-pix_fmt', 'yuv420p',
        '-r', '24',
        '-g', '90',
        '-keyint_min', '90',
        '-sc_threshold', '0',
        '-b:v', '1500k', // Increased bitrate for better quality
        '-maxrate', '1500k',
        '-bufsize', '1500k', // Reduced buffer size for lower latency
        '-fflags', 'nobuffer', // Disable buffering
        '-flags', 'low_delay', // Low delay flag
        '-f', 'rtsp',
        '-rtsp_transport', 'tcp',
        'rtsp://172.16.1.162:8554/mystream'
      ].join(' ');

      logger.i('Starting FFmpeg with command: $command');

      session = await FFmpegKit.executeAsync(command, (session) async {
        final returnCode = await session.getReturnCode();
        logger.i('FFmpeg session completed with return code: $returnCode');

        if (Get.isRegistered<StreamCameraController>()) {
          isStreaming.value = false;
          await stopHttpServer();
        }
      });

      logger.i("RTSP streaming started successfully");
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

      // Clear cache
      _cachedFrame = null;
      _frameReady = false;
    } catch (e) {
      logger.e("Error stopping HTTP server: $e");
    }
  }

  Future<Uint8List?> _fastCaptureWidgetToJPEG(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData == null) {
        image.dispose();
        return null;
      }

      final bytes = byteData.buffer.asUint8List();
      image.dispose();

      // Direct RGBA to JPEG conversion without PNG intermediate step
      final imgPkg = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: bytes.buffer,
        format: img.Format.uint8,
        numChannels: 4,
      );

      if (imgPkg == null) return null;

      // Direct JPEG encoding with optimized quality
      return Uint8List.fromList(img.encodeJpg(imgPkg, quality: 85));
    } catch (e) {
      logger.e('Error capturing JPEG: $e');
      return null;
    }
  }

  // Keep original method as fallback
  Future<Uint8List?> captureWidgetToJPEG(GlobalKey key) async {
    return _fastCaptureWidgetToJPEG(key);
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
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await cameraController.initialize();
      await cameraController.setFocusMode(FocusMode.auto);
      await cameraController.setExposureMode(ExposureMode.auto);
      isCameraInitialized.value = true;

      logger.i(
          'Camera initialized. Preview size: ${cameraController.value.previewSize}');

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
