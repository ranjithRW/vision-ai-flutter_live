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
  final ImagePicker _picker = ImagePicker();
  var isDetecting = false.obs;

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

  Future<void> pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      // Process the image using the interpreter
      // Update detectedObjects with the results
    }
  }

  void detectObjects(CameraImage image) {
    // Convert CameraImage to the required input format
    // Run inference using interpreter
    // Update detectedObjects with the results
  }
}
