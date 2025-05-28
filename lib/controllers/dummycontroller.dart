import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:logger/logger.dart';
import 'package:tflite_v2/tflite_v2.dart';
import 'package:vision_ai_app/model_classes/recognized_object.dart';
import 'package:vision_ai_app/screens/result_image_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vision_ai_app/widgets/general_snackbars.dart';

class ObjectDetectionControllerTFLiteV2 extends GetxController {
  final Logger logger = Logger();
  final bool isLive;
  ObjectDetectionControllerTFLiteV2({this.isLive = false});

  // Observables
  var isModelLoaded = false.obs;
  var isCameraInitialized = false.obs;
  var isDetecting = false.obs;
  var detectedObjects = <RecognizedObject>[].obs;

  var selectedImagePath = ''.obs;
  var imageAspectRatio = (3 / 4).obs;
  var isLoadingImage = false.obs;

  late Interpreter interpreter;
  late List<String> labels;
  late CameraController cameraController;

  static const int inputSize = 300;
  static const double threshold = 0.4;

  DateTime? lastInference;
  final Duration throttleDuration = const Duration(milliseconds: 300); // Increased throttle

  var isEnabled = true.obs;

  // Improved confidence tracking
  final Map<String, List<double>> _confidenceHistory = {};
  static const int _historySize = 5;

  @override
  void onInit() async {
    super.onInit();
    await initializeCamera();
    await loadModel();
  }

  @override
  void onClose() async {
    await stopCamera();
    interpreter.close();
    super.onClose();
  }

  Future<void> loadModel() async {
    try {
      String? res = await Tflite.loadModel(
          model: 'assets/models/ssd_mobilenet_external.tflite',
          labels: 'assets/labels/ssd_mobilenet.txt',
          isAsset: true);
      logger.i('Model loaded: $res');
      isModelLoaded.value = true;
    } catch (e) {
      logger.e('Failed to load model: $e');
      GeneralSnackbars.showSnackBarAtTop(
          'Detection Failed', 'Failed to load model: $e', 'error');
    }
  }

  Future<void> initializeCamera() async {
    try {
      logger.i('Initializing camera...');
      final cameras = await availableCameras();
      
      // Use higher resolution for better quality
      cameraController = CameraController(
        cameras[0], 
        ResolutionPreset.high, // Changed from medium to high
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // Consistent format
      );
      
      await cameraController.initialize();
      
      // Set camera settings for consistency
      await cameraController.setFocusMode(FocusMode.auto);
      await cameraController.setExposureMode(ExposureMode.auto);
      
      isCameraInitialized.value = true;

      if (isLive) {
        logger.i('Start Streaming images from camera');
        cameraController.startImageStream((CameraImage image) {
          if (!isDetecting.value && isModelLoaded.value) {
            isDetecting.value = true;
            runModelOnFrame(image).then((_) {
              isDetecting.value = false;
            });
          }
        });
      }
    } catch (e) {
      logger.e('Camera initialization error: $e');
      GeneralSnackbars.showSnackBarAtTop(
          'Sorry for the trouble', '$e', 'error');
    }
  }

  Future<void> stopCamera() async {
    if (cameraController.value.isStreamingImages) {
      await cameraController.stopImageStream();
    }
    await cameraController.dispose();
    isCameraInitialized.value = false;
  }

  /// Improved frame processing with temporal smoothing
  Future<void> runModelOnFrame(CameraImage cameraImage) async {
    if (!isModelLoaded.value) return;

    final now = DateTime.now();
    if (lastInference != null &&
        now.difference(lastInference!) < throttleDuration) {
      return;
    }
    lastInference = now;

    try {
      // Improved parameters for better consistency
      var recognitions = await Tflite.detectObjectOnFrame(
          bytesList: cameraImage.planes.map((plane) => plane.bytes).toList(),
          model: 'SSDMobileNet',
          imageHeight: cameraImage.height,
          imageWidth: cameraImage.width,
          imageMean: 127.5,
          imageStd: 127.5,
          rotation: 90,
          numResultsPerClass: 10, // Increased from 5
          threshold: 0.3, // Increased from 0.1 for more stable detections
          asynch: true
      );

      // Apply temporal smoothing
      final smoothedObjects = await _applySmoothingFilter(
        await mapRecognitions(recognitions)
      );
      
      detectedObjects.assignAll(smoothedObjects);
      
    } catch (e) {
      logger.e('Error during inference: $e');
      GeneralSnackbars.showSnackBarAtTop(
          'Detection Failed', 'Failed to run object detection: $e', 'error');
    } finally {
      isDetecting.value = false;
    }
  }

