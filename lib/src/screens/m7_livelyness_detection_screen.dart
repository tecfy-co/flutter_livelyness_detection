// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:livelyness_detection/index.dart';
import 'package:livelyness_detection/src/core/helpers/image_converter.dart';
import '../../livelyness_detection.dart';

List<CameraDescription> availableCams = [];

class LivelynessDetectionScreenV1 extends StatefulWidget {
  final DetectionConfig config;
  const LivelynessDetectionScreenV1({
    required this.config,
    super.key,
  });

  @override
  State<LivelynessDetectionScreenV1> createState() =>
      _MLivelyness7DetectionScreenState();
}

class _MLivelyness7DetectionScreenState
    extends State<LivelynessDetectionScreenV1> {
  //* MARK: - Private Variables
  //? =========================================================
  late bool _isInfoStepCompleted;
  late final List<LivelynessStepItem> steps;
  CameraController? _cameraController;
  CustomPaint? _customPaint;
  int _cameraIndex = 0;
  bool _isBusy = false;
  final GlobalKey<LivelynessDetectionStepOverlayState> _stepsKey =
      GlobalKey<LivelynessDetectionStepOverlayState>();
  bool _isProcessingStep = false;
  bool _didCloseEyes = false;
  bool _isTakingPicture = false;
  Timer? _timerToDetectFace;
  bool _isCaptureButtonVisible = false;
  InputImage? lastImage;
  Face? lastFace;

  late final List<LivelynessStepItem> _steps;

  //* MARK: - Life Cycle Methods
  //? =========================================================
  @override
  void initState() {
    _preInitCallBack();
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _postFrameCallBack(),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _timerToDetectFace?.cancel();
    _timerToDetectFace = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  //* MARK: - Private Methods for Business Logic
  //? =========================================================
  void _preInitCallBack() {
    _steps = widget.config.steps;
    _isInfoStepCompleted = !widget.config.startWithInfoScreen;
  }

  void _postFrameCallBack() async {
    availableCams = await availableCameras();
    if (availableCams.any(
      (element) =>
          element.lensDirection == CameraLensDirection.front &&
          element.sensorOrientation == 90,
    )) {
      _cameraIndex = availableCams.indexOf(
        availableCams.firstWhere((element) =>
            element.lensDirection == CameraLensDirection.front &&
            element.sensorOrientation == 90),
      );
    } else {
      _cameraIndex = availableCams.indexOf(
        availableCams.firstWhere(
          (element) => element.lensDirection == CameraLensDirection.front,
        ),
      );
    }
    if (!widget.config.startWithInfoScreen) {
      _startLiveFeed();
    }
  }

  void _startTimer() {
    _timerToDetectFace = Timer(
      Duration(seconds: widget.config.maxSecToDetect),
      () {
        _timerToDetectFace?.cancel();
        _timerToDetectFace = null;
        if (widget.config.allowAfterMaxSec) {
          _isCaptureButtonVisible = true;
          setState(() {});
          return;
        }
        _onDetectionCompleted(
            // imgToReturn: null,
            didCaptureAutomatically: false);
      },
    );
  }

  void _startLiveFeed() async {
    final camera = availableCams[_cameraIndex];
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _cameraController?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      _startTimer();
      _cameraController?.startImageStream(_processCameraImage);
      setState(() {});
    });
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in cameraImage.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(
      cameraImage.width.toDouble(),
      cameraImage.height.toDouble(),
    );

    final camera = availableCams[_cameraIndex];
    final imageRotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    if (imageRotation == null) return;

    final inputImageFormat = InputImageFormatValue.fromRawValue(
      cameraImage.format.raw,
    );
    if (inputImageFormat == null) return;

    final planeData = cameraImage.planes.map(
      (Plane plane) {
        return InputImageMetadata(
          size: Size(
            plane.width?.toDouble() ?? 0,
            plane.height?.toDouble() ?? 0,
          ),
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: plane.bytesPerRow,
        );
      },
    ).toList();

    final inputImageData = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: planeData.first.bytesPerRow,
    );

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: inputImageData,
    );

    _processImage(inputImage);
  }

  bool faceAcceptedForPhoto(Face face) {
    if ((face.leftEyeOpenProbability ?? 1.0) < 0.25 &&
        (face.rightEyeOpenProbability ?? 1.0) < 0.25) {
      return false;
    }
    if ((face.smilingProbability ?? 0) > 0.75) {
      return false;
    }
    if ((face.headEulerAngleY ?? 0) > 15 || (face.headEulerAngleY ?? 0) < -15) {
      return false;
    }
    return true;
  }

  bool faceBetterForPhoto(Face newface) {
    if (!faceAcceptedForPhoto(newface)) return false;
    if (newface.leftEyeOpenProbability == null ||
        newface.smilingProbability == null ||
        newface.headEulerAngleY == null) return false;
    if (lastFace == null) return true;
    var eye =
        (1 - newface.leftEyeOpenProbability!) * 50; // 1 is best      0 is worst
    var smile = (newface.smilingProbability!) * 50; // 0 is best      1 is worst
    var angle = newface.headEulerAngleY!.abs(); // 0 is best         50 is worst

    var ceye = (1 - lastFace!.leftEyeOpenProbability!) * 50;
    var csmile = (lastFace!.smilingProbability!) * 50;
    var cangle = lastFace!.headEulerAngleY!.abs();

    return (eye + smile + angle) < (ceye + csmile + cangle);
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (_isBusy) {
      return;
    }
    if (!mounted) return;
    _isBusy = true;

    final faces = await MLHelper.instance.processInputImage(inputImage);

    if (inputImage.metadata?.size != null &&
        inputImage.metadata?.rotation != null) {
      if (faces.isEmpty) {
        _resetSteps();
      } else {
        final firstFace = faces.first;

        if (lastImage == null) {
          lastImage = inputImage;
          lastFace = firstFace;
        }
        if (faceAcceptedForPhoto(firstFace) &&
            !faceAcceptedForPhoto(lastFace!)) {
          lastImage = inputImage;
          lastFace = firstFace;
        } else if (faceBetterForPhoto(firstFace)) {
          lastImage = inputImage;
          lastFace = firstFace;
        }

        final painter = FaceDetectorPainter(
          firstFace,
          inputImage.metadata!.size,
          inputImage.metadata!.rotation,
        );
        _customPaint = CustomPaint(
          painter: painter,
          child: Container(
            color: Colors.transparent,
            height: double.infinity,
            width: double.infinity,
            margin: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
              bottom: MediaQuery.of(context).padding.bottom,
            ),
          ),
        );
        if (_isProcessingStep &&
            _steps[_stepsKey.currentState?.currentIndex ?? 0].step ==
                LivelynessStep.blink) {
          if (_didCloseEyes) {
            if ((faces.first.leftEyeOpenProbability ?? 1.0) < 0.75 &&
                (faces.first.rightEyeOpenProbability ?? 1.0) < 0.75) {
              await _completeStep(
                step: _steps[_stepsKey.currentState?.currentIndex ?? 0].step,
              );
            }
          }
        }
        _detect(
          face: faces.first,
          step: _steps[_stepsKey.currentState?.currentIndex ?? 0].step,
        );
      }
    } else {
      _resetSteps();
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _completeStep({
    required LivelynessStep step,
  }) async {
    final int indexToUpdate = _steps.indexWhere(
      (p0) => p0.step == step,
    );

    _steps[indexToUpdate] = _steps[indexToUpdate].copyWith(
      isCompleted: true,
    );
    if (mounted) {
      setState(() {});
    }
    await _stepsKey.currentState?.nextPage();
    _stopProcessing();
  }

  void _takePicture({
    required bool didCaptureAutomatically,
  }) async {
    try {
      if (_cameraController == null) return;
      // if (face == null) return;
      if (_isTakingPicture) {
        return;
      }
      setState(
        () => _isTakingPicture = true,
      );

      await _cameraController?.stopImageStream();
      // final XFile? clickedImage = await _cameraController?.takePicture();

      // if (clickedImage == null) {
      // _startLiveFeed();
      // return;
      // }
      _onDetectionCompleted(
        // imgToReturn: clickedImage,
        didCaptureAutomatically: true,
      );
    } catch (e) {
      _startLiveFeed();
    }
  }

  void _onDetectionCompleted({
    // XFile? imgToReturn,
    bool? didCaptureAutomatically,
  }) async {
    if (didCaptureAutomatically != true) {
      Navigator.of(context).pop(null);
    }
    var image = await ConvertNativeImgStream().convertImgToBytes(
        lastImage!.bytes!,
        lastImage!.metadata!.size.width.toInt(),
        lastImage!.metadata!.size.height.toInt());
    Navigator.of(context).pop(
      CapturedImage(
        imgPath: null,
        bytes: image,
        didCaptureAutomatically: didCaptureAutomatically ?? true,
      ),
    );
  }

  void _resetSteps() async {
    for (var p0 in _steps) {
      final int index = _steps.indexWhere(
        (p1) => p1.step == p0.step,
      );
      _steps[index] = _steps[index].copyWith(
        isCompleted: false,
      );
    }
    _customPaint = null;
    _didCloseEyes = false;
    if (_stepsKey.currentState?.currentIndex != 0) {
      _stepsKey.currentState?.reset();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _startProcessing() {
    if (!mounted) {
      return;
    }
    setState(
      () => _isProcessingStep = true,
    );
  }

  void _stopProcessing() {
    if (!mounted) {
      return;
    }
    setState(
      () => _isProcessingStep = false,
    );
  }

  void _detect({
    required Face face,
    required LivelynessStep step,
  }) async {
    if (_isProcessingStep) {
      return;
    }
    final faceWidth = face.boundingBox.width;
    final Point<int>? leftEyePosition = face
        .getContour(
          FaceContourType.leftEye,
        )
        ?.points
        .elementAt(8);
    final Point<int>? rightEyePosition = face
        .getContour(
          FaceContourType.rightEye,
        )
        ?.points
        .elementAt(0);
    if (leftEyePosition != null && rightEyePosition != null) {
      final goldenRatio = (faceWidth /
          leftEyePosition.distanceTo(
            rightEyePosition,
          ));
      if (kDebugMode) {
        print("Golden Ratio: $goldenRatio");
      }
    }
    switch (step) {
      case LivelynessStep.blink:
        final BlinkDetectionThreshold? blinkThreshold =
            LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is BlinkDetectionThreshold,
        ) as BlinkDetectionThreshold?;
        if ((face.leftEyeOpenProbability ?? 1.0) <
                (blinkThreshold?.leftEyeProbability ?? 0.25) &&
            (face.rightEyeOpenProbability ?? 1.0) <
                (blinkThreshold?.rightEyeProbability ?? 0.25)) {
          _startProcessing();
          if (mounted) {
            setState(
              () => _didCloseEyes = true,
            );
          }
        }
        break;
      case LivelynessStep.turnLeft:
        final HeadTurnDetectionThreshold? headTurnThreshold =
            LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is HeadTurnDetectionThreshold,
        ) as HeadTurnDetectionThreshold?;
        if ((face.headEulerAngleY ?? 0) <
            (headTurnThreshold?.rotationAngle ?? -40)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
      case LivelynessStep.turnRight:
        final HeadTurnDetectionThreshold? headTurnThreshold =
            LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is HeadTurnDetectionThreshold,
        ) as HeadTurnDetectionThreshold?;
        if ((face.headEulerAngleY ?? 0) >
            (headTurnThreshold?.rotationAngle ?? 45)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
      case LivelynessStep.smile:
        final SmileDetectionThreshold? smileThreshold =
            LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is SmileDetectionThreshold,
        ) as SmileDetectionThreshold?;
        if ((face.smilingProbability ?? 0) >
            (smileThreshold?.probability ?? 0.75)) {
          _startProcessing();
          await _completeStep(step: step);
        }
        break;
      case LivelynessStep.photoPosition:
        final BlinkDetectionThreshold? blinkThreshold =
            LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is BlinkDetectionThreshold,
        ) as BlinkDetectionThreshold?;
        if ((face.leftEyeOpenProbability ?? 1.0) <
                (blinkThreshold?.leftEyeProbability ?? 0.25) &&
            (face.rightEyeOpenProbability ?? 1.0) <
                (blinkThreshold?.rightEyeProbability ?? 0.25)) {
          break;
        }
        final SmileDetectionThreshold? smileThreshold =
            LivelynessDetection.instance.thresholdConfig.firstWhereOrNull(
          (p0) => p0 is SmileDetectionThreshold,
        ) as SmileDetectionThreshold?;
        if ((face.smilingProbability ?? 0) >
            (smileThreshold?.probability ?? 0.75)) {
          break;
        }
        if ((face.headEulerAngleY ?? 0) > 10 ||
            (face.headEulerAngleY ?? 0) < -10) {
          break;
        }
        _startProcessing();
        await _completeStep(step: step);
        break;
    }
  }

  //* MARK: - Private Methods for UI Components
  //? =========================================================
  Widget _buildBody() {
    return Stack(
      children: [
        _isInfoStepCompleted
            ? _buildDetectionBody()
            : LivelynessInfoWidget(
                onStartTap: () {
                  if (mounted) {
                    setState(
                      () => _isInfoStepCompleted = true,
                    );
                  }
                  _startLiveFeed();
                },
              ),
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(
              right: 10,
              top: 10,
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.black,
              child: IconButton(
                onPressed: () => _onDetectionCompleted(
                  // imgToReturn: null,
                  didCaptureAutomatically: false,
                ),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetectionBody() {
    if (_cameraController == null ||
        _cameraController?.value.isInitialized == false) {
      return const Center(
        child: CircularProgressIndicator.adaptive(),
      );
    }
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * _cameraController!.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    final Widget cameraView = CameraPreview(_cameraController!);
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: cameraView,
        ),
        BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: 5.0,
            sigmaY: 5.0,
          ),
          child: Container(
            color: Colors.transparent,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        Center(
          child: cameraView,
        ),
        if (widget.config.showFacialVertices) ...[
          if (_customPaint != null) _customPaint!,
        ],
        LivelynessDetectionStepOverlay(
          key: _stepsKey,
          steps: _steps,
          onCompleted: () => Future.delayed(
            const Duration(milliseconds: 500),
            () => _takePicture(
              didCaptureAutomatically: true,
            ),
          ),
        ),
        Visibility(
          visible: _isCaptureButtonVisible,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Spacer(
                flex: 20,
              ),
              MaterialButton(
                onPressed: () => _takePicture(
                  didCaptureAutomatically: false,
                ),
                color: widget.config.captureButtonColor ??
                    Theme.of(context).primaryColor,
                textColor: Colors.white,
                padding: const EdgeInsets.all(16),
                shape: const CircleBorder(),
                child: const Icon(
                  Icons.camera_alt,
                  size: 24,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }
}

extension FaceExt on Face {
  FaceContour? getContour(FaceContourType type) {
    switch (type) {
      case FaceContourType.face:
        return contours[FaceContourType.face];
      case FaceContourType.leftEyebrowTop:
        return contours[FaceContourType.leftEyebrowTop];
      case FaceContourType.leftEyebrowBottom:
        return contours[FaceContourType.leftEyebrowBottom];
      case FaceContourType.rightEyebrowTop:
        return contours[FaceContourType.rightEyebrowTop];
      case FaceContourType.rightEyebrowBottom:
        return contours[FaceContourType.rightEyebrowBottom];
      case FaceContourType.leftEye:
        return contours[FaceContourType.leftEye];
      case FaceContourType.rightEye:
        return contours[FaceContourType.rightEye];
      case FaceContourType.upperLipTop:
        return contours[FaceContourType.upperLipTop];
      case FaceContourType.upperLipBottom:
        return contours[FaceContourType.upperLipBottom];
      case FaceContourType.lowerLipTop:
        return contours[FaceContourType.lowerLipTop];
      case FaceContourType.lowerLipBottom:
        return contours[FaceContourType.lowerLipBottom];
      case FaceContourType.noseBridge:
        return contours[FaceContourType.noseBridge];
      case FaceContourType.noseBottom:
        return contours[FaceContourType.noseBottom];
      case FaceContourType.leftCheek:
        return contours[FaceContourType.leftCheek];
      case FaceContourType.rightCheek:
        return contours[FaceContourType.rightCheek];
    }
  }
}
