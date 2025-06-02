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
 
  // Camera frame buffer for streaming
  CameraImage? latestCameraFrame;
  bool isProcessingFrame = false;
 
  void setWidgetKey(GlobalKey key) {
    widgetKey = key;
    logger.i("WidgetKey has been set.");
  }
 
  @override
  void onInit() async {
    super.onInit();
    await initializeCamera();
  }
 
  Future<void> startHttpStreamServer() async {
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
 
        // Start frame generation from latest camera frame
        _startFrameStreaming(controller);
 
        final response = shelf.Response.ok(controller.stream, headers: headers);
        return response;
      }
 
      // Start server with proper configuration
      httpServer = await shelf_io.serve(
        handler,
        "172.16.0.149",
        8081,
        poweredByHeader: null,
      );
 
      // Configure server settings
      httpServer!.autoCompress = false;
      httpServer!.idleTimeout = const Duration(minutes: 10);
 
      logger.i(
          'MJPEG stream server started at http://${httpServer!.address.host}:${httpServer!.port}');
    } catch (e) {
      logger.e('Error starting HTTP stream server: $e');
      rethrow;
    }
  }
 
  void _startFrameStreaming(StreamController<List<int>> controller) {
    final frameQueue = <List<int>>[];
    bool isCapturing = false;
    bool isSending = false;
 
    // Timer to capture frames at ~30 fps
    frameTimer =
        Timer.periodic(const Duration(milliseconds: 33), (timer) async {   //checkkkk?
      if (controller.isClosed || !activeStreams.contains(controller)) {
        timer.cancel();
        return;
      }
 
      // Check if we have a fresh camera frame
      if (latestCameraFrame == null || isCapturing) return;
 
      isCapturing = true;
 
      try {
        // Convert the latest camera frame to JPEG
        final jpegBytes = await convertCameraImageToJPEG(latestCameraFrame!);
        if (jpegBytes == null || controller.isClosed) {
          isCapturing = false;
          return;
        }
 
        logger.i('Converted camera frame to JPEG: ${jpegBytes.length} bytes');
 
        // Create MJPEG frame
        final frame = <int>[];
        frame.addAll(utf8.encode('--boundarydonotcross\r\n'));
        frame.addAll(utf8.encode('Content-Type: image/jpeg\r\n'));
        frame.addAll(utf8.encode('Content-Length: ${jpegBytes.length}\r\n\r\n'));
        frame.addAll(jpegBytes);
        frame.addAll(utf8.encode('\r\n'));
 
        // Add frame to queue
        frameQueue.add(frame);
 
        // Keep queue size manageable
        if (frameQueue.length > 3) {
          frameQueue.removeAt(0);
        }
 
        // Send frames asynchronously
        if (!isSending && frameQueue.isNotEmpty) {
          isSending = true;
          while (frameQueue.isNotEmpty && !controller.isClosed) {
            final nextFrame = frameQueue.removeAt(0);
            controller.add(nextFrame);
            // Small delay to prevent overwhelming the stream
            await Future.delayed(const Duration(milliseconds: 1));
          }
          isSending = false;
        }
      } catch (e) {
        logger.e('Error processing camera frame for streaming: $e');
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
 
  Future<Uint8List?> convertCameraImageToJPEG(CameraImage cameraImage) async {
    try {
      // Convert CameraImage to Image package format
      img.Image? image;
 
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        // Handle YUV420 format
        image = _convertYUV420ToImage(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        // Handle BGRA8888 format
        image = _convertBGRA8888ToImage(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.nv21) {
        // Handle NV21 format
        image = _convertNV21ToImage(cameraImage);
      } else {
        logger.w('Unsupported image format: ${cameraImage.format.group}');
        return null;
      }
 
      if (image == null) {
        logger.w('Failed to convert camera image');
        return null;
      }
 
      // Encode to JPEG with good quality
      final jpegBytes = img.encodeJpg(image, quality: 85);
      return Uint8List.fromList(jpegBytes);
    } catch (e) {
      logger.e('Error converting camera image to JPEG: $e');
      return null;
    }
  }
 
  img.Image? _convertYUV420ToImage(CameraImage cameraImage) {
    try {
      final int width = cameraImage.width;
      final int height = cameraImage.height;
 
      final Uint8List yPlane = cameraImage.planes[0].bytes;
      final Uint8List uPlane = cameraImage.planes[1].bytes;
      final Uint8List vPlane = cameraImage.planes[2].bytes;
 
      final img.Image image = img.Image(width: width, height: height);
 
      final int uvRowStride = cameraImage.planes[1].bytesPerRow;
      final int uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;
 
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * width + x;
          final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
 
          final int yValue = yPlane[yIndex];
          final int uValue = uPlane[uvIndex];
          final int vValue = vPlane[uvIndex];
 
          // YUV to RGB conversion
          final int r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
          final int g =
              (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
                  .round()
                  .clamp(0, 255);
          final int b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);
 
          image.setPixelRgb(x, y, r, g, b);
        }
      }
 
      return image;
    } catch (e) {
      logger.e('Error converting YUV420 to Image: $e');
      return null;
    }
  }
 
  img.Image? _convertBGRA8888ToImage(CameraImage cameraImage) {
    try {
      final int width = cameraImage.width;
      final int height = cameraImage.height;
      final Uint8List bytes = cameraImage.planes[0].bytes;
 
      final img.Image image = img.Image(width: width, height: height);
 
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int pixelIndex = (y * width + x) * 4;
          final int b = bytes[pixelIndex];
          final int g = bytes[pixelIndex + 1];
          final int r = bytes[pixelIndex + 2];
          final int a = bytes[pixelIndex + 3];
 
          image.setPixelRgba(x, y, r, g, b, a);
        }
      }
 
      return image;
    } catch (e) {
      logger.e('Error converting BGRA8888 to Image: $e');
      return null;
    }
  }
 
  img.Image? _convertNV21ToImage(CameraImage cameraImage) {
    try {
      final int width = cameraImage.width;
      final int height = cameraImage.height;
 
      final Uint8List yPlane = cameraImage.planes[0].bytes;
      final Uint8List uvPlane = cameraImage.planes[1].bytes;
 
      final img.Image image = img.Image(width: width, height: height);
 
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * width + x;
          final int uvIndex = (y ~/ 2) * width + (x ~/ 2) * 2;
 
          final int yValue = yPlane[yIndex];
          final int vValue = uvPlane[uvIndex];
          final int uValue = uvPlane[uvIndex + 1];
 
          // YUV to RGB conversion
          final int r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
          final int g =
              (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
                  .round()
                  .clamp(0, 255);
          final int b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);
 
          image.setPixelRgb(x, y, r, g, b);
        }
      }
 
      return image;
    } catch (e) {
      logger.e('Error converting NV21 to Image: $e');
      return null;
    }
  }
 
  Future<void> startStreaming() async {
    if (isStreaming.value) {
      logger.w("Streaming already active");
      return;
    }
 
    if (!isCameraInitialized.value) {
      logger.e("Camera not initialized");
      GeneralSnackbars.showSnackBarAtTop(
        "Error",
        "Camera not initialized",
        "error",
      );
      return;
    }
 
    try {
      isStreaming.value = true;
 
      // Start HTTP MJPEG server
      await startHttpStreamServer();
 
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
        '-r', '30', // Increased frame rate
        '-g', '90',
        '-keyint_min', '90',
        '-sc_threshold', '0',
        '-b:v', '1500k', // Increased bitrate for better quality
        '-maxrate', '1500k',
        '-bufsize', '3000k',
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
 
      const resolution = ResolutionPreset.high;
      cameraController = CameraController(
        cameras[0],
        resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888, // Use consistent format
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
        logger.i('Camera image stream started.');
      }
    } catch (e) {
      logger.e('Camera initialization error: $e');
      GeneralSnackbars.showSnackBarAtTop(
          'Camera Error', 'Camera init failed: $e', 'error');
      isCameraInitialized.value = false;
    }
  }
 
  void _processFrame(CameraImage image) {
    if (!Get.isRegistered<StreamCameraController>()) return;
 
    // Store the latest camera frame for streaming
    if (!isProcessingFrame) {
      latestCameraFrame = image;
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
    } else {
      logger.w("StopCamera: Camera not initialized or already disposed.");
    }
    isCameraInitialized.value = false;
  }
 
  Future<void> toggleStreaming() async {
    if (isStreaming.value) {
      await stopStreaming();
      return;
    }
 
    if (!isCameraInitialized.value) {
      logger.e("Toggle Streaming: Camera not initialized.");
      GeneralSnackbars.showSnackBarAtTop(
        "Error",
        "Camera not initialized for streaming.",
        "error",
      );
      return;
    }
 
    await startStreaming();
  }
}