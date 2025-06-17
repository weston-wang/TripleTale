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
    
    private var isSessionStabilized = false
    
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
                if let result = MLUtils.processObservations(for: request, error: error) {
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
    
    func extractFish(from inputImage: UIImage) -> UIImage? {
        do {
            // Resize image to 256x256 (required by SAM2 Tiny)
            guard let resizedImage = MLUtils.resizeImageForModel(inputImage, width: 416, height: 416) ,
                  let pixelBuffer = ImageConverter.pixelBuffer(from: resizedImage) else {
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

            if let maskImage = MLUtils.postprocessFishMask(from: maskArray, originalSize: inputImage.size) {
                let originalSize = inputImage.size
                if let resizedMask = ImageConverter.resizeMaskToOriginal(maskImage: maskImage, targetSize: originalSize) {
                    return resizedMask
                }
            }
            
            return nil

        } catch {
            print("❌ Failed to load SAM models: \(error)")
            return nil
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("has lidar: \(self.hasLiDAR)")
        
        sceneView = ARSCNView(frame: self.view.frame)
        sceneView.delegate = self
        view.addSubview(sceneView)

        if !hasLiDAR {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "iPhone Pro Required", message: "This app requires an iPhone Pro device. Regular iPhone support will be enabled in future updates.", preferredStyle: .alert)

                // Normal OK action (will exit if tapped once)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                    exit(0)
                }))
                
                self.present(alert, animated: true)
            }
        }

        // Create splash/loading image view
        showLoadingOverlay()
        
//        Task {
//
//        }
        
        Task { @MainActor in
            await self.subscriptionManager.loadProducts()
            await self.subscriptionManager.updateSubscriptionStatus()
            
            DispatchQueue.main.async {
                InAppPurchaseManager.printActiveEntitlements()
            }
            
            _ = self.fishExtractor  // Load 1st model

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

                if !self.subscriptionManager.isSubscribed {
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
//                    alert.addAction(UIAlertAction(title: "Later", style: .cancel, handler: nil))
//                    self.present(alert, animated: true, completion: nil)
                    self.showSubscriptionOverlay()
                }
                
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

                // Force re-check after purchase
                print("🔁 Subscription status after purchase: \(subscriptionManager.isSubscribed)")


                if subscriptionManager.isSubscribed {
                    if let overlay = self.view.viewWithTag(9090) {
                        overlay.removeFromSuperview()
                    }
                    if let restoreButton = self.view.viewWithTag(9191) {
                        restoreButton.removeFromSuperview()
                    }
                } else {
                    self.view.showToast(message: "Subscription failed or was not verified.")
                }
            } else {
                self.view.showToast(message: "No subscription product available. Try again later.")
            }
        }
    }
    
    private func setupRestoreButton() {
        let button = UIButton(type: .system)
        button.setTitle("Restore Purchase", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 12)
        button.backgroundColor = UIColor(red: 0.0, green: 0.2, blue: 0.3, alpha: 1.0)
        button.layer.cornerRadius = 8
        button.frame = CGRect(x: view.bounds.width - 140, y: 50, width: 120, height: 30)
        button.tag = 9191
        button.addTarget(self, action: #selector(handleRestoreButton), for: .touchUpInside)
        view.addSubview(button)
    }

    @objc private func handleRestoreButton() {
        Task {
            await subscriptionManager.restorePurchases()
            if subscriptionManager.isSubscribed {
                self.view.showToast(message: "✅ Subscription restored!")
            } else {
                self.view.showToast(message: "No active subscription found.")
            }
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
        
        self.lengthScale = isFacingForward ? 1.05 : 1.0
        self.widthScale = isFacingForward ? 1.05 : 1.0
        
        guard let fishImage = extractFish(from: image) else {
            print("❌ Fish model returned no mask output.")
            self.view.showToast(message: "SAM failed to return a mask.")
            return
        }
                
        guard let maskImage = CIImage(image: fishImage) else {
            print("❌ maskImage is nil")
            self.view.showToast(message: "Could not extract mask.")

            return
        }
        
        guard let finalImage = image.masked(with: maskImage) else {
            print("❌ image.masked(with:) failed")
            self.view.showToast(message: "Could not isolate fish with mask.")

            return
        }
        
        guard let mlImage = ImageConverter.resizeAndPadMaskImage(finalImage) else {
            print("❌ resizeAndPadMaskImage failed")
            self.view.showToast(message: "Could not classify fish.")

            return
        }
        
        if self.debugMode {
            GalleryManager.saveImageToGallery(mlImage)
        }
        
        runTripleTaleModel(on: mlImage) { identifier, confidence, boundingBox in
            self.identifierString = identifier
            self.confidence = confidence
                            
            var verticesAnchors: [ARAnchor] = []
                
            if let normalizedVertices = findEllipseVertices(from: image, for: 1.0, inward: self.inwardPercent, maskImage: maskImage, debug: self.debugMode) {
                verticesAnchors = AnchorUtils.getVertices(self.sceneView, normalizedVertices, image.size)
                
                print("found \(verticesAnchors.count) vertices anchors")
            }
            
            
            if verticesAnchors.count < 4 {
                // Reset AR session to recover from potential raycast/tracking issues
                self.restartSession()

                DispatchQueue.main.async {
                    self.showPopupMessage(title: "Error", message: "Could not find tips. Please try again.")
                    completion()
                }
                return
            }
            
            var (width, length) = MeasurementUtils.measureVertices(verticesAnchors)
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
            MeasurementUtils.calculateWeight(width, length, height, girth, self.scaleFactor)

            let imageOrientation = OrientationUtils.uiImageOrientation(from: self.deviceOrientation)
            let displayImage = UIImage(cgImage: image.cgImage!, scale: image.scale, orientation: imageOrientation)
            
            let popUpOrientation = OrientationUtils.popUpImageOrientation(from: self.deviceOrientation)
            if let combinedImage = generateResultImage(displayImage, nil, widthInInches, lengthInInches, heightInInches, girthInInches, weightInLb, self.identifierString, debug: self.debugMode) {
                self.showImagePopup(combinedImage: combinedImage, orientation:popUpOrientation)
                
                GalleryManager.saveImageToGallery(combinedImage)
            } else {
                self.view.showToast(message: "Could not isolate fish from scene, too much clutter!")
            }

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
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.isLightEstimationEnabled = true // Helps in low-light conditions
        configuration.isAutoFocusEnabled = true // Enable auto-focus for better tracking stability

        // ✅ Enable scene depth if supported (LiDAR-only)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
        
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        self.isSessionStabilized = true
        self.updateCameraButtonState() // if button relies on tracking state too
    
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
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.isLightEstimationEnabled = true
        configuration.isAutoFocusEnabled = true
        configuration.environmentTexturing = .automatic

        // ✅ Enable scene depth if supported (LiDAR-only)
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                configuration.frameSemantics.insert(.smoothedSceneDepth)
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
    
    // MARK: - Subscription Overlay
    private func showSubscriptionOverlay() {
        let overlayView = UIView(frame: self.view.bounds)
        overlayView.backgroundColor = UIColor(red: 0.0, green: 0.1, blue: 0.2, alpha: 1.0) // Dark navy
        overlayView.tag = 9090 // Tag to identify the subscription overlay

        let backgroundImage = UIImageView(frame: overlayView.bounds)
        backgroundImage.contentMode = .scaleAspectFill
        backgroundImage.image = UIImage(named: "subscription") // Replace with your actual image name
        overlayView.addSubview(backgroundImage)

        // Move messageLabel near the bottom of the screen
        let messageLabel = UILabel(frame: CGRect(x: 50, y: self.view.bounds.height - 210, width: self.view.bounds.width - 100, height: 80))
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        let title = "TripleTale Subscription:\n"
        let description = "Unlock fish classification, measurement, and weight"

        let attributedText = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: UIFont(name: "Futura-Bold", size: 20) as Any,
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor(red: 0.0, green: 0.2, blue: 0.3, alpha: 1.0),
                .strokeWidth: -6
            ])

        let descriptionText = NSAttributedString(
            string: description,
            attributes: [
                .font: UIFont(name: "Futura-Bold", size: 16) as Any,
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor(red: 0.0, green: 0.2, blue: 0.3, alpha: 1.0),
                .strokeWidth: -3
            ])

        attributedText.append(descriptionText)
        messageLabel.attributedText = attributedText
        overlayView.addSubview(messageLabel)

        // Move subscribeButton near the bottom and restyle
        let subscribeButton = UIButton(type: .system)
        subscribeButton.setTitle("Subscribe for $9.99/month", for: .normal)
        subscribeButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        subscribeButton.setTitleColor(UIColor(red: 0.0, green: 0.4, blue: 0.4, alpha: 1.0), for: .normal) // Deep teal
        subscribeButton.backgroundColor = .white
        subscribeButton.layer.borderColor = UIColor(red: 0.0, green: 0.2, blue: 0.3, alpha: 1.0).cgColor // Navy
        subscribeButton.layer.borderWidth = 2
        subscribeButton.layer.cornerRadius = 10
        subscribeButton.frame = CGRect(x: 40, y: self.view.bounds.height - 120, width: self.view.bounds.width - 80, height: 50)
        subscribeButton.addTarget(self, action: #selector(self.handleSubscribeButton), for: .touchUpInside)
        overlayView.addSubview(subscribeButton)

        // Add Privacy Policy and Terms of Use buttons at the bottom
        let buttonHeight: CGFloat = 30
        let buttonSpacing: CGFloat = 10
        let buttonWidth = (self.view.bounds.width - 60) / 2

        let privacyButton = UIButton(type: .system)
        privacyButton.setTitle("Privacy Policy", for: .normal)
        privacyButton.setTitleColor(.white, for: .normal)
        privacyButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        privacyButton.frame = CGRect(x: 50, y: self.view.bounds.height - 50, width: buttonWidth, height: buttonHeight)
        privacyButton.addTarget(self, action: #selector(openPrivacyPolicy), for: .touchUpInside)
        overlayView.addSubview(privacyButton)

        let termsButton = UIButton(type: .system)
        termsButton.setTitle("App EULA", for: .normal)
        termsButton.setTitleColor(.white, for: .normal)
        termsButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        termsButton.frame = CGRect(x: self.view.bounds.width - buttonWidth - 50, y: self.view.bounds.height - 50, width: buttonWidth, height: buttonHeight)
        termsButton.addTarget(self, action: #selector(openTermsOfUse), for: .touchUpInside)
        overlayView.addSubview(termsButton)

        self.view.addSubview(overlayView)
        
        self.setupRestoreButton()
    }

    @objc private func openPrivacyPolicy() {
        if let url = URL(string: "https://www.tripletale.net/privacy-policy") {
            UIApplication.shared.open(url)
        }
    }

    @objc private func openTermsOfUse() {
        if let url = URL(string: "https://www.tripletale.net/terms-of-use") {
            UIApplication.shared.open(url)
        }
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
                    if let result = MLUtils.processObservations(for: request, error: error) {
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
