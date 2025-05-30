//
//  ViewController.swift
//  tripletalear
//
//  Created by Wes Wang on 8/18/24.
//

import UIKit
import SceneKit
import ARKit
import Vision
import CoreMotion

class MainViewController: UIViewController, ARSCNViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    let hasLiDAR = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)

    var sceneView: ARSCNView!
    
    private var subscriptionManager = InAppPurchaseManager()
    
    private var bracketView: BracketView?

    private var isProcessingCameraPress = false
    private var classifierLabel: UILabel?
    
    // Labels for classified objects by ARAnchor UUID
    private var anchorLabels = [UUID: String]()
        
    private var debugCounter = 0
    private var debugNodes: [SCNNode] = []
    private var debugMode: Bool = false

    private var currentBuffer: CVPixelBuffer?
    private var isProcessingML = false
    private var lastMLTimestamp: TimeInterval = 0
    
    private var deviceOrientation: CGFloat = 0.0
    
    private var tapCounter = 0
    var scaleFactor: Double = 800.0
    
    var screenRatio: CGFloat = 0.95
    
    var inwardPercent: Double = 20.0 // 5%
    var heightNudge: Double = 1.0
    
    var lengthScale: Double = 1.05
    var widthScale: Double = 1.05
    
    var bodyRatio: Double = 2.75
    
    // Classification results
    private var identifierString = ""
    private var confidence: VNConfidence = 0.0
    private var boundingBox: CGRect?
    
    private var motionManager = CMMotionManager()
    private var isFacingForward = true

    private var cameraButton: UIButton?
    private var feedbackLabel: UILabel?
        
    // Queue for dispatching vision classification requests
    private let visionQueue = DispatchQueue(label: "com.tripletale.tripletaleapp")
    
    /// The ML model to be used for detection of arbitrary objects
    private var _tripleTaleModel: TripleTaleV2!
    private var tripleTaleModel: TripleTaleV2! {
        get {
            if let model = _tripleTaleModel { return model }
            _tripleTaleModel = {
                do {
                    let configuration = MLModelConfiguration()
                    return try TripleTaleV2(configuration: configuration)
                } catch {
                    fatalError("Couldn't create TripleTale due to: \(error)")
                }
            }()
            return _tripleTaleModel
        }
    }
    
    private lazy var mlRequest: VNCoreMLRequest = {
        do {
            // Instantiate the model from its generated Swift class.
            let model = try VNCoreMLModel(for: tripleTaleModel.model)
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                if let result = processObservations(for: request, error: error) {
                    DispatchQueue.main.async {
                        self?.handleClassificationResult(identifier: result.identifierString, confidence: result.confidence, boundingBox: result.boundingBox)
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.handleClassificationResult(identifier: "", confidence: 0, boundingBox: nil)
                    }
                }
            })

            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    // The view controller that displays the status and "restart experience" UI.
    private lazy var statusViewController: StatusViewController? = {
        return children.lazy.compactMap { $0 as? StatusViewController }.first
    }()

    private lazy var fishExtractor: FishSegmentation = {
        do {
            return try FishSegmentation(configuration: MLModelConfiguration())
        } catch {
            fatalError("❌ Failed to load FishSegmentation model: \(error)")
        }
    }()
    
