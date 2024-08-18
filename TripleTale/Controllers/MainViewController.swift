/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the ARKitVision sample.
*/

import UIKit
import SpriteKit
import ARKit
import Vision
import CoreMotion

class MainViewController: UIViewController, ARSKViewDelegate, ARSessionDelegate {
    
    @IBOutlet weak var sceneView: ARSKView!
    
    var bracketView: BracketView?
    
    var scaleFactor: Double = 500.0
    var lengthNudge: Double = 1.2
    var widthNudge: Double = 1.2

    let isMLDetection = false
    
    let motionManager = CMMotionManager()
    private var isForwardFacing = false
    
    private var imagePortion: CGFloat = 1.0

    private var freezeButton: UIButton?
    private var isFrozen = false
    
    private var tapCounter = 0
    
    private var saveImage: UIImage?
    private var depthImage: UIImage?
    private var depthMask: UIImage?

    private var rotationMatrix: simd_float4x4?
    
    // Labels for classified objects by ARAnchor UUID
    private var anchorLabels = [UUID: String]()
    
    private var anglesString: String?

    // Classification results
    private var identifierString = ""
    private var confidence: VNConfidence = 0.0
    private var boundingBox: CGRect?
    
    // The pixel buffer being held for analysis; used to serialize Vision requests.
    private var currentBuffer: CVPixelBuffer?
    
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
    
    // The view controller that displays the status and "restart experience" UI.
    private lazy var statusViewController: StatusViewController = {
        return children.lazy.compactMap({ $0 as? StatusViewController }).first!
    }()
    
    @objc private func handleTapGesture() {
        tapCounter += 1
        
        if tapCounter == 3 {
            tapCounter = 0 // Reset counter after showing the popup
            
            // Show the input popup
            showInputPopup(title: "Developer Mode", message: "Update Values Below", placeholders: [
                "Weight Scale: \(self.scaleFactor)",
                "Length Scale: \(self.lengthNudge)",
                "Width Scale: \(self.widthNudge)"
            ]) { inputs in
                // Handle the user inputs here
                if let value1 = inputs[0] {
                    self.scaleFactor = value1
                }
                
                if let value2 = inputs[1] {
                    self.lengthNudge = value2
                }
                
                if let value3 = inputs[2] {
                    self.widthNudge = value3
                }
            }
        }
    }
    
    // MARK: - Main logic
    @objc func toggleFreeze() {
        DispatchQueue.main.async {
            self.isFrozen.toggle()  // Toggle the state of isFrozen
            
            let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
            feedbackGenerator.prepare()
            feedbackGenerator.impactOccurred()

            if self.isFrozen {
                if let inputImage = self.saveImage {
//                    self.sceneView.session.add(anchor: centroidAboveAnchor)
//                    self.anchorLabels[centroidAboveAnchor.identifier] = "above"

                    var weightInLb = Measurement(value: 0, unit: UnitMass.pounds)
                    var widthInInches = Measurement(value: 0, unit: UnitLength.inches)
                    var lengthInInches = Measurement(value: 0, unit: UnitLength.inches)
                    var heightInInches = Measurement(value: 0, unit: UnitLength.inches)
                    var circumferenceInInches = Measurement(value: 0, unit: UnitLength.inches)

                    if !self.isForwardFacing {
                        if let normalizedVertices = findEllipseVertices(from: inputImage, for: self.imagePortion, with: self.rotationMatrix!) {
                            let (verticesAnchors, centroidAboveAnchor, centroidBelowAnchor, cornerAnchors) = buildRealWorldVerticesAnchors(self.sceneView, normalizedVertices, inputImage.size)
                            
                            var (width, length, height) = measureVertices(verticesAnchors, cornerAnchors, centroidAboveAnchor, centroidBelowAnchor)
                            
                            length = length * Float(self.lengthNudge)
                            width = width * Float(self.widthNudge)
                            
                            let circumference = calculateCircumference(majorAxis: width, minorAxis: height)
                            
                            (weightInLb, widthInInches, lengthInInches, heightInInches, circumferenceInInches) = calculateWeight(width, length, height, circumference, self.scaleFactor)
                        }
                    } else {
//                        let blurredImage = inputImage.applyBlurOutsideEllipse(portion: self.imagePortion)
                        saveImageToGallery(self.depthImage!)
//                        saveImageToGallery(self.depthMask!)

                        let testVertices = findEllipseVerticesVertical(from: self.depthImage!, for: self.imagePortion, with: self.rotationMatrix!)
                        let (testVerticesAnchors, _, _, _) = buildRealWorldVerticesAnchors(self.sceneView, testVertices!, inputImage.size)
                        
                        let forkLenght = calculateDistanceBetweenAnchors2DVert(anchor1: testVerticesAnchors[0], anchor2: testVerticesAnchors[2])

                        (weightInLb, lengthInInches) = calculateWeightFromFork(forkLenght, self.identifierString)
                    }
                    
                    if let combinedImage = generateResultImage(inputImage, nil , widthInInches, lengthInInches, heightInInches, circumferenceInInches, weightInLb, self.identifierString) {
                        self.showImagePopup(combinedImage: combinedImage)
                    } else {
                        self.view.showToast(message: "Could not isolate fish from scene, too much clutter!")
                    }
                }
                
                self.isFrozen.toggle()
            }
        }
    }