  /// Apply temporal smoothing to reduce flickering
  Future<List<RecognizedObject>> _applySmoothingFilter(
      List<RecognizedObject> currentObjects) async {
    
    List<RecognizedObject> smoothedObjects = [];
    
    for (var obj in currentObjects) {
      String key = '${obj.label}_${obj.rect.center.dx.round()}_${obj.rect.center.dy.round()}';
      
      // Maintain confidence history
      if (!_confidenceHistory.containsKey(key)) {
        _confidenceHistory[key] = [];
      }
      
      _confidenceHistory[key]!.add(obj.confidence);
      
      // Keep only recent history
      if (_confidenceHistory[key]!.length > _historySize) {
        _confidenceHistory[key]!.removeAt(0);
      }
      
      // Calculate smoothed confidence
      double avgConfidence = _confidenceHistory[key]!
          .reduce((a, b) => a + b) / _confidenceHistory[key]!.length;
      
      // Only include if average confidence is above threshold
      if (avgConfidence >= 0.4) {
        smoothedObjects.add(RecognizedObject(
          rect: obj.rect,
          label: obj.label,
          confidence: avgConfidence,
        ));
      }
    }
    
    // Clean up old entries
    _cleanupConfidenceHistory();
    
    return smoothedObjects;
  }

  void _cleanupConfidenceHistory() {
    // Remove entries that haven't been updated recently
    final keysToRemove = <String>[];
    _confidenceHistory.forEach((key, values) {
      if (values.isEmpty) {
        keysToRemove.add(key);
      }
    });
    
    for (String key in keysToRemove) {
      _confidenceHistory.remove(key);
    }
  }

  Future<void> runObjectDetectionOnSelectedImage() async {
    logger.i('Running model on selected image');
    isEnabled.value = false;
    
    if (!isModelLoaded.value) {
      logger.e('Model not loaded');
      GeneralSnackbars.showSnackBarAtTop(
          'Detection Failed', "Failed to load model", 'error');
      isEnabled.value = true;
      return;
    }

    try {
      isDetecting.value = true;
      logger.i('Running model on selected image: ${selectedImagePath.value}');
      
      // Use same threshold as camera for consistency
      var recognitions = await Tflite.detectObjectOnImage(
          path: selectedImagePath.value,
          model: 'SSDMobileNet',
          imageMean: 127.5,
          imageStd: 127.5,
          numResultsPerClass: 10, // Increased for consistency
          threshold: 0.3, // Match camera threshold
          asynch: true
      );
      
      logger.i('Inference completed');
      detectedObjects.assignAll(await mapRecognitions(recognitions));
      
      if (detectedObjects.isEmpty) {
        GeneralSnackbars.showSnackBarAtTop('No Objects Detected',
            'No objects were detected in the image', 'info');
      } else {
        await Get.to(ResultImageScreen());
      }
    } catch (e) {
      logger.e('Error during inference: $e');
      GeneralSnackbars.showSnackBarAtTop(
          'Detection Failed', 'Failed to run object detection: $e', 'error');
    } finally {
      isDetecting.value = false;
      isEnabled.value = true;
    }
  }

