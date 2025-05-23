import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:logger/logger.dart';
import 'package:vision_ai_app/model_classes/recognized_object.dart';

class ObjectDetectionControllerTFLite extends GetxController {
  final Logger logger = Logger();

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
  void onInit() {
    super.onInit();
    loadModel();
    initializeCamera();
  }

  @override
  void onClose() {
    stopCamera();
    interpreter.close();
    super.onClose();
  }

  Future<void> loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset(
          'assets/models/ssd_mobilenet_external.tflite');
      // Load labels from asset file
      String labelsData = await DefaultAssetBundle.of(Get.context!)
          .loadString('assets/labels/ssd_mobilenet.txt');
      labels = labelsData
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      logger.i('Loaded labels: $labels');
      // printModelIO();
      isModelLoaded.value = true;
      logger.i('Model and labels loaded');
      interpreter.allocateTensors();
    } catch (e) {
      logger.e('Failed to load model: $e');
    }
  }

  void printModelIO() {
    final inputs = interpreter.getInputTensors();
    final outputs = interpreter.getOutputTensors();

    for (var input in inputs) {
      logger.i(
          'INPUT: name=${input.name}, shape=${input.shape}, type=${input.type}');
    }

    for (var output in outputs) {
      logger.i(
          'OUTPUT: name=${output.name}, shape=${output.shape}, type=${output.type}');
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
      logger.i('Camera initialized');
      // Start image stream
      cameraController.startImageStream((CameraImage image) {
        logger.i('Received image stream');
        logger.i('isDetecting: ${isDetecting.value}');
        logger.i('isModelLoaded: ${isModelLoaded.value}');
        logger.i(
            'Valid to run model: ${!isDetecting.value && isModelLoaded.value}');
        if (!isDetecting.value && isModelLoaded.value) {
          isDetecting.value = true;
          runModelOnFrame(image).then((_) {
            isDetecting.value = false;
          });
        }
      });
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

  /// Converts YUV420 CameraImage to RGB image using the image package
  img.Image convertYUV420ToImage(CameraImage image) {
    logger.i('Converting YUV420 to RGB image');
    final int width = image.width;
    final int height = image.height;
    logger.i('Image size: $width x $height');
    final img.Image imgImage = img.Image(width: width, height: height);
    logger.i('Created image object: $imgImage');

    final Plane planeY = image.planes[0];
    final Plane planeU = image.planes[1];
    final Plane planeV = image.planes[2];
    logger.i(
        'Planes: Y: ${planeY.bytes.length}, U: ${planeU.bytes.length}, V: ${planeV.bytes.length}');

    final Uint8List bytesY = planeY.bytes;
    final Uint8List bytesU = planeU.bytes;
    final Uint8List bytesV = planeV.bytes;
    logger.i('Y plane bytes: ${bytesY.length}');
    logger.i('U plane bytes: ${bytesU.length}');
    logger.i('V plane bytes: ${bytesV.length}');

    final int strideY = planeY.bytesPerRow;
    final int strideUV = planeU.bytesPerRow;
    logger.i('Y stride: $strideY, UV stride: $strideUV');

    for (int y = 0; y < height; y++) {
      final int uvRow = (y / 2).floor();

      for (int x = 0; x < width; x++) {
        final int uvCol = (x / 2).floor();

        final int indexY = y * strideY + x;
        final int indexU = uvRow * strideUV + uvCol;
        final int indexV = uvRow * strideUV + uvCol;

        final int Y = bytesY[indexY];
        final int U = bytesU[indexU];
        final int V = bytesV[indexV];

        // YUV to RGB conversion formula
        int R = (Y + 1.402 * (V - 128)).round();
        int G = (Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)).round();
        int B = (Y + 1.772 * (U - 128)).round();

        R = R.clamp(0, 255);
        G = G.clamp(0, 255);
        B = B.clamp(0, 255);

        imgImage.setPixelRgba(x, y, R, G, B, 255);
      }
    }

    logger.i('Converted image: $imgImage');

    return imgImage;
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

      // Convert YUV420 camera image to RGB image
      final img.Image convertedImage = convertYUV420ToImage(cameraImage);

      // Resize to model input size (300x300)
      logger.i('Resizing image to ${inputSize}x$inputSize');
      final img.Image resizedImage =
          img.copyResize(convertedImage, width: inputSize, height: inputSize);

      // Convert image to uint8 input tensor [1, 300, 300, 3]
      final Uint8List inputTensor =
          imageToByteListUint8(resizedImage, inputSize);

      // Prepare output buffers based on TFLite_Detection_PostProcess outputs
      // Output 0: TFLite_Detection_PostProcess, shape=[1, 10, 4] - BOXES
      var outputBoxes = List.generate(
          1, (_) => List.generate(10, (_) => List.generate(4, (_) => 0.0)));

      // Output 1: TFLite_Detection_PostProcess:1, shape=[1, 10] - CLASSES
      var outputClasses =
          List.generate(1, (_) => List.generate(10, (_) => 0.0));

      // Output 2: TFLite_Detection_PostProcess:2, shape=[1, 10] - SCORES
      var outputScores = List.generate(1, (_) => List.generate(10, (_) => 0.0));

      // Output 3: TFLite_Detection_PostProcess:3, shape=[1] - NUM_DETECTIONS
      var numDetections = List.generate(1, (_) => 0.0);

      // Map outputs (order matters!)
      Map<int, Object> outputs = {
        0: outputBoxes, // Bounding boxes [1, 10, 4]
        1: outputClasses, // Class indices [1, 10]
        2: outputScores, // Confidence scores [1, 10]
        3: numDetections, // Number of valid detections [1]
      };
    
      // Run inference
      logger.i('Running inference');
      logger.i('Input tensor shape: ${inputTensor.length}');
      logger.i('Output tensor shapes:');
      logger.i('Boxes: ${outputBoxes.length}');
      logger.i('Classes: ${outputClasses.length}');
      logger.i('Scores: ${outputScores.length}');
      logger.i('Num detections: ${numDetections.length}');
      interpreter.runForMultipleInputs(inputTensor, outputs);

      logger.i('Inference completed');
      logger.i('Number of detections: ${numDetections[0]}');

      // Parse outputs using the standard TFLite Detection PostProcess format
      parseOutputsStandard(
        outputBoxes[0], // [10, 4]
        outputClasses[0], // [10]
        outputScores[0], // [10]
        numDetections[0], // single value
        cameraImage.width,
        cameraImage.height,
      );
    } catch (e) {
      logger.e('Error during inference: $e');
    } finally {
      isDetecting.value = false;
    }
  }

  /// Convert Image to uint8 input tensor [1, 300, 300, 3]
  Uint8List imageToByteListUint8(img.Image image, int inputSize) {
    logger.i('Converting image to uint8 tensor [$inputSize x $inputSize x 3]');

    final buffer = Uint8List(1 * inputSize * inputSize * 3);
    int pixelIndex = 0;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);
        buffer[pixelIndex++] = pixel.r.toInt(); // R channel (0-255)
        buffer[pixelIndex++] = pixel.g.toInt(); // G channel (0-255)
        buffer[pixelIndex++] = pixel.b.toInt(); // B channel (0-255)
      }
    }

    logger.i('Created uint8 buffer with ${buffer.length} elements');
    return buffer;
  }

  /// Standard parsing for TFLite Detection PostProcess outputs
  void parseOutputsStandard(
    List<List<double>> boxes, // [10, 4]
    List<double> classes, // [10]
    List<double> scores, // [10]
    double numDetections, // single value
    int imageWidth,
    int imageHeight,
  ) {
    logger.i('Parsing standard TFLite Detection PostProcess outputs');
    logger.i('Number of detections: $numDetections');

    int count = numDetections.toInt().clamp(0, 10); // Max 10 detections
    List<RecognizedObject> results = [];

    for (int i = 0; i < count; i++) {
      double score = scores[i];
      logger.i('Detection $i: score=$score, threshold=$threshold');

      if (score < threshold) {
        logger.i('Skipping detection $i due to low score');
        continue;
      }

      // Box coordinates are typically [ymin, xmin, ymax, xmax] and normalized (0-1)
      final box = boxes[i];
      double ymin = box[0];
      double xmin = box[1];
      double ymax = box[2];
      double xmax = box[3];

      logger.i('Box $i: ymin=$ymin, xmin=$xmin, ymax=$ymax, xmax=$xmax');

      // Convert normalized coordinates to pixel coordinates
      Rect rect = Rect.fromLTRB(
        xmin * imageWidth,
        ymin * imageHeight,
        xmax * imageWidth,
        ymax * imageHeight,
      );

      // Get class label
      int classIndex = classes[i].toInt();
      String label =
          classIndex < labels.length ? labels[classIndex] : "Unknown";

      logger.i(
          'Detection $i: $label (class $classIndex) with confidence ${score.toStringAsFixed(2)}');

      results.add(RecognizedObject(
        rect: rect,
        label: label,
        confidence: score,
      ));
    }

    logger.i('Found ${results.length} valid detections');
    detectedObjects.value = results;
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      isLoadingImage.value = true;
      final image = await picker.pickImage(source: source);

      if (image != null) {
        selectedImagePath.value = image.path;
        await _calculateImageAspectRatio(image.path);

        // Run detection on picked image
        await runObjectDetectionOnSelectedImage(image.path);
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

  /// Updated method for selected images
  Future<void> runObjectDetectionOnSelectedImage(String imagePath) async {
    isLoadingImage.value = true;
    try {
      Uint8List imageBytes = await XFile(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(imageBytes);

      if (image == null) {
        logger.e('Failed to decode selected image');
        return;
      }

      // Resize to model input size (300x300)
      img.Image resizedImage =
          img.copyResize(image, width: inputSize, height: inputSize);

      // Convert to uint8 input tensor
      var input = imageToByteListUint8(resizedImage, inputSize);

      // Prepare output buffers
      var outputBoxes = List.generate(
          1, (_) => List.generate(10, (_) => List.generate(4, (_) => 0.0)));
      var outputClasses =
          List.generate(1, (_) => List.generate(10, (_) => 0.0));
      var outputScores = List.generate(1, (_) => List.generate(10, (_) => 0.0));
      var numDetections = List.generate(1, (_) => 0.0);

      var outputs = {
        0: outputBoxes,
        1: outputClasses,
        2: outputScores,
        3: numDetections,
      };

      interpreter.run(input, outputs);

      parseOutputsStandard(
        outputBoxes[0],
        outputClasses[0],
        outputScores[0],
        numDetections[0],
        image.width,
        image.height,
      );
    } catch (e) {
      logger.e("Error detecting on selected image: $e");
    } finally {
      isLoadingImage.value = false;
    }
  }
}