//    private lazy var imageEncoder: MLModel = {
//        do {
//            let url = Bundle.main.url(forResource: "SAM2_1BasePlusImageEncoderFLOAT16", withExtension: "mlmodelc")!
//            return try MLModel(contentsOf: url)
//        } catch {
//            fatalError("❌ Failed to load image encoder: \(error)")
//        }
//    }()
//
//    private lazy var promptEncoder: MLModel = {
//        do {
//            let url = Bundle.main.url(forResource: "SAM2_1BasePlusPromptEncoderFLOAT16", withExtension: "mlmodelc")!
//            return try MLModel(contentsOf: url)
//        } catch {
//            fatalError("❌ Failed to load prompt encoder: \(error)")
//        }
//    }()
//
//    private lazy var maskDecoder: MLModel = {
//        do {
//            let url = Bundle.main.url(forResource: "SAM2_1BasePlusMaskDecoderFLOAT16", withExtension: "mlmodelc")!
//            return try MLModel(contentsOf: url)
//        } catch {
//            fatalError("❌ Failed to load mask decoder: \(error)")
//        }
//    }()
//
    func extractFish(from inputImage: UIImage) -> UIImage? {
        do {
            // Resize image to 256x256 (required by SAM2 Tiny)
            guard let resizedImage = resizeImageForModel(inputImage, width: 416, height: 416) ,
                  let pixelBuffer = pixelBuffer(from: resizedImage) else {
                print("❌ Failed to preprocess image.")
                return nil
            }

            let result = try fishExtractor.prediction(input_image: pixelBuffer)

            guard let maskArray = result.featureValue(for: "var_520")?.multiArrayValue else {
                print("❌ Could not extract MLMultiArray from result")
                return nil
            }
            
            let count = maskArray.count
            let flatValues = (0..<count).map { maskArray[$0].floatValue }

            let minVal = flatValues.min() ?? 0
            let maxVal = flatValues.max() ?? 0
            let meanVal = flatValues.reduce(0, +) / Float(count)

            if let maskImage = postprocessFishMask(from: maskArray, originalSize: inputImage.size) {
                let originalSize = inputImage.size
                if let resizedMask = resizeMaskToOriginal(maskImage: maskImage, targetSize: originalSize) {
                    return resizedMask
                }
            }
            
            return nil

        } catch {
            print("❌ Failed to load SAM models: \(error)")
            return nil
        }
    }
    