  /// Improved recognition mapping with filtering
  Future<List<RecognizedObject>> mapRecognitions(
      List<dynamic>? recognitions) async {
    
    if (recognitions == null) {
      logger.i('No recognitions found');
      return [];
    }
    
    List<RecognizedObject> objects = [];
    
    for (var recognition in recognitions) {
      try {
        final map = Map<String, dynamic>.from(recognition as Map);
        final rectData = Map<String, dynamic>.from(map['rect'] as Map);
        final confidence = map['confidenceInClass'] as double;
        
        // Apply minimum confidence filter
        if (confidence < 0.3) continue;
        
        final rect = Rect.fromLTWH(
          rectData['x'] as double,
          rectData['y'] as double,
          rectData['w'] as double,
          rectData['h'] as double,
        );
        
        // Filter out very small or very large bounding boxes
        final area = rect.width * rect.height;
        if (area < 100 || area > 300000) continue;
        
        objects.add(RecognizedObject(
          rect: rect,
          label: map['detectedClass'] as String,
          confidence: confidence,
        ));
      } catch (e) {
        logger.w('Error parsing recognition: $e');
        continue;
      }
    }
    
    // Sort by confidence
    objects.sort((a, b) => b.confidence.compareTo(a.confidence));
    
    return objects;
  }

  // Method to capture high-quality frame from camera for detection
  Future<void> captureAndDetect() async {
    if (!isCameraInitialized.value || !isModelLoaded.value) return;
    
    try {
      isDetecting.value = true;
      
      // Capture high-quality image
      final XFile imageFile = await cameraController.takePicture();
      
      // Run detection on captured image (same as still image processing)
      var recognitions = await Tflite.detectObjectOnImage(
          path: imageFile.path,
          model: 'SSDMobileNet',
          imageMean: 127.5,
          imageStd: 127.5,
          numResultsPerClass: 10,
          threshold: 0.3,
          asynch: true
      );
      
      detectedObjects.assignAll(await mapRecognitions(recognitions));
      
      // Clean up temporary file
      await File(imageFile.path).delete();
      
    } catch (e) {
      logger.e('Error during capture and detect: $e');
    } finally {
      isDetecting.value = false;
    }
  }

  // Rest of your existing methods remain the same...
  Future<void> pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      isLoadingImage.value = true;
      final image = await picker.pickImage(source: source);

      if (image != null) {
        selectedImagePath.value = image.path;
        await _calculateImageAspectRatio(image.path);
      }
    } catch (e) {
      GeneralSnackbars.showSnackBarAtBottom(
          '', 'Failed to pick image: $e', 'error');
      logger.e('Failed to pick image: $e');
    } finally {
      isLoadingImage.value = false;
    }
  }

  Future<void> _calculateImageAspectRatio(String imagePath) async {
    try {
      final Uint8List imageBytes = await XFile(imagePath).readAsBytes();
      final codec = await instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      imageAspectRatio.value = image.width / image.height;
      image.dispose();
    } catch (e) {
      imageAspectRatio.value = 3 / 4;
    }
  }

  void clearImage() {
    selectedImagePath.value = '';
    imageAspectRatio.value = 3 / 4;
    detectedObjects.value = [];
    _confidenceHistory.clear(); // Clear smoothing history
  }

  Future<Size> getImageSizeFromFile(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  Future<Uint8List?> captureWidgetToImage(GlobalKey key) async {
    RenderRepaintBoundary? boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> saveToDownloads(Uint8List imageBytes) async {
    Directory? downloadsDirectory;

    if (Platform.isAndroid) {
      downloadsDirectory = Directory('/storage/emulated/0/Download');
    } else if (Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isWindows) {
      downloadsDirectory = await getDownloadsDirectory();
    }
    
    final filePath =
        '${downloadsDirectory!.path}/detected_image_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);
    logger.i("Image saved to Downloads: ${file.path}");
    GeneralSnackbars.showSnackBarAtBottom(
        'Image Saved', 'Image saved to Downloads', 'success');
  }

  Future<void> shareImage(Uint8List imageBytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/shared_image.png');
    await file.writeAsBytes(imageBytes);
    await SharePlus.instance.share(ShareParams(
      text: 'Check out this detected image!',
      subject: 'Object Detection Result',
      files: [XFile(file.path, mimeType: 'image/png')],
    ));
  }
}