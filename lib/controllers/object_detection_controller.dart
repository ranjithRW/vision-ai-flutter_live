import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:get/get.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
// import 'package:tflite_flutter/tflite_flutter.dart';
// import 'package:tflite_flutter_helper/tflite_flutter_helper.dart';

class ObjectDetectionController extends GetxController {
  // late Interpreter interpreter;
  var isModelLoaded = false.obs;
  var detectedObjects = <String>[].obs;
  late CameraController cameraController;
  var isCameraInitialized = false.obs;
  var isDetecting = false.obs;
  var selectedImagePath = ''.obs;
  var imageAspectRatio = (3 / 4).obs; // Default vertical ratio
  var isLoadingImage = false.obs;
  var dummy = "".obs;

  get results => null;

  @override
  void onInit() {
    super.onInit();
    initializeCamera();
    // loadModel();
  }

  @override
  void onClose() {
    stopCamera();
    super.onClose();
  }

  Future<void> stopCamera() async {
    if (cameraController.value.isStreamingImages) {
      await cameraController.stopImageStream();
    }
    await cameraController.dispose();
    isCameraInitialized.value = false;
  }

  // TODO: Implement the model loading logic later
  // Future<void> loadModel() async {
  //   interpreter = await Interpreter.fromAsset('model.tflite');
  //   isModelLoaded.value = true;
  // }

  Future<void> initializeCamera() async {
    final cameras = await availableCameras();
    cameraController = CameraController(
      cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );

    await cameraController.initialize();
    isCameraInitialized.value = true;

    // Start the stream
    cameraController.startImageStream((CameraImage image) {
      if (!isDetecting.value) {
        isDetecting.value = true;
        // runModelOnFrame(image).then((_) {
        //   isDetecting = false;
        // });
      }
    });
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      isLoadingImage.value = true;
      final XFile? image = await picker.pickImage(source: source);

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
      final XFile imageFile = XFile(imagePath);
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // Decode image to get dimensions
      final ui.Codec codec = await ui.instantiateImageCodec(imageBytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image image = frameInfo.image;

      // Calculate aspect ratio (width / height)
      final double aspectRatio = image.width / image.height;
      imageAspectRatio.value = aspectRatio;

      // Dispose the image to free memory
      image.dispose();
    } catch (e) {
      // Fallback to default ratio
      imageAspectRatio.value = 3 / 4;
    }
  }

  void clearImage() {
    selectedImagePath.value = '';
    imageAspectRatio.value = 3 / 4; // Reset to default
  }

  Future<void> runObjectDetectionOnSelectedImage() async {
    // Your logic to run detection using selectedImagePath
  }

  void detectObjects(CameraImage image) {
    // Convert CameraImage to the required input format
    // Run inference using interpreter
    // Update detectedObjects with the results
  }
}