    // MARK: - View controller lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Check if the accelerometer is available
        guard motionManager.isDeviceMotionAvailable else {
            print("Motion Sensor is not available")
            return
        }
        
        // Start Device Motion Updates
        motionManager.startDeviceMotionUpdates(to: .main) { (motion, error) in
            guard let motion = motion else { return }
            
            // Access device motion data (includes attitude, gravity, etc.)
            let roll = motion.attitude.roll
            let pitch = motion.attitude.pitch
            let yaw = motion.attitude.yaw
            
            // Convert to degrees if needed
            let rollDegrees = roll * 180 / .pi
            let pitchDegrees = pitch * 180 / .pi
            let yawDegrees = yaw * 180 / .pi
            
            self.anglesString = "Device Motion - Roll: \(rollDegrees)°, Pitch: \(pitchDegrees)°, Yaw: \(yawDegrees)°"
            
            let previousFacing = self.isForwardFacing
            self.isForwardFacing = self.detectOrientation(attitude: motion.attitude)
            
            if self.isForwardFacing != previousFacing {
                
                // Update the bracket size based on the current state
                self.updateBracketSize()
            }
        }
        
        // Configure and present the SpriteKit scene that draws overlay content.
        let overlayScene = SKScene()
        overlayScene.scaleMode = .aspectFill
        sceneView.delegate = self
        sceneView.presentScene(overlayScene)
        sceneView.session.delegate = self
        
        // Add the bracket view to the main view
        bracketView = BracketView(frame: view.bounds)
        bracketView?.isUserInteractionEnabled = false // Make sure it doesn't intercept touch events
        view.addSubview(bracketView!)

        // Add the freeze button and other UI elements
        freezeButton = createFreezeButton()
        view.addSubview(freezeButton!)
        
        // Hook up status view controller callback.
        statusViewController.restartExperienceHandler = { [unowned self] in
            self.restartSession()
        }
        
        // Initial bracket update
        updateBracketSize()
        
        // Create a transparent view for the bottom left corner
        let cornerView = UIView()
        cornerView.translatesAutoresizingMaskIntoConstraints = false
        cornerView.backgroundColor = UIColor.clear
        view.addSubview(cornerView)
        
        // Set constraints to position the view in the bottom left corner
        NSLayoutConstraint.activate([
            cornerView.widthAnchor.constraint(equalToConstant: 100), // Adjust size as needed
            cornerView.heightAnchor.constraint(equalToConstant: 100), // Adjust size as needed
            cornerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            cornerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        ])
        
