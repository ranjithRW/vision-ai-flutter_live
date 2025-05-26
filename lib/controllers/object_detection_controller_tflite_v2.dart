import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:logger/logger.dart';
import 'package:tflite_v2/tflite_v2.dart';
import 'package:vision_ai_app/model_classes/recognized_object.dart';
import 'package:vision_ai_app/screens/result_image_screen.dart';

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
  var imageAspectRatio = (3 / 4).obs; // default vertical ratio
  var isLoadingImage = false.obs;

  late Interpreter interpreter;
  late List<String> labels;

  late CameraController cameraController;

  static const int inputSize = 300;
  static const double threshold = 0.4;

  // Output buffers
  late List<List<List<double>>> outputBoxes; // shape: [1, num_boxes, 4]
  late List<List<double>> outputScores; // shape: [1, num_boxes]
  late List<List<double>> outputClasses; // shape: [1, num_boxes]
  late List<double> numDetections; // shape: [1]

  DateTime? lastInference;
  final Duration throttleDuration = const Duration(milliseconds: 150);

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
    }
  }

  Future<void> initializeCamera() async {
    try {
      logger.i('Initializing camera...');
      final cameras = await availableCameras();
      cameraController = CameraController(cameras[0], ResolutionPreset.medium,
          enableAudio: false);
      await cameraController.initialize();
      isCameraInitialized.value = true;

      if (isLive) {
        logger.i('Start Streaming images from camera');
        // Start image stream
        cameraController.startImageStream((CameraImage image) {
          if (!isDetecting.value && isModelLoaded.value) {
            isDetecting.value = true;
            runModelOnFrame(image).then((_) {
              isDetecting.value = false;
            });
          }
          // ! This makes the interpreter busy
          // isDetecting.value = true;
          // runModelOnFrame(image).then((_) {
          //   isDetecting.value = false;
          // });
        });
      }
    } catch (e) {
      logger.e('Camera initialization error: $e');
    }
  }

  Future<void> stopCamera() async {
    if (cameraController.value.isStreamingImages) {
      await cameraController.stopImageStream();
    }
    await cameraController.dispose();
    isCameraInitialized.value = false;
  }

  /// Run TFLite model on CameraImage frame - CORRECTED FOR SSD MobileNet
  Future<void> runModelOnFrame(CameraImage cameraImage) async {
    logger.i('Running model on frame');
    if (!isModelLoaded.value) return;

    final now = DateTime.now();
    if (lastInference != null &&
        now.difference(lastInference!) < throttleDuration) {
      return;
    }
    lastInference = now;

    try {
      logger.i('Starting detection');
      logger.i('Running inference');
      // logger.i('Input tensor shape: ${inputTensor.length}');
      var recognitions = await Tflite.detectObjectOnFrame(
          bytesList: cameraImage.planes.map((plane) {
            return plane.bytes;
          }).toList(),
          model: 'SSDMobileNet',
          imageHeight: cameraImage.height,
          imageWidth: cameraImage.width,
          imageMean: 127.5, // defaults to 127.5
          imageStd: 127.5, // defaults to 127.5
          rotation: 90, // defaults to 90, Android only
          numResultsPerClass: 5, // defaults to 5
          threshold: 0.1, // defaults to 0.1
          asynch: true // defaults to true
          );
      logger.i('Inference completed');
      logger.i('Recognitions: $recognitions');
      detectedObjects.assignAll(await mapRecognitions(recognitions));
      logger.i('Detected objects: $detectedObjects');
    } catch (e) {
      logger.e('Error during inference: $e');
    } finally {
      isDetecting.value = false;
    }
  }

  Future<void> runObjectDetectionOnSelectedImage() async {
    logger.i('Running model on frame');
    if (!isModelLoaded.value) return;

    final now = DateTime.now();
    if (lastInference != null &&
        now.difference(lastInference!) < throttleDuration) {
      return;
    }
    lastInference = now;
    try {
      isDetecting.value = true;
      logger.i('Running model on selected image: ${selectedImagePath.value}');
      var recognitions = await Tflite.detectObjectOnImage(
          path: selectedImagePath.value,
          model: 'SSDMobileNet',
          imageMean: 127.5, // defaults to 127.5
          imageStd:
              127.5, // defaults to 127.5numResultsPerClass: 5, // defaults to 5
          threshold: 0.1, // defaults to 0.1
          asynch: true // defaults to true
          );
      logger.i('Inference completed');
      logger.i('Recognitions: $recognitions');
      detectedObjects.assignAll(await mapRecognitions(recognitions));
      logger.i('Detected objects: $detectedObjects');
      Get.to(const ResultImageScreen());
    } catch (e) {
      logger.e('Error during inference: $e');
      Get.snackbar('Error', 'Failed to run object detection: $e');
    } finally {
      isDetecting.value = false;
    }
  }

  Future<List<RecognizedObject>> mapRecognitions(
      List<dynamic>? recognitions) async {
    if (recognitions == null) {
      logger.i('No recognitions found');
      return [];
    }
    return recognitions.map((recognition) {
      final map = Map<String, dynamic>.from(recognition as Map); // Safe cast

      final rectData = Map<String, dynamic>.from(map['rect'] as Map);

      final rect = Rect.fromLTWH(
        rectData['x'] as double,
        rectData['y'] as double,
        rectData['w'] as double,
        rectData['h'] as double,
      );
      return RecognizedObject(
        rect: rect,
        label: map['detectedClass'] as String,
        confidence: map['confidenceInClass'] as double,
      );
    }).toList();
  }

//Other methods
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
      Get.snackbar('Error', 'Failed to pick image: $e');
    } finally {
      isLoadingImage.value = false;
    }
  }

  Future<void> _calculateImageAspectRatio(String imagePath) async {
    try {
      // Read image file as bytes
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
  }

  Future<Size> getImageSizeFromFile(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    return Size(image.width.toDouble(), image.height.toDouble());
  }
}
