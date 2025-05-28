import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui; // Aliased to avoid conflict with dart:ui's Rect
import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_v2/tflite_v2.dart';
// Ensure these model and widget paths are correct for your project
import 'package:vision_ai_app/model_classes/recognized_object.dart';
import 'package:vision_ai_app/widgets/general_snackbars.dart';

class StreamCameraController extends GetxController {
  final Logger logger = Logger(printer: PrettyPrinter(methodCount: 1, lineLength: 100));
  final bool isLive; // if true, enables RTSP streaming functionality
  StreamCameraController({this.isLive = false});

  // Observables
  var isModelLoaded = false.obs;
  var isCameraInitialized = false.obs;
  var isDetecting = false.obs;
  var detectedObjects = <RecognizedObject>[].obs;
  var isStreaming = false.obs; // RTSP streaming active
  var streamHealth = 'Unknown'.obs;

  late CameraController cameraController;
  DateTime? lastInference;
  final Duration throttleDuration = const Duration(milliseconds: 300);

  // Streaming variables
  FFmpegSession? streamingSession;
  Timer? captureTimer;
  Timer? healthCheckTimer;
  Timer? tempFileCleanupTimer;
  var streamUrl = 'rtsp://<your_rtsp_server_ip>:8554/mystream'.obs; 
  final StreamController<Uint8List> _frameStreamController = StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _pipeSubscription;
  String? _ffmpegInputPipePath; // This will hold the path returned by FFmpegKitConfig.registerNewFFmpegPipe()

  GlobalKey? widgetKey;

  // Temp file management
  String? _tempFrameDir;
  int _frameCounter = 0;
  final List<String> _tempFilesToDelete = [];
  static const int maxTempFiles = 10; // Limit temp files to prevent disk space issues

  // Performance settings for streaming
  static const int targetFPS = 15;
  static const Duration frameDuration = Duration(milliseconds: 1000 ~/ targetFPS);
  static const int maxBufferSize = 2;

  var framesStreamed = 0.obs;
  DateTime? _streamStartTime;
  DateTime lastFrameTime = DateTime.now();
  var actualFPS = 0.0.obs;

  void setWidgetKey(GlobalKey key) {
    widgetKey = key;
    logger.i("WidgetKey has been set.");
  }

  @override
  void onInit() async {
    super.onInit();
    await initializeCamera();
    await loadModel();
    startHealthCheck();
    _startTempFileCleanupTimer();
  }

  @override
  void onClose() async {
    logger.i("StreamCameraController onClose called");
    healthCheckTimer?.cancel();
    tempFileCleanupTimer?.cancel();
    await stopDirectStreaming();
    await stopCamera(); // Ensure camera is stopped before _frameStreamController is closed
    await _pipeSubscription?.cancel(); // Cancel subscription before closing controller
    _pipeSubscription = null;
    await _frameStreamController.close();
    await _cleanupAllTempFiles(); // Final cleanup
    super.onClose();
  }

  Future<void> startLiveStreamingIfEnabled() async {
    logger.d("Attempting to start live streaming. isLive: $isLive, CamInit: ${isCameraInitialized.value}, widgetKeySet: ${widgetKey != null}, !isStreaming: ${!isStreaming.value}");
    if (isLive && isCameraInitialized.value && widgetKey != null && !isStreaming.value) {
      await startDirectStreaming();
    } else {
      String reason = "";
      if (!isLive) reason += "isLive is false. ";
      if (!isCameraInitialized.value) reason += "Camera not initialized. ";
      if (widgetKey == null) reason += "WidgetKey is null. ";
      if (isStreaming.value) reason += "Already streaming. ";
      if (reason.isNotEmpty) logger.w("Not starting stream: $reason");
    }
  }