        // Add tap gesture recognizer to the corner view
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        cornerView.addGestureRecognizer(tapGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        startPlaneDetection()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        bracketView?.frame = view.bounds
        updateBracketSize()
    }
    
    // MARK: - Helpers
    func updateBracketSize() {
        guard let bracketView = bracketView else { return }
        
        // Define different sizes for forward-facing and not forward-facing
        let width: CGFloat
        let height: CGFloat
        if isForwardFacing {
            imagePortion = 0.6
            
            width = view.bounds.width * imagePortion // Example size for forward-facing, adjust as needed
            height = width * 16 / 9 // Maintain 9:16 aspect ratio
        } else {
            imagePortion = 0.85
            
            width = view.bounds.width * imagePortion // Example size for not forward-facing, adjust as needed
            height = width * 16 / 9 // Maintain 9:16 aspect ratio
        }
        
        let rect = CGRect(origin: CGPoint(x: view.bounds.midX - width / 2, y: view.bounds.midY - height / 2), size: CGSize(width: width, height: height))
        bracketView.updateBracket(rect: rect)
    }
    
    func createFreezeButton() -> UIButton {
        let button = UIButton(frame: CGRect(x: (view.bounds.width - 70)/2, y: view.bounds.height - 150, width: 70, height: 70))
        button.backgroundColor = .white
        button.layer.cornerRadius = 35
        button.clipsToBounds = true

        // Set the button images for different states
        button.setImage(UIImage(named: "measure"), for: .normal)
        button.setImage(UIImage(named: "pressed"), for: .highlighted)

        button.imageView?.contentMode = .scaleAspectFill

        button.isHidden = true

        button.addTarget(self, action: #selector(toggleFreeze), for: .touchUpInside)
        return button
    }
    
    func startPlaneDetection() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        
        // Enable depth data (only works on LiDAR-equipped devices)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        } else {
            print("Device does not support scene depth")
        }
        
        sceneView.session.run(configuration)
    }

    func detectOrientation(attitude: CMAttitude) -> Bool {
        return  attitude.pitch * 180 / .pi > 60.0
    }
    
    // MARK: - ARSessionDelegate
    
    // Pass camera frames received from ARKit to Vision (when not already processing one)
    /// - Tag: ConsumeARFrames
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Do not enqueue other buffers for processing while another Vision task is still running.
        // The camera stream has only a finite amount of buffers available; holding too many buffers for analysis would starve the camera.
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else {
            return
        }
        
        // Retain the image buffer for Vision processing.
        self.currentBuffer = frame.capturedImage
        
        // Retain rotation information
        self.rotationMatrix = frame.camera.transform
                
        
        // Optional: Process depth data if available