//    func processSAMImage(from inputImage: UIImage) -> UIImage? {
//        do {
//            // Resize image to 256x256 (required by SAM2 Tiny)
//            guard let resizedImage = resizeImageForModel(inputImage, width: 1024, height: 1024) ,
//                  let pixelBuffer = pixelBuffer(from: resizedImage) else {
//                print("❌ Failed to preprocess image.")
//                return nil
//            }
//
//            // Use center click (normalized coordinates)
//            let centerX: Float = 512
//            let centerY: Float = 512
//            
//            guard let points = try? MLMultiArray(shape: [1, 1, 2], dataType: .float16),
//                  let labels = try? MLMultiArray(shape: [1, 1], dataType: .float16) else {
//                print("❌ Failed to create input arrays")
//                return nil
//            }
//            points[0] = centerX as NSNumber
//            points[1] = centerY as NSNumber
//            labels[0] = 1.0
//
//            // Run Image Encoder
//            let imageInput = try MLDictionaryFeatureProvider(dictionary: ["image": pixelBuffer])
//            let imageFeatures = try imageEncoder.prediction(from: imageInput)
//
//            // Run Prompt Encoder
//            let promptInput = try MLDictionaryFeatureProvider(dictionary: [
//                "points": points,
//                "labels": labels
//            ])
//            let promptFeatures = try promptEncoder.prediction(from: promptInput)
//
//            // Run Mask Decoder
//            let decoderInput = try MLDictionaryFeatureProvider(dictionary: [
//                "image_embedding": imageFeatures.featureValue(for: "image_embedding")!,
//                "sparse_embedding": promptFeatures.featureValue(for: "sparse_embeddings")!,
//                "dense_embedding": promptFeatures.featureValue(for: "dense_embeddings")!,
//                "feats_s0": imageFeatures.featureValue(for: "feats_s0")!,
//                "feats_s1": imageFeatures.featureValue(for: "feats_s1")!
//            ])
//            let maskOutput = try maskDecoder.prediction(from: decoderInput)
//            
//            // Log available outputs
//            for name in maskOutput.featureNames {
//                print("🧠 Decoder output available: \(name)")
//            }
//            
//            guard let maskArray = maskOutput.featureValue(for: "low_res_masks")?.multiArrayValue else {
//                print("❌ SAM decoder did not return 'low_res_masks' as MLMultiArray.")
//                return nil
//            }
//            
//            let scores = maskOutput.featureValue(for: "scores")!.multiArrayValue!
//            print("Mask scores: \(scores)")
//            print("Mask size: \(maskArray.shape)")
//            
//            // Create new MLMultiArray [1,1,256,256]
//            let totalPixels = 256 * 256
//            // Extract first mask at index 0
//            let startIndex = 2*256*256 // [1, 3, 256, 256] — first mask
//            let sliceValues = (0..<totalPixels).map { i in
//                maskArray[startIndex + i].floatValue
//            }
//            
//            guard let singleMask = try? MLMultiArray(shape: [1, 1, NSNumber(value: 256), NSNumber(value: 256)], dataType: .float16) else {
//                print("❌ Could not create reshaped MLMultiArray")
//                return nil
//            }
//            
//            // Fill it with the first mask's data
//            for i in 0..<totalPixels {
//                singleMask[i] = NSNumber(value: sliceValues[i])
//            }
//            
//            // Convert to grayscale image
//            let maskImage = multiArrayToGrayscaleImage(singleMask)
//
//            // Resize the mask to match the original input image size
//            if let maskImage = maskImage {
//                let resizedMask = resizeImageForModel(maskImage, width: Int(inputImage.size.width), height: Int(inputImage.size.height))
//                return resizedMask
//            }
//
//            return nil
//
//        } catch {
//            print("❌ Failed to load SAM models: \(error)")
//            return nil
//        }
//    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("has lidar: \(self.hasLiDAR)")
        
        sceneView = ARSCNView(frame: self.view.frame)
        sceneView.delegate = self
        view.addSubview(sceneView)

        if !hasLiDAR {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "LiDAR Required", message: "This app requires a LiDAR-enabled device. Non-LiDAR devices support will be enabled in future updates.", preferredStyle: .alert)

                // Normal OK action (will exit if tapped once)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                    exit(0)
                }))
                
                self.present(alert, animated: true)
            }
        }

        // Create splash/loading image view
        showLoadingOverlay()
        
        Task {
            await subscriptionManager.loadProducts()
            await subscriptionManager.updateSubscriptionStatus()
            
            DispatchQueue.main.async {
                printActiveEntitlements()
            }
        }
        
        Task.detached(priority: .utility) {
            _ = await self.fishExtractor  // Load 1st model

//            _ = await self.imageEncoder  // Load 1st model
//            _ = await self.promptEncoder // Load 2nd model (after 1st completes)
//            _ = await self.maskDecoder   // Load 3rd model (after 2nd completes)

            // Update UI once all done
            DispatchQueue.main.async {
                self.hideLoadingOverlay()
                                
                // Add the bracket view to the main view
                self.bracketView = BracketView(frame: self.view.bounds)
                self.bracketView?.isUserInteractionEnabled = false // Make sure it doesn't intercept touch events
                self.view.addSubview(self.bracketView!)
                
                // Initial bracket update
//                self.updateBracketSize()
                
                // Call the function to create and add the camera button
                self.setupCameraButton()
                
                // Create a transparent view for the bottom left corner
                self.createCornerView(withSize: 100)
                
                // Create a transparent view for the bottom right corner
                self.createDebugCornerView(withSize: 100)

        //        setupClassifierLabel()
                
                // Subscribe button
//                self.setupSubscribeButton()
//                self.setupRestoreButton()
                
//                if !self.subscriptionManager.isSubscribed {
//                    let alert = UIAlertController(title: "Subscribe to Unlock", message: "  fish classification \nfish length measurement \nfish weight calculation.\n\n$9.99 per month. Cancel anytime.", preferredStyle: .alert)
//                    alert.addAction(UIAlertAction(title: "Subscribe", style: .default, handler: { _ in
//                        Task {
//                            if let product = self.subscriptionManager.products.first {
//                                await self.subscriptionManager.purchase(product)
//                            } else {
//                                self.view.showToast(message: "No subscription product available.")
//                            }
//                        }
//                    }))
////                    alert.addAction(UIAlertAction(title: "Later", style: .cancel, handler: nil))
//                    self.present(alert, animated: true, completion: nil)
//                }
                
                // Start monitoring tilt changes
                self.startMotionTracking()
                
                // Start AR
                self.startSession()
                
                // Hook up status view controller callback.
                self.statusViewController?.restartExperienceHandler = { [unowned self] in
                    self.restartSession()
                }
                
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    private func setupSubscribeButton() {
        let button = UIButton(frame: CGRect(x: 0, y: 30, width: 50, height: 50))
        
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let image = UIImage(systemName: "plus.circle", withConfiguration: config)
        button.setImage(image, for: .normal)
        button.tintColor = .systemBlue
        button.backgroundColor = .clear
        button.addTarget(self, action: #selector(handleSubscribeButton), for: .touchUpInside)
        view.addSubview(button)
    }

    @objc private func handleSubscribeButton() {
        Task {
            if let product = subscriptionManager.products.first {
                await subscriptionManager.purchase(product)
            } else {
                self.view.showToast(message: "No subscription product available. Try again later.")
            }
        }
    }
    
    private func setupRestoreButton() {
        let button = UIButton(frame: CGRect(x: view.bounds.width - 50, y: 30, width: 50, height: 50))
        
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let image = UIImage(systemName: "arrow.counterclockwise.circle", withConfiguration: config)
        button.setImage(image, for: .normal)
        button.tintColor = .systemGray
        button.backgroundColor = .clear
        button.addTarget(self, action: #selector(handleRestoreButton), for: .touchUpInside)
        view.addSubview(button)
    }

    @objc private func handleRestoreButton() {
        Task {
            await subscriptionManager.restorePurchases()
        }
    }
    
    @objc private func handleDeviceOrientationChange() {
        let orientation = UIDevice.current.orientation

        switch orientation {
        case .landscapeLeft:
            deviceOrientation = CGFloat.pi / 2
        case .landscapeRight:
            deviceOrientation = -CGFloat.pi / 2
        case .portraitUpsideDown:
            deviceOrientation = CGFloat.pi
        case .portrait, .faceUp, .faceDown, .unknown:
            deviceOrientation = 0
        default:
            deviceOrientation = 0
        }

        UIView.animate(withDuration: 0.3) {
            self.cameraButton?.transform = CGAffineTransform(rotationAngle: self.deviceOrientation)
        }
    }
    
    @objc private func handleTapGesture() {
        tapCounter += 1
        
        if tapCounter == 3 {
            tapCounter = 0 // Reset counter after showing the popup
            
            // Show the input popup
            showInputPopup(title: "Developer Mode", message: "Update Values Below", placeholders: [
                "Weight Scale: \(self.scaleFactor)",
                "Inward Nudge: \(self.inwardPercent) %",
                "Body Ratio: \(self.bodyRatio)"
            ]) { inputs in
                // Handle the user inputs here
                if let value1 = inputs[0] {
                    self.scaleFactor = value1
                }
                if let value2 = inputs[1] {
                    self.inwardPercent = value2
                }
                if let value3 = inputs[2] {
                    self.bodyRatio = value3
                }
            }
        }
    }
    
    @objc private func handleDebugGesture() {
          debugCounter += 1

          if debugCounter == 3 {
              debugCounter = 0 // Reset counter after activation

              debugMode.toggle()

              // Toggle debug options
              if debugMode {
                  // Enable debug mode
                  sceneView.debugOptions = []
                  self.view.showToast(message: "Debug Mode ENABLED")

                  // Show debug nodes (mesh and spheres)
                  for node in debugNodes {
                      node.isHidden = false
                  }
              } else {
                  // Disable debug mode
                  sceneView.debugOptions = []
                  self.view.showToast(message: "Debug Mode DISABLED")

                  // Hide debug nodes
                  for node in debugNodes {
                      node.isHidden = true
                  }
              }
          }
      }
    
    @objc func handleCameraButtonPress() {
//        guard subscriptionManager.isSubscribed else {
//            self.showPopupMessage(title: "Subscription Required", message: "You need an active subscription to use this feature.")
//            return
//        }
        
        guard !isProcessingCameraPress else {
            print("⏳ Button press ignored: Please wait for processing to complete...")
            return
        }

        isProcessingCameraPress = true

        // Haptic feedback
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()

        // Capture the current frame
        if let image = captureFrameAsUIImage(from: sceneView) {
            calculateAndDisplayWeight(with: image) { [weak self] in
                DispatchQueue.main.async {
                    self?.isProcessingCameraPress = false
                }
            }
            
//            if let cameraImage = captureRawCameraImage(from: sceneView) {
//                saveImageToGallery(cameraImage)
//            }
        } else {
            self.view.showToast(message: "Could not capture image from scene!")
            isProcessingCameraPress = false
        }
    }

    func calculateAndDisplayWeight(with image: UIImage, completion: @escaping () -> Void) {
        let mask: CIImage?
        
        if !isFacingForward {
            print("FACING down")
            self.lengthScale = 1.0
            self.widthScale = 1.0
            
            mask = generateMaskImage(from: image, for: 1.0)
        } else {
            print("FACING forward")
            self.lengthScale = 1.05
            self.widthScale = 1.05
            
//            guard let samImage = processSAMImage(from: image) else {
//                print("❌ SAM model returned no mask output.")
//                self.view.showToast(message: "SAM failed to return a mask.")
//                return
//            }
            
            guard let fishImage = extractFish(from: image) else {
                print("❌ SAM model returned no mask output.")
                self.view.showToast(message: "SAM failed to return a mask.")
                return
            }
            saveImageToGallery(fishImage)
            mask = CIImage(image: fishImage)
        }
        
        guard let maskImage = mask else {
            print("❌ maskImage is nil")
            self.view.showToast(message: "Could not extract mask.")

            return
        }
        
        guard let finalImage = image.masked(with: maskImage) else {
            print("❌ image.masked(with:) failed")
            self.view.showToast(message: "Could not isolate fish with mask.")

            return
        }
        saveImageToGallery(finalImage)
        
        guard let mlImage = resizeAndPadMaskImage(finalImage) else {
            print("❌ resizeAndPadMaskImage failed")
            self.view.showToast(message: "Could not classify fish.")

            return
        }
        
        if self.debugMode {
            saveImageToGallery(mlImage)
        }
        
        runTripleTaleModel(on: mlImage) { identifier, confidence, boundingBox in
            self.identifierString = identifier
            self.confidence = confidence
            
            var normalizedVertices: [CGPoint]? = nil
            var verticesAnchors: [ARAnchor] = []

            let userInwardPercent = self.inwardPercent
            while self.inwardPercent <= 40.0 {
                normalizedVertices = findEllipseVertices(from: image, for: 1.0, inward: self.inwardPercent, maskImage: maskImage, debug: self.debugMode)

                if let vertices = normalizedVertices {
                    verticesAnchors = getVertices(self.sceneView, vertices, image.size)
                    if !self.isFacingForward || areAnchorHeightsWithinTolerance(verticesAnchors) {
                        break
                    }
                }

                self.inwardPercent += 5.0
            }

            if verticesAnchors.count < 4 {
                
                // reset scaling
                self.inwardPercent = userInwardPercent

                // Reset AR session to recover from potential raycast/tracking issues
                self.startSession()

                DispatchQueue.main.async {
                    self.showPopupMessage(title: "Error", message: "Could not find tips. Please try again.")
                    completion()
                }
                return
            }
            
    //        verticesAnchors = backProjectAnchorsToSameDepth(anchors: verticesAnchors, queries: verticesQueries)

            var (width, length) = measureVertices(verticesAnchors)
            let height: Float = 0.0
            
            print("measurements: width: \(width), height: \(length)")
            if width > length {
                DispatchQueue.main.async {
                    self.showPopupMessage(title: "Error", message: "Measurement error. Please try again.")
                    completion()
                }
                return
            }
            
            length *= Float(1.0 / (1.0 - self.inwardPercent/100.0))
            width *= Float(1.0 / (1.0 - self.inwardPercent/100.0))

            length *= Float(self.lengthScale)
            width *= Float(self.widthScale)
            
            let girth = width * Float(self.bodyRatio)

            let (weightInLb, widthInInches, lengthInInches, heightInInches, girthInInches) =
                calculateWeight(width, length, height, girth, self.scaleFactor)

            let imageOrientation = uiImageOrientation(from: self.deviceOrientation)
            let displayImage = UIImage(cgImage: image.cgImage!, scale: image.scale, orientation: imageOrientation)
            
            let popUpOrientation = popUpImageOrientation(from: self.deviceOrientation)
            if let combinedImage = generateResultImage(displayImage, nil, widthInInches, lengthInInches, heightInInches, girthInInches, weightInLb, self.identifierString, debug: self.debugMode) {
                self.showImagePopup(combinedImage: combinedImage, orientation:popUpOrientation)
                
                saveImageToGallery(combinedImage)
            } else {
                self.view.showToast(message: "Could not isolate fish from scene, too much clutter!")
            }
            
            // reset scaling
            self.inwardPercent = userInwardPercent

            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    // Function to create and add the camera button
    private func setupCameraButton() {
        let button = UIButton(frame: CGRect(x: (view.bounds.width - 70)/2, y: view.bounds.height - 150, width: 70, height: 70))
        button.backgroundColor = .white
        button.layer.cornerRadius = 35
        button.clipsToBounds = true

        // Set the button images for different states
        button.setImage(UIImage(named: "measure"), for: .normal)
        button.setImage(UIImage(named: "pressed"), for: .highlighted)

        button.imageView?.contentMode = .scaleAspectFill

        button.isEnabled = false // Start disabled
        button.alpha = 0.5 // Visually indicate the disabled state

        button.addTarget(self, action: #selector(handleCameraButtonPress), for: .touchUpInside)

        view.addSubview(button)
        self.cameraButton = button
    }

    private func setupClassifierLabel() {
        let iconSize: CGFloat = 50
        let spacing: CGFloat = 8

        // Label: height matches icon, text vertically centered, large Georgia font
        let labelHeight = iconSize
        let labelY: CGFloat = 70
        let label = UILabel(frame: CGRect(x: 20 + iconSize + spacing, y: labelY, width: 260, height: labelHeight))
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.0)
        label.font = UIFont(name: "Futura-Bold", size: 20)
        label.textAlignment = .left
        label.text = ""
        label.adjustsFontSizeToFitWidth = true
        label.baselineAdjustment = .alignCenters
        label.numberOfLines = 1
        label.contentMode = .center
        label.clipsToBounds = true
        view.addSubview(label)
        self.classifierLabel = label
    }
    
    func createCornerView(withSize size: CGFloat, backgroundColor: UIColor = .clear) {
        let cornerView = UIView()
        cornerView.backgroundColor = backgroundColor
        
        // Set the frame to place the view near the bottom left corner
        let xPosition: CGFloat = 20 // Adjust as needed
        let yPosition: CGFloat = view.bounds.height - size - 20 // Adjust as needed
        cornerView.frame = CGRect(x: xPosition, y: yPosition, width: size, height: size)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        cornerView.addGestureRecognizer(tapGesture)

        view.addSubview(cornerView)
    }
    
    func createDebugCornerView(withSize size: CGFloat, backgroundColor: UIColor = .clear) {
        let cornerView = UIView()
        cornerView.backgroundColor = backgroundColor
        
        // Set the frame to place the view near the bottom left corner
        let xPosition: CGFloat = view.bounds.width - size - 20 // Adjust as needed
        let yPosition: CGFloat = view.bounds.height - size - 20 // Adjust as needed
        cornerView.frame = CGRect(x: xPosition, y: yPosition, width: size, height: size)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDebugGesture))
        cornerView.addGestureRecognizer(tapGesture)

        view.addSubview(cornerView)
    }
    
    func startSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .camera // Ensures detected plane aligns with camera
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true // Helps in low-light conditions
        configuration.isAutoFocusEnabled = true // Enable auto-focus for better tracking stability

        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func captureFrameAsUIImage(from arSCNView: ARSCNView) -> UIImage? {
        // Capture the current view as a UIImage
        let image = arSCNView.snapshot()
        return image
    }
    
    func captureRawCameraImage(from arSCNView: ARSCNView) -> UIImage? {
        guard let pixelBuffer = arSCNView.session.currentFrame?.capturedImage else {
            print("❌ Failed to get captured image from current AR frame.")
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("❌ Failed to create CGImage from CIImage.")
            return nil
        }

        let rawImage = UIImage(cgImage: cgImage)
        
        // Always rotate 90 degrees clockwise to match screen
        return rawImage.rotate(radians: .pi / 2)
    }
    
    // This method is called whenever an ARAnchor is added to the session
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard !(anchor is ARPlaneAnchor) else { return }

        // Add a red sphere for all other anchors
        let sphere = SCNSphere(radius: 0.005)
        sphere.firstMaterial?.diffuse.contents = UIColor.red
        sphere.firstMaterial?.specular.contents = UIColor.white // Adds highlight
        sphere.firstMaterial?.lightingModel = .blinn // or .phong for more realism

        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.isHidden = !debugMode

        node.addChildNode(sphereNode)
        debugNodes.append(sphereNode)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Limit to ~1 inference per second
        guard time - lastMLTimestamp > 1.0 else { return }

        guard !isProcessingML,
              let frame = sceneView.session.currentFrame,
              case .normal = frame.camera.trackingState else {
            return
        }

        let pixelBuffer = frame.capturedImage
        isProcessingML = true
        lastMLTimestamp = time

        // Optional: Save image for inspection
        self.currentBuffer = pixelBuffer

//        detectCurrentImage()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("Session error: \(error.localizedDescription)")
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateCameraButtonState()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        print("Frame updated at: \(frame.timestamp)")
    }

    
    private func updateCameraButtonState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let isTrackingNormal = self.sceneView.session.currentFrame?.camera.trackingState == .normal

            if isTrackingNormal {
                self.cameraButton?.isEnabled = true
                self.cameraButton?.alpha = 1.0
            } else {
                print("tracking: \(isTrackingNormal)")
                self.cameraButton?.isEnabled = false
                self.cameraButton?.alpha = 0.5
            }
        }
    }
    
    private func startMotionTracking() {
        guard motionManager.isDeviceMotionAvailable else {
            print("⚠️ Device Motion not available")
            return
        }

        motionManager.deviceMotionUpdateInterval = 0.5 // Update every 0.5 sec
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }

            let currentPitch = motion.attitude.pitch * (180.0 / .pi) // Convert to degrees
            let currentRoll = motion.attitude.roll * (180.0 / .pi)

            self.isFacingForward = abs(currentPitch) > 60 || abs(currentRoll) > 60
        }
    }
    
    // 📌 Helper function to calculate distance from camera to plane
    func handleClassificationResult(identifier: String, confidence: VNConfidence, boundingBox: CGRect?) {
        // Update your UI or perform other actions with the identifier, confidence, and boundingBox
        self.identifierString = identifier
        self.confidence = confidence
        self.boundingBox = boundingBox ?? .zero
        
        self.displayClassifierResults()
    }
    
    
    // Show the classification results in the UI.
    private func displayClassifierResults() {
        var message: String
        if self.identifierString.isEmpty || self.confidence < 0.01 {
            message = "None"
        } else {
            message = String(format: "%@", self.identifierString)
        }

        classifierLabel?.text = message
        statusViewController?.showMessage(message)

        // Icon handling
//        let iconSize: CGFloat = 50
//        let iconFrame = CGRect(x: 20, y: 70, width: iconSize, height: iconSize)

//        if let existingIcon = view.viewWithTag(9999) as? UIImageView {
//            existingIcon.image = UIImage(named: self.identifierString)
//        } else {
//            let iconImageView = UIImageView(image: UIImage(named: self.identifierString))
//            iconImageView.frame = iconFrame
//            iconImageView.contentMode = .scaleAspectFit
//            iconImageView.tag = 9999
//            iconImageView.isHidden = true
//            view.addSubview(iconImageView)
//        }
    }
    
    private func detectCurrentImage() {
        let orientation = CGImagePropertyOrientation(UIDevice.current.orientation)
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentBuffer!, orientation: orientation)
        
        visionQueue.async {
            defer {
                self.currentBuffer = nil
                self.isProcessingML = false // ✅ Release the lock
            }

            do {
                try requestHandler.perform([self.mlRequest])
            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
    }
    
    private func restartSession() {
        statusViewController?.cancelAllScheduledMessages()
        statusViewController?.showMessage("RESTARTING SESSION")
 
        anchorLabels = [UUID: String]()
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .camera
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        configuration.isAutoFocusEnabled = true
        configuration.environmentTexturing = .automatic

        // ✅ Enable scene depth if supported (LiDAR-only)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    private func updateBracketSize() {
        guard let bracketView = bracketView else { return }

//        bracketView.addCircleMarker()
        
        let width = view.bounds.width * self.screenRatio // Example size for not forward-facing, adjust as needed
        let height = width * 16 / 9 // Maintain 9:16 aspect ratio

        let rect = CGRect(origin: CGPoint(x: view.bounds.midX - width / 2, y: view.bounds.midY - height / 2), size: CGSize(width: width, height: height))
        bracketView.updateBracket(rect: rect)
    }
    
    private func showLoadingOverlay() {
        // Create splash/loading image view
        let loadingImageView = UIImageView(frame: view.bounds)
        loadingImageView.contentMode = .scaleAspectFill
        loadingImageView.image = UIImage(named: "background") // Replace with your asset name
        loadingImageView.tag = 3030
        view.addSubview(loadingImageView)
        
        // Add activity indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.center = CGPoint(x: self.view.bounds.midX, y: self.view.bounds.midY)
        activityIndicator.color = .white
        activityIndicator.tag = 2025
        activityIndicator.startAnimating()
        self.view.addSubview(activityIndicator)
        
        // Add loading label
        let loadingLabel = UILabel(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 40))
        loadingLabel.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY + 60)
        loadingLabel.textAlignment = .center
        loadingLabel.textColor = .white
        loadingLabel.font = UIFont(name: "Futura-Bold", size: 20)
        loadingLabel.text = "Loading AI Models…"
        loadingLabel.tag = 4040
        view.addSubview(loadingLabel)
        
        UIView.animate(withDuration: 1.0,
                       delay: 0,
                       options: [.repeat, .autoreverse, .allowUserInteraction],
                       animations: {
            loadingLabel.alpha = 0.3
        }, completion: nil)
    }
    
    private func hideLoadingOverlay() {
        [2025, 3030, 4040].forEach { tag in
            if let view = self.view.viewWithTag(tag) {
                view.removeFromSuperview()
            }
        }
    }
    
    /// Run the TripleTale CoreML model on a UIImage and return the identifier, confidence, and bounding box.
    /// This is useful for external or test calls.
    func runTripleTaleModel(on image: UIImage, completion: @escaping (String, VNConfidence, CGRect?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion("", 0, nil)
            return
        }

        let ciImage = CIImage(cgImage: cgImage)
        let orientation = CGImagePropertyOrientation(UIDevice.current.orientation)

        let requestHandler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation)

        visionQueue.async {
            do {
                let request = VNCoreMLRequest(model: try VNCoreMLModel(for: self.tripleTaleModel.model)) { request, error in
                    if let result = processObservations(for: request, error: error) {
                        DispatchQueue.main.async {
                            completion(result.identifierString, result.confidence, result.boundingBox)
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion("", 0, nil)
                        }
                    }
                }

                try requestHandler.perform([request])
            } catch {
                print("❌ Error running TripleTale model: \(error)")
                DispatchQueue.main.async {
                    completion("", 0, nil)
                }
            }
        }
    }
    
    
}