  void startHealthCheck() {
    healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      checkStreamHealth();
    });
  }

  void _startTempFileCleanupTimer() {
    // Clean up temp files every 30 seconds
    tempFileCleanupTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _cleanupOldTempFiles();
    });
  }

  void checkStreamHealth() {
    if (!isStreaming.value) {
      streamHealth.value = 'Stopped';
      actualFPS.value = 0.0;
      return;
    }
    final now = DateTime.now();
    final timeDiffSinceLastCapture = now.difference(lastFrameTime).inSeconds;

    if (timeDiffSinceLastCapture > 10) {
      streamHealth.value = 'Poor (No new frames captured recently)';
    } else if (timeDiffSinceLastCapture > 5) {
      streamHealth.value = 'Fair (Frame capture delay)';
    } else {
      streamHealth.value = 'Good';
    }

    // Calculate FPS based on frames streamed to FFmpeg pipe
    if (_streamStartTime != null && framesStreamed.value > 0) {
      final durationSeconds = now.difference(_streamStartTime!).inMilliseconds / 1000.0;
      if (durationSeconds > 0) {
        // This is capture FPS, FFmpeg stats will give encoding FPS
        // actualFPS.value = framesStreamed.value / durationSeconds;
      }
    }
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
      GeneralSnackbars.showSnackBarAtTop('Model Error', 'Failed to load model: $e', 'error');
    }
  }

  Future<void> initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        logger.e('No cameras available');
        GeneralSnackbars.showSnackBarAtTop('Camera Error', 'No cameras available', 'error');
        return;
      }
      const resolution = ResolutionPreset.high; // e.g., 1280x720
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
      logger.i('Camera initialized. Preview size: ${cameraController.value.previewSize}');

      if (cameraController.value.isInitialized && !cameraController.value.isStreamingImages) {
        cameraController.startImageStream(_processFrame);
        logger.i('Camera image stream started for object detection.');
      }
    } catch (e) {
      logger.e('Camera initialization error: $e');
      GeneralSnackbars.showSnackBarAtTop('Camera Error', 'Camera init failed: $e', 'error');
      isCameraInitialized.value = false;
    }
  }

  void _processFrame(CameraImage image) {
    if (!isModelLoaded.value || isDetecting.value || !Get.isRegistered<StreamCameraController>()) return;

    final now = DateTime.now();
    if (lastInference == null || now.difference(lastInference!) >= throttleDuration) {
      lastInference = now;
      isDetecting.value = true;
      
      runModelOnFrame(image).whenComplete(() {
         if (Get.isRegistered<StreamCameraController>()) { // Ensure controller still exists
            isDetecting.value = false;
         }
      });
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
        rotation: 90, // Adjust if necessary based on camera orientation and TFLite model
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

  Future<List<RecognizedObject>> mapRecognitions(List<dynamic>? recognitions) async {
    if (recognitions == null) return [];
    return recognitions.map((recog) {
      final map = Map<String, dynamic>.from(recog);
      final rectData = Map<String, dynamic>.from(map['rect']);
      return RecognizedObject(
        rect: ui.Rect.fromLTWH( // Using ui.Rect
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

  Future<void> startDirectStreaming() async {
    if (isStreaming.value) {
      logger.w("startDirectStreaming called but already streaming.");
      return;
    }
    if (widgetKey?.currentContext == null) {
      logger.e("Cannot start streaming: widgetKey or its context is null. Widget might not be built yet.");
      GeneralSnackbars.showSnackBarAtTop('Streaming Error', 'Preview widget not ready.', 'error');
      return;
    }

    final renderBox = widgetKey!.currentContext!.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
        logger.e("RenderBox not available or has no size. Cannot determine stream dimensions.");
        GeneralSnackbars.showSnackBarAtTop('Streaming Error', 'Preview widget size not determined.', 'error');
        return;
    }
    final Size streamingDimensions = renderBox.size;

    logger.i("Attempting to start direct streaming...");
    isStreaming.value = true; // Set early to prevent re-entry
    framesStreamed.value = 0;
    _streamStartTime = DateTime.now();
    lastFrameTime = DateTime.now();

    try {
      await _setupTempFrameDirectory();
      _ffmpegInputPipePath = await _startFFmpegSessionAndGetPipe(streamingDimensions);
      if (_ffmpegInputPipePath == null) {
        throw Exception('Failed to initialize FFmpeg session or named pipe.');
      }
      await _startFrameCaptureAndPipe(_ffmpegInputPipePath!); // Pass the pipe path
      streamHealth.value = 'Starting...';
      logger.i('Successfully initiated streaming to ${streamUrl.value} via pipe: $_ffmpegInputPipePath');
    } catch (e) {
      logger.e('Streaming start failed: $e');
      GeneralSnackbars.showSnackBarAtTop('Streaming Error', 'Failed to start stream: $e', 'error');
      await _stopStreamingInternals(); // Cleanup FFmpeg and timers
      isStreaming.value = false;
      streamHealth.value = 'Failed';
    }
  }

  Future<void> _setupTempFrameDirectory() async {
    // Clean up any existing temp directory first
    await _cleanupTempFrameDirectory();
    
    // Create new temporary directory for frames
    final tempDir = await getTemporaryDirectory();
    _tempFrameDir = '${tempDir.path}/stream_frames_${DateTime.now().millisecondsSinceEpoch}';
    await Directory(_tempFrameDir!).create(recursive: true);
    _frameCounter = 0;
    _tempFilesToDelete.clear();
    logger.i("Created temp frame directory: $_tempFrameDir");
  }

  Future<String?> _startFFmpegSessionAndGetPipe(Size dimensions) async {
    int width = dimensions.width.toInt();
    int height = dimensions.height.toInt();

    // Ensure dimensions are even for YUV420p
    if (width % 2 != 0) width--; 
    if (height % 2 != 0) height--;

    if (width <= 0 || height <= 0) {
      logger.e('Invalid dimensions for FFmpeg after adjustment: ${width}x$height.');
      return null;
    }

    logger.i("Streaming with dimensions: ${width}x$height, Target FPS: $targetFPS");

    // Create a new named pipe for FFmpeg input
    final String? pipePath = await FFmpegKitConfig.registerNewFFmpegPipe();
    if (pipePath == null) {
      logger.e("Failed to register FFmpeg pipe.");
      return null;
    }
    logger.i("Registered FFmpeg input pipe at: $pipePath");

    final command = '''
      -f rawvideo -pixel_format rgba -video_size ${width}x$height -framerate $targetFPS -i pipe:$pipePath
      -vf "format=yuv420p"
      -c:v libx264 -preset ultrafast -tune zerolatency -profile:v baseline
      -level 3.1 -g ${targetFPS * 2} -keyint_min ${targetFPS * 2} -sc_threshold 0
      -b:v 1000k -maxrate 1000k -bufsize 2000k
      -pix_fmt yuv420p -rtsp_transport tcp -f rtsp ${streamUrl.value}
    '''
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    logger.d('FFmpeg command: $command');

    if (streamingSession != null) {
        logger.w("Existing FFmpeg session found, cancelling it first.");
        await FFmpegKit.cancel(streamingSession!.getSessionId());
        streamingSession = null;
    }
    
    streamingSession = await FFmpegKit.executeAsync(
      command,
      (session) async { // onCompleted
        final rc = await session.getReturnCode();
        logger.i("FFmpeg session (ID: ${session.getSessionId()}) ended. Return code: $rc");
        streamHealth.value = ReturnCode.isSuccess(rc) ? 'Finished' : 'Error ($rc)';
        if (ReturnCode.isSuccess(rc)) {
          logger.i('FFmpeg process finished successfully.');
        } else if (ReturnCode.isCancel(rc)) {
          logger.i('FFmpeg process was cancelled.');
        } else {
          logger.e('FFmpeg process failed. RC: $rc.\nOutput: ${await session.getOutput()}\nLogs: ${await session.getAllLogsAsString()}');
          if(isStreaming.value) { // If it failed unexpectedly while we thought we were streaming
            GeneralSnackbars.showSnackBarAtTop('Streaming Error', 'FFmpeg process error', 'error');
            await _stopStreamingInternals(); // Ensure cleanup
            isStreaming.value = false; // Update state
            streamHealth.value = 'Failed ($rc)';
          }
        }
        // Consider auto-restart logic here if desired and not cancelled intentionally
      },
      (log) => logger.t('[FFMPEG LOG]: ${log.getMessage()}'), // Verbose logs
      (stats) {
        if (!isStreaming.value) return;
        final newFps = stats.getVideoFps();
        if (newFps > 0) actualFPS.value = newFps;
        // You can also get stats.getBitrate(), stats.getSize() etc.
        streamHealth.value = 'Streaming (${newFps.toStringAsFixed(1)} FPS)';
      },
    );
    
    if (streamingSession == null) {
        logger.e("FFmpegKit.executeAsync failed to return a session.");
        await FFmpegKitConfig.closeFFmpegPipe(pipePath); // Clean up pipe if session failed to start
        return null;
    }
    logger.i("FFmpeg session started with ID: ${streamingSession!.getSessionId()} reading from pipe: $pipePath");
    return pipePath; // Return the path of the created pipe
  }

  Future<void> _startFrameCaptureAndPipe(String pipePathToWriteTo) async {
    await _pipeSubscription?.cancel(); // Cancel any existing subscription
    
    _pipeSubscription = _frameStreamController.stream.listen(
      (Uint8List imageBytes) async {
        if (isStreaming.value && streamingSession != null && _tempFrameDir != null) {
          try {
            // Create temporary file for this frame
            final frameFileName = 'frame_${_frameCounter.toString().padLeft(8, '0')}.raw';
            final frameFilePath = '$_tempFrameDir/$frameFileName';
            final frameFile = File(frameFilePath);
            
            // Write frame data to temporary file
            await frameFile.writeAsBytes(imageBytes);
            
            // Add to cleanup list
            _tempFilesToDelete.add(frameFilePath);
            
            // Use FFmpegKitConfig.writeToPipe to pipe the file
            final result = await FFmpegKitConfig.writeToPipe(frameFilePath, pipePathToWriteTo);
            
            _frameCounter++;
            
            if (result == null || result <= 0) {
              logger.w('writeToPipe returned unsuccessful result: $result for frame $_frameCounter');
            }
            
            // Schedule immediate cleanup of this temp file
            _scheduleFileCleanup(frameFilePath);
            
          } catch (e) {
            logger.e('Error processing frame for pipe: $e');
            if (isStreaming.value) {
              GeneralSnackbars.showSnackBarAtTop('Streaming Error', 'Frame processing error', 'error');
              stopDirectStreaming();
            }
          }
        }
      },
      onError: (e, s) {
        logger.e('Error in frame stream for piping: $e \n$s');
        if (isStreaming.value) {
          GeneralSnackbars.showSnackBarAtTop('Streaming Error', 'Frame pipe stream error', 'error');
          stopDirectStreaming();
        }
      },
      onDone: () {
        logger.i('Frame stream for piping is done');
        _cleanupAllTempFiles();
      },
      cancelOnError: false,
    );

    captureTimer?.cancel();
    int frameBuffer = 0;
    _frameCounter = 0;
    
    captureTimer = Timer.periodic(frameDuration, (_) async {
      if (!isStreaming.value || widgetKey?.currentContext == null || streamingSession == null) {
        return;
      }
      if (frameBuffer >= maxBufferSize) {
        return;
      }
      frameBuffer++;
      try {
        final imageBytes = await captureWidgetToImage(widgetKey!);
        if (imageBytes != null && isStreaming.value && !_frameStreamController.isClosed) {
          _frameStreamController.add(imageBytes);
          framesStreamed.value++;
          lastFrameTime = DateTime.now();
        }
      } catch (e) {
        logger.e('Frame capture error during timer: $e');
      } finally {
        frameBuffer--;
      }
    });
    logger.i("Frame capture and piping timer started with temp files approach. Writing to pipe: $pipePathToWriteTo");
  }

  void _scheduleFileCleanup(String filePath) {
    // Schedule cleanup after a short delay to ensure FFmpeg has processed the file
    Timer(const Duration(milliseconds: 500), () async {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          _tempFilesToDelete.remove(filePath);
        }
      } catch (e) {
        logger.w('Error deleting temp file $filePath: $e');
      }
    });
  }

  void _cleanupOldTempFiles() {
    if (_tempFilesToDelete.isEmpty) return;
    
    // Clean up files older than maxTempFiles to prevent accumulation
    if (_tempFilesToDelete.length > maxTempFiles) {
      final filesToCleanup = _tempFilesToDelete.take(_tempFilesToDelete.length - maxTempFiles).toList();
      for (final filePath in filesToCleanup) {
        File(filePath).delete().catchError((e) {
          logger.w('Error cleaning up old temp file $filePath: $e');
          return File(filePath); // Return the file to satisfy the required return type
        });
        _tempFilesToDelete.remove(filePath);
      }
      logger.d('Cleaned up ${filesToCleanup.length} old temp files');
    }
  }

  Future<void> _cleanupTempFrameDirectory() async {
    if (_tempFrameDir != null) {
      try {
        final dir = Directory(_tempFrameDir!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          logger.i("Cleaned up temp frame directory: $_tempFrameDir");
        }
      } catch (e) {
        logger.w("Error cleaning up temp frame directory: $e");
      }
      _tempFrameDir = null;
      _tempFilesToDelete.clear();
    }
  }

  Future<void> _cleanupAllTempFiles() async {
    // Clean up individual temp files first
    for (final filePath in List.from(_tempFilesToDelete)) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        logger.w('Error deleting temp file $filePath: $e');
      }
    }
    _tempFilesToDelete.clear();
    
    // Clean up the temp directory
    await _cleanupTempFrameDirectory();
    
    logger.i('All temp files and directories cleaned up');
  }

  Future<Uint8List?> captureWidgetToImage(GlobalKey key) async {
    if (key.currentContext == null) {
      logger.w("captureWidgetToImage: key.currentContext is null.");
      return null;
    }
    try {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // Ensure pixelRatio is 1.0 for predictable byte size for FFmpeg
      final image = await boundary.toImage(pixelRatio: 1.0); 
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose(); // Important to free native resources
      return byteData?.buffer.asUint8List();
    } catch (e) {
      if (e.toString().contains("disposed") || e.toString().contains("RenderRepaintBoundary object was disposed")) {
         logger.w("CaptureWidgetToImage error (likely due to dispose/navigation): $e");
      } else {
         logger.e('Image capture error: $e');
      }
      return null;
    }
  }

  Future<void> stopDirectStreaming() async {
    if (!isStreaming.value && streamingSession == null && captureTimer == null && _pipeSubscription == null) {
      logger.i("stopDirectStreaming: Not actively streaming or already effectively stopped.");
      return;
    }
    logger.i('Attempting to stop direct streaming...');
    
    // Set isStreaming to false first to stop new frames from being processed/captured
    isStreaming.value = false; 

    await _stopStreamingInternals();

    streamHealth.value = 'Stopped';
    actualFPS.value = 0.0; // Reset FFmpeg reported FPS
    logger.i('Direct streaming stopped.');
  }

  Future<void> _stopStreamingInternals() async {
    captureTimer?.cancel();
    captureTimer = null;
    logger.d("_stopStreamingInternals: Capture timer cancelled.");

    await _pipeSubscription?.cancel();
    _pipeSubscription = null;
    logger.d("_stopStreamingInternals: Pipe subscription cancelled.");
    
    if (streamingSession != null) {
      logger.i('Cancelling FFmpeg session ID: ${streamingSession!.getSessionId()}');
      await FFmpegKit.cancel(streamingSession!.getSessionId());
      streamingSession = null;
      logger.d("_stopStreamingInternals: FFmpeg session cancelled and cleared.");
    } else {
       logger.d("_stopStreamingInternals: No active FFmpeg session to cancel.");
    }

    if (_ffmpegInputPipePath != null) {
      logger.d("_stopStreamingInternals: Clearing pipe path reference: $_ffmpegInputPipePath");
      _ffmpegInputPipePath = null;
    }
    
    // Clean up all temp files and directories
    await _cleanupAllTempFiles();
  }

  Future<void> stopCamera() async {
    logger.i("Stopping camera...");
    // Check if cameraController is initialized and not null
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
      await stopDirectStreaming();
    } else {
      if (widgetKey == null || widgetKey?.currentContext == null) {
         logger.e("Toggle Streaming: Cannot start, widget (RepaintBoundary) not ready or key not set.");
         GeneralSnackbars.showSnackBarAtTop("Error", "Preview widget not ready for streaming.", "error");
         return;
      }
      await startDirectStreaming();
    }
  }

  void updateStreamUrl(String newUrl) {
    if (newUrl.isEmpty || !newUrl.startsWith('rtsp://')) {
      logger.w('Invalid RTSP URL provided: $newUrl');
      GeneralSnackbars.showSnackBarAtTop('Invalid URL', 'Please enter a valid RTSP URL (rtsp://...).', 'warning');
      return;
    }
    streamUrl.value = newUrl;
    logger.i('Stream URL updated to: $newUrl');
    if (isStreaming.value) {
      logger.i('Streaming is active, restarting with new URL...');
      // Asynchronously stop and then start.
      stopDirectStreaming().then((_) {
        // Add a small delay to ensure FFmpeg fully releases resources,
        // especially if the OS needs a moment for the pipe.
        Future.delayed(const Duration(milliseconds: 1000), () { 
          if(widgetKey != null && widgetKey?.currentContext != null && !isStreaming.value) {
             startDirectStreaming();
          } else {
            logger.e("Cannot restart streaming with new URL: Widget not ready or still streaming.");
             if(isStreaming.value) {
               GeneralSnackbars.showSnackBarAtTop("Error", "Previous stream did not stop.", "error");
             } else {
               GeneralSnackbars.showSnackBarAtTop("Error", "Preview widget became unready.", "error");
             }
          }
        });
      });
    }
  }

   Map<String, dynamic> getStreamingStats() {
    String streamingRes = 'N/A';
    if(isStreaming.value && widgetKey?.currentContext != null) {
        final ro = widgetKey!.currentContext!.findRenderObject();
        if (ro is RenderBox && ro.hasSize) {
            int w = ro.size.width.toInt();
            int h = ro.size.height.toInt();
            if (w % 2 != 0) w--; // Reflect actual ffmpeg input
            if (h % 2 != 0) h--;
            streamingRes = '${w}x$h';
        }
    }
    return {
      'isStreaming': isStreaming.value,
      'streamUrl': streamUrl.value,
      'framesSentToPipe': framesStreamed.value, // Renamed for clarity
      'ffmpegFPS': actualFPS.value.toPrecision(1), // FPS from FFmpeg stats
      'streamHealth': streamHealth.value,
      'targetCaptureFPS': targetFPS,
      'tempFilesCount': _tempFilesToDelete.length,
      'tempFrameDir': _tempFrameDir ?? 'N/A',
      'cameraResolution': isCameraInitialized.value && cameraController.value.previewSize != null 
          ? '${cameraController.value.previewSize!.width.toInt()}x${cameraController.value.previewSize!.height.toInt()}' 
          : 'N/A',
      'effectiveStreamingResolution': streamingRes,
    };
  }
}