//        if let sceneDepth = frame.sceneDepth {
//            // Convert the depth map to a UIImage
////            let depthMap = applyNonLinearDepthTransformation(depthMap: sceneDepth.depthMap)
//
//            // You could store or process the depth data here if needed
////            self.depthMask = depthMapToBinaryMask(depthPixelBuffer: sceneDepth.depthMap)
//            self.depthImage = pixelBufferToUIImage(pixelBuffer: sceneDepth.depthMap)
//        }     // Use person segmentation with depth for non-LiDAR devices
//        
//        else if let segmentationBuffer = frame.estimatedDepthData {
//            self.depthImage = pixelBufferToUIImage(pixelBuffer: segmentationBuffer)
//        }
        
        
        self.saveImage = pixelBufferToUIImage(pixelBuffer: self.currentBuffer!)
        
        detectCurrentImage()
    }
    
    // MARK: - Vision classification
    func handleResult(identifier: String, confidence: VNConfidence, boundingBox: CGRect?) {
        // Update your UI or perform other actions with the identifier, confidence, and boundingBox
        self.identifierString = identifier
        self.confidence = confidence
        self.boundingBox = boundingBox ?? .zero
        
        self.displayClassifierResults()
    }
    
    private lazy var mlRequest: VNCoreMLRequest = {
        do {
            // Instantiate the model from its generated Swift class.
            let model = try VNCoreMLModel(for: tripleTaleModel.model)
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                if let result = processObservations(for: request, error: error) {
                    DispatchQueue.main.async {
                        self?.handleResult(identifier: result.identifierString, confidence: result.confidence, boundingBox: result.boundingBox)
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.handleResult(identifier: "", confidence: 0, boundingBox: nil)
                    }
                }
            })

            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    private func detectCurrentImage() {
        // Most computer vision tasks are not rotation agnostic so it is important to pass in the orientation of the image with respect to device.
        let orientation = CGImagePropertyOrientation(UIDevice.current.orientation)
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentBuffer!, orientation: orientation)
        visionQueue.async {
            do {
                // Release the pixel buffer when done, allowing the next buffer to be processed.
                defer { self.currentBuffer = nil }
                try requestHandler.perform([self.mlRequest])
            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
    }

    // Show the classification results in the UI.
    private func displayClassifierResults() {
        guard !self.identifierString.isEmpty else {
            freezeButton?.isHidden = true
            return // No object was classified.
        }
        freezeButton?.isHidden = false

//        let message = String(format: "Detected \(self.identifierString) with %.2f", self.confidence * 100) + "% confidence"
//        statusViewController.showMessage(message)
        
        statusViewController.showMessage(self.anglesString!)

    }
    
    // MARK: - Tap gesture handler & ARSKViewDelegate

    // When an anchor is added, provide a SpriteKit node for it and set its text to the classification label.
    /// - Tag: UpdateARContent
    func view(_ view: ARSKView, didAdd node: SKNode, for anchor: ARAnchor) {
        // Check if the anchor is an ARPlaneAnchor
        if anchor is ARPlaneAnchor {
            print("A plane anchor was added. Ignoring label assignment for plane anchors.")
            return
        } else if anchor is ARBodyAnchor {
            print("A body anchor was added. Ignoring label assignment for plane anchors.")
            return
        }
        
        guard let labelText = anchorLabels[anchor.identifier] else {
            fatalError("missing expected associated label for anchor")
        }
        let label = TemplateLabelNode(text: labelText)
        node.addChild(label)
    }
    
    // MARK: - AR Session Handling
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
//        statusViewController.showTrackingQualityInfo(for: camera.trackingState, autoHide: true)
        
        switch camera.trackingState {
        case .notAvailable, .limited:
            statusViewController.escalateFeedback(for: camera.trackingState, inSeconds: 3.0)
        case .normal:
            statusViewController.cancelScheduledMessage(for: .trackingStateEscalation)
            // Unhide content after successful relocalization.
            setOverlaysHidden(false)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Filter out optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            self.displayErrorMessage(title: "The AR session failed.", message: errorMessage)
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        setOverlaysHidden(true)
    }
    
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        /*
         Allow the session to attempt to resume after an interruption.
         This process may not succeed, so the app must be prepared
         to reset the session if the relocalizing status continues
         for a long time -- see `escalateFeedback` in `StatusViewController`.
         */
        return false
    }

    private func setOverlaysHidden(_ shouldHide: Bool) {
        sceneView.scene!.children.forEach { node in
            if shouldHide {
                // Hide overlay content immediately during relocalization.
                node.alpha = 0
            } else {
                // Fade overlay content in after relocalization succeeds.
                node.run(.fadeIn(withDuration: 0.5))
            }
        }
    }

    private func restartSession() {
        statusViewController.cancelAllScheduledMessages()
        statusViewController.showMessage("RESTARTING SESSION")

        anchorLabels = [UUID: String]()
        
        let configuration = ARWorldTrackingConfiguration()
        
        // Enable depth data (only works on LiDAR-equipped devices)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - Error handling
    private func displayErrorMessage(title: String, message: String) {
        // Present an alert informing about the error that has occurred.
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.restartSession()
        }
        alertController.addAction(restartAction)
        present(alertController, animated: true, completion: nil)
    }
}
