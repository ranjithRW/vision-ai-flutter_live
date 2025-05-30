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

  // Streaming related
  static FFmpegSession? session;
  HttpServer? httpServer;
  Timer? frameTimer;
  final Set<StreamController<List<int>>> activeStreams = {};

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
      // Close any existing server
      await stopHttpServer();

      handler(shelf.Request request) {
        final controller = StreamController<List<int>>();
        activeStreams.add(controller);

        // Add connection close handler
        controller.onCancel = () {
          activeStreams.remove(controller);
          logger.i("Client disconnected from MJPEG stream");
        };

        // Stream headers with proper MJPEG format
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

        // Start frame generation
        _startFrameGeneration(controller, widgetKey);

        final response = shelf.Response.ok(controller.stream, headers: headers);
        return response;
      }

      // Start server with proper configuration
      httpServer = await shelf_io.serve(
        handler,
        // "192.168.1.4",
        "172.16.0.149",
        8081,
        poweredByHeader: null,
      );

      // Configure server settings
      httpServer!.autoCompress = false;
      httpServer!.idleTimeout = const Duration(minutes: 10); // Longer timeout

      logger.i(
          'MJPEG stream server started at http://${httpServer!.address.host}:${httpServer!.port}');
    } catch (e) {
      logger.e('Error starting HTTP stream server: $e');
      rethrow;
    }
  }

  void _startFrameGeneration(
      StreamController<List<int>> controller, GlobalKey widgetKey) {
    final frameQueue = <List<int>>[];
    bool isCapturing = false;
    bool isSending = false;

    // Timer interval for ~24 fps
    frameTimer =
        Timer.periodic(const Duration(milliseconds: 42), (timer) async {
      if (controller.isClosed || !activeStreams.contains(controller)) {
        timer.cancel();
        return;
      }

      // Start capture only if not already capturing
      if (isCapturing) return;
      isCapturing = true;

      try {
        final bytes = await captureWidgetToJPEG(widgetKey);
        if (bytes == null || controller.isClosed) {
          isCapturing = false;
          return;
        }

        final frame = <int>[];
        frame.addAll(utf8.encode('--boundarydonotcross\r\n'));
        frame.addAll(utf8.encode('Content-Type: image/jpeg\r\n'));
        frame.addAll(utf8.encode('Content-Length: ${bytes.length}\r\n\r\n'));
        frame.addAll(bytes);
        frame.addAll(utf8.encode('\r\n'));

        // Add frame to queue
        frameQueue.add(frame);

        // If queue too long, drop oldest frame to avoid memory bloat
        if (frameQueue.length > 10) {
          frameQueue.removeAt(0);
        }

        // If not already sending frames, start sending asynchronously
        if (!isSending) {
          isSending = true;
          while (frameQueue.isNotEmpty && !controller.isClosed) {
            final nextFrame = frameQueue.removeAt(0);
            controller.add(nextFrame);
            // Optional: slight delay to let the stream process frames (adjust if needed)
            await Future.delayed(const Duration(milliseconds: 1));
          }
          isSending = false;
        }
      } catch (e) {
        logger.e('Error generating frame: $e');
        if (!controller.isClosed) {
          try {
            controller.close();
          } catch (_) {}
        }
        timer.cancel();
      } finally {
        isCapturing = false;
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

      // Start HTTP MJPEG server
      await startHttpStreamServer(widgetKey!);

      // Wait a bit for server to be ready
      await Future.delayed(const Duration(milliseconds: 500));

      // Enhanced FFmpeg command for better RTSP streaming
      final command = [
        '-f', 'mjpeg',
        '-i', 'http://172.16.0.149:8081',
        '-c:v', 'libx264',
        '-preset', 'ultrafast',
        '-tune', 'zerolatency',
        '-profile:v', 'baseline',
        '-level:v', '3.0',
        '-pix_fmt', 'yuv420p',
        '-r', '24', // Set consistent frame rate
        '-g', '90', // GOP size
        '-keyint_min', '90',
        '-sc_threshold', '0',
        '-b:v', '1000k',
        '-maxrate', '1000k',
        '-bufsize', '2000k',
        '-f', 'rtsp',
        '-rtsp_transport', 'tcp',
        'rtsp://172.16.1.4:8554/mystream'
      ].join(' ');

      logger.i('Starting FFmpeg with command: $command');

      session = await FFmpegKit.executeAsync(command, (session) async {
        final returnCode = await session.getReturnCode();
        final logs = await session.getAllLogs();

        logger.i('FFmpeg session completed with return code: $returnCode');
        for (final log in logs) {
          logger.i('FFmpeg: ${log.getMessage()}');
        }

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
      // Cancel FFmpeg session
      if (session != null) {
        await session!.cancel();
        session = null;
      }

      // Stop HTTP server
      await stopHttpServer();

      logger.i("Streaming stopped successfully");
    } catch (e) {
      logger.e("Error stopping streaming: $e");
    }
  }

  Future<void> stopHttpServer() async {
    try {
      // Cancel frame timer
      frameTimer?.cancel();
      frameTimer = null;

      // Close all active stream controllers
      for (final controller in activeStreams.toList()) {
        if (!controller.isClosed) {
          try {
            await controller.close();
          } catch (e) {
            logger.w('Error closing stream controller: $e');
          }
        }
      }
      activeStreams.clear();

      // Close HTTP server
      if (httpServer != null) {
        await httpServer!.close(force: true);
        httpServer = null;
        logger.i("HTTP server stopped");
      }
    } catch (e) {
      logger.e("Error stopping HTTP server: $e");
    }
  }

  Future<Uint8List?> captureWidgetToJPEG(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        logger.w("captureWidgetToJPEG: boundary is null");
        return null;
      }

      // Capture with consistent pixel ratio
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        image.dispose();
        return null;
      }

      final pngBytes = byteData.buffer.asUint8List();
      final imgPkg = img.decodeImage(pngBytes);
      image.dispose(); // Important: dispose the image to free memory

      if (imgPkg == null) return null;

      // Ensure consistent image size and quality
      // final resizedImg = img.copyResize(imgPkg, width: 480, height: 640);
      // return Uint8List.fromList(img.encodeJpg(resizedImg, quality: 100));
      return Uint8List.fromList(img.encodeJpg(imgPkg, quality: 100));
    } catch (e) {
      logger.e('Error capturing JPEG: $e');
      return null;
    }
  }

  @override
  void onClose() async {
    logger.i("StreamCameraController onClose called");
    await stopStreaming();
    await stopCamera();
    super.onClose();
  }

  Future<void> loadModel() async {
    try {
      final String? res = await Tflite.loadModel(
        model: 'assets/models/ssd_mobilenet_external.tflite',
        labels: 'assets/labels/ssd_mobilenet.txt',
      );
      logger.i('Model loaded: $res');
      isModelLoaded.value = true;
    } catch (e) {
      logger.e('Failed to load model: $e');
      GeneralSnackbars.showSnackBarAtTop(
          'Model Error', 'Failed to load model: $e', 'error');
    }
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

      const resolution = ResolutionPreset.high;
      cameraController = CameraController(
        cameras[0],
        resolution,
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
        !Get.isRegistered<StreamCameraController>()) return;

    final now = DateTime.now();
    if (lastInference == null ||
        now.difference(lastInference!) >= throttleDuration) {
      lastInference = now;
      isDetecting.value = true;

      // runModelOnFrame(image).whenComplete(() {
      //   if (Get.isRegistered<StreamCameraController>()) {
      //     isDetecting.value = false;
      //   }
      // });
    }
  }

  Future<void> runModelOnFrame(CameraImage cameraImage) async {
    try {
      var recognitions = await Tflite.detectObjectOnFrame(
        bytesList: cameraImage.planes.map((plane) => plane.bytes).toList(),
        model: 'SSDMobileNet',
        imageHeight: cameraImage.height,
        imageWidth: cameraImage.width,
        imageMean: 127.5,
        imageStd: 127.5,
        rotation: 90,
        numResultsPerClass: 5,
        threshold: 0.4,
      );
      if (recognitions != null && Get.isRegistered<StreamCameraController>()) {
        detectedObjects.assignAll(await mapRecognitions(recognitions));
      }
    } catch (e) {
      logger.e('Inference error: $e');
    }
  }

  Future<List<RecognizedObject>> mapRecognitions(
      List<dynamic>? recognitions) async {
    if (recognitions == null) return [];
    return recognitions.map((recog) {
      final map = Map<String, dynamic>.from(recog);
      final rectData = Map<String, dynamic>.from(map['rect']);
      return RecognizedObject(
        rect: ui.Rect.fromLTWH(
          (rectData['x'] as num?)?.toDouble() ?? 0.0,
          (rectData['y'] as num?)?.toDouble() ?? 0.0,
          (rectData['w'] as num?)?.toDouble() ?? 0.0,
          (rectData['h'] as num?)?.toDouble() ?? 0.0,
        ),
        label: map['detectedClass']?.toString() ?? 'Unknown',
        confidence: (map['confidenceInClass'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
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
    } else {
      logger.w("StopCamera: Camera not initialized or already disposed.");
    }
    isCameraInitialized.value = false;
  }

  // ...existing code...
  Future<void> toggleStreaming() async {
    if (isStreaming.value) {
      await stopStreaming();
      return;
    }

    // Wait until the widget is ready
    // int retries = 0;
    // while ((widgetKey == null || widgetKey?.currentContext == null) &&
    //     retries < 10) {
    //   logger.i("Waiting for widget to be ready... retry $retries");
    //   await Future.delayed(const Duration(milliseconds: 100));
    //   retries++;
    // }

    // if (widgetKey?.currentContext == null) {
    //   logger.e(
    //       "Toggle Streaming: Preview widget (RepaintBoundary) is not ready after waiting.");
    //   GeneralSnackbars.showSnackBarAtTop(
    //     "Error",
    //     "Preview widget not ready for streaming.",
    //     "error",
    //   );
    //   return;
    // }

    await startStreaming();
  }
// ...existing code...
}
