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

    var sceneView: ARSCNView!
    var frameCounter = 0

    private var trackingStatusLabel: UILabel!
    
    let motionManager = CMMotionManager()
    var isBoatMode = false // Default to land mode
    var motionHistory: [Double] = [] // Track recent tilt changes
    let motionThreshold = 5.0 // Degrees: sensitivity for boat detection
    let sampleCount = 10 // How many motion samples to analyze

    private var boatAnchor: ARAnchor?
    
    private var planeDetectionTimer: Timer?
    
    private var tapCounter = 0
    private var debugCounter = 0
    
    private var debugNodes: [SCNNode] = []

    var scaleFactor: Double = 500.0
    var lengthNudge: Double = 1.3
    var widthNudge: Double = 1.3
    var heightNudge: Double = 1.4

    private var cameraButton: UIButton?
    private var feedbackLabel: UILabel?
    
    private var bracketView: BracketView?
    private var imagePortion: CGFloat = 1.0
    
    private var firstPlaneAnchor: ARPlaneAnchor?
    private var isGroundPlaneDetected = true

    // The pixel buffer being held for analysis; used to serialize Vision requests.
    private var depthImage: UIImage?
//    private var visionQueue = DispatchQueue(label: "com.tripleTale.visionQueue")

    private var depthQueue = DispatchQueue(label: "com.tripleTale.depthQueue")

    /// The ML model to be used for detection of fish
    private var depthModel: DepthAnythingV2 = {
        do {
            let configuration = MLModelConfiguration()
            return try DepthAnythingV2(configuration: configuration)
        } catch {
            fatalError("Couldn't create DepthAnythingV2 due to: \(error)")
        }
    }()
    
    /// Vision CoreML request for processing depth data
    private lazy var depthRequest: VNCoreMLRequest = {
        do {
            // Instantiate the model from its generated Swift class.
            let model = try VNCoreMLModel(for: depthModel.model)
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error in depth request: \(error)")
                    return
                }
                
                guard let results = request.results as? [VNPixelBufferObservation],
                      let depthMap = results.first?.pixelBuffer else {
                    print("No depth map found")
                    return
                }

                // Convert depth map (CVPixelBuffer) to UIImage
                let depthImage = depthPixelBufferToUIImage(pixelBuffer: depthMap)
                
                // Instead of processing directly, return the depth image through the completion handler
                if let depthImage = depthImage {
                    self.depthCompletionHandler?(depthImage)
                }
            })
            
            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()

    /// Completion handler that will return the depth image
    private var depthCompletionHandler: ((UIImage) -> Void)?

    /// Method to run the depth request on an input UIImage and return the result via completion handler
    func processDepthImage(from inputImage: UIImage, completion: @escaping (UIImage) -> Void) {
        guard let cgImage = inputImage.cgImage else {
            print("Unable to convert UIImage to CGImage")
            return
        }
        
        // Set the completion handler
        self.depthCompletionHandler = completion
        
        // Perform request asynchronously on a background queue
        depthQueue.async { [weak self] in
            guard let self = self else { return }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([self.depthRequest])
            } catch {
                print("Failed to perform depth request: \(error)")
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView = ARSCNView(frame: self.view.frame)
        sceneView.delegate = self
        view.addSubview(sceneView)

        // ✅ Start a stabilization phase before allowing anchors
//        performPreTrackingPhase()
        
        // Add the bracket view to the main view
        bracketView = BracketView(frame: view.bounds)
        bracketView?.isUserInteractionEnabled = false // Make sure it doesn't intercept touch events
        view.addSubview(bracketView!)
        
        // Create a transparent view for the bottom left corner
        createCornerView(withSize: 100)
        
        // Create a transparent view for the bottom right corner
        createDebugCornerView(withSize: 100)
        
        // Call the function to create and add the camera button
        setupCameraButton()

        // Start AR
        startPlaneDetection()

        // Initial bracket update
        updateBracketSize()
        
        // Start checking for boat motion
        startMotionTracking()
        
        // Call this function inside `viewDidLoad()`
        setupTrackingStatusLabel()
    }
    
    @objc private func handleTapGesture() {
        tapCounter += 1
        
        if tapCounter == 3 {
            tapCounter = 0 // Reset counter after showing the popup
            
            // Show the input popup
            showInputPopup(title: "Developer Mode", message: "Update Values Below", placeholders: [
                "Weight Scale: \(self.scaleFactor)",
                "Length Scale: \(self.lengthNudge)",
                "Width Scale: \(self.widthNudge)",
                "Height Scale: \(self.heightNudge)"
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
                
                if let value4 = inputs[3] {
                    self.heightNudge = value4
                }
            }
        }
    }
    
    @objc private func handleDebugGesture() {
        debugCounter += 1

        if debugCounter == 3 {
            debugCounter = 0 // Reset counter after activation
            
            // Toggle debug options
            if sceneView.debugOptions.isEmpty {
                // Enable debug mode
                sceneView.debugOptions = [.showFeaturePoints]
//                print("🔍 Debug mode ENABLED")
//                self.showPopupMessage(title: "Debug Mode", message: "Debug mode ENABLED")
                
                for node in debugNodes {
                    node.isHidden = false
                }

            } else {
                // Disable debug mode
                sceneView.debugOptions = []
//                print("🚫 Debug mode DISABLED")
//                self.showPopupMessage(title: "Debug Mode", message: "Debug mode DISABLED")
                
                for node in debugNodes {
                    node.isHidden = true
                }
            }
        }
    }
    
    @objc func handleCameraButtonPress() {
        // Haptic feedback
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()

        // Capture the current frame
        if let image = captureFrameAsUIImage(from: sceneView) {
            calculateAndDisplayWeight(with: image)
            
//            if let inputImage = image.downscale(to: 1280) {
//                let resizedImage = resizeImageForModel(inputImage)
//                processDepthImage(from: resizedImage!) { depthImage in
//                    let resizedDepthImage = resizeDepthMap(depthImage, to: inputImage.size)
//                    
//                    let thresholdedImage = thresholdImage(resizedDepthImage!, threshold: 255 * 0.85)
//                    saveImageToGallery(thresholdedImage!)
//                    saveImageToGallery(resizedDepthImage!)
//                }
//            }
        } else {
            self.view.showToast(message: "Could not capture image from scene!")
        }
    }
    
    @objc private func showPlaneDetectionHint() {
        DispatchQueue.main.async {
            let isLidarAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)

            if !self.isGroundPlaneDetected {
                let message = isLidarAvailable ?
                    "Try slowly moving your phone to help detect the ground." :
                    "Your device doesn't have LiDAR. Try moving the phone more and pointing at a textured surface."

                self.showPopupMessage(title: "Move Your Phone", message: message)
            }
        }
    }
    
    @objc private func showBoatAnchorHint() {
        DispatchQueue.main.async {
            self.showPopupMessage(title: "Move Your Phone", message: "Try slowly moving your phone to help detect stable points on the boat.")
        }
    }
    
//    func performPreTrackingPhase() {
//        let config = ARWorldTrackingConfiguration()
//        config.planeDetection = [.horizontal]
//        config.isLightEstimationEnabled = true
////        config.worldAlignment = .gravityAndHeading
//        config.isAutoFocusEnabled = true
//
//        // ✅ Step 1: Reset tracking & remove previous anchors to force rescan
//        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
//
//        DispatchQueue.global(qos: .userInitiated).async {
//            var featurePointCount = 0
//            var attempts = 0
//
//            // ✅ Step 2: Wait until ARKit has detected a sufficient number of feature points
//            while featurePointCount < 50 && attempts < 10 { // Adjust threshold as needed
//                if let featurePoints = self.sceneView.session.currentFrame?.rawFeaturePoints?.points {
//                    featurePointCount = featurePoints.count
//                }
//                print("🔍 Feature points detected: \(featurePointCount)")
//
//                usleep(500_000) // Wait 0.5 seconds before checking again
//                attempts += 1
//            }
//
//            // ✅ Step 3: Once stable, start normal plane detection
//            DispatchQueue.main.async { self.startPlaneDetection() }
//        }
//    }
    
    func calculateAndDisplayWeight(with image: UIImage) {
        guard let normalizedVertices = findEllipseVertices(from: image, for: self.imagePortion, debug: false) else {
            DispatchQueue.main.async {
                self.showPopupMessage(title: "Error", message: "Could not detect valid fish contours. Please try again.")
            }
            return
        }

        let (verticesAnchors,
             centroidAboveAnchor,
             centroidBelowAnchor,
             cornerAnchors) = buildRealWorldVerticesAnchors(self.sceneView, normalizedVertices, image.size)
        
        // Handle failure: If no valid anchors were returned, show an error popup
        if verticesAnchors.count < 4 {
            DispatchQueue.main.async {
                self.showPopupMessage(title: "Error", message: "Failed to place anchors at vertices, able to place \(verticesAnchors.count).")
            }
            return
        }
        
        if cornerAnchors.isEmpty {
            DispatchQueue.main.async {
                self.showPopupMessage(title: "Error", message: "Failed to place anchors at corners.")
            }
            return
        }
        
        if centroidAboveAnchor == nil {
            DispatchQueue.main.async {
                self.showPopupMessage(title: "Error", message: "Failed to place anchor on fish.")
            }
            return
        }
        
        if centroidBelowAnchor == nil {
            DispatchQueue.main.async {
                self.showPopupMessage(title: "Error", message: "Failed to place anchor below fish.")
            }
            return
        }
        
        
        var (width, length, height) = measureVertices(verticesAnchors, cornerAnchors, centroidAboveAnchor!, centroidBelowAnchor!)
        
//        if let planeAnchor = self.firstPlaneAnchor {
//            if let normVector = normalVector(from: cornerAnchors) {
//                height = distanceToPlane(from: centroidAboveAnchor!, planeAnchor: planeAnchor, normal: normVector)
//            }
//        } else {
//            print("❌ No detected ground plane. Cannot measure height.")
//            DispatchQueue.main.async {
//                self.showPopupMessage(title: "Error", message: "No detected ground plane. Please scan the area again.")
//            }
//            return
//        }

        length *= Float(self.lengthNudge)
        width *= Float(self.widthNudge)
        height *= Float(self.heightNudge)

        let circumference = calculateCircumference(majorAxis: width, minorAxis: height)

        let (weightInLb, widthInInches, lengthInInches, heightInInches, circumferenceInInches) = calculateWeight(width, length, height, circumference, self.scaleFactor)

        imagePortion = 0.85

        let resultImageWidth = image.size.width * imagePortion
        let resultImageHeight = resultImageWidth * 16 / 9

        let croppedImage = image.croppedToAspectRatio(size: CGSize(width: resultImageWidth, height: resultImageHeight))
        if let combinedImage = generateResultImage(croppedImage!, nil, widthInInches, lengthInInches, heightInInches, circumferenceInInches, weightInLb, "") {
            self.showImagePopup(combinedImage: combinedImage)
        } else {
            self.view.showToast(message: "Could not isolate fish from scene, too much clutter!")
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

        // Add feedback label below the button
        let label = UILabel(frame: CGRect(x: button.frame.minX, y: button.frame.maxY + 10, width: button.frame.width, height: 20))
        label.text = "Initiating..."
        label.textAlignment = .center
        label.textColor = .gray
        label.font = UIFont.systemFont(ofSize: 14)
        view.addSubview(label)
        self.feedbackLabel = label
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
    
    func updateBracketSize() {
        guard let bracketView = bracketView else { return }
             
        imagePortion = 0.85
        
        let width = view.bounds.width * imagePortion // Example size for not forward-facing, adjust as needed
        let height = width * 16 / 9 // Maintain 9:16 aspect ratio
    
        let rect = CGRect(origin: CGPoint(x: view.bounds.midX - width / 2, y: view.bounds.midY - height / 2), size: CGSize(width: width, height: height))
        bracketView.updateBracket(rect: rect)
    }
    
    func startPlaneDetection() {

        if let featurePoints = sceneView.session.currentFrame?.rawFeaturePoints?.points, featurePoints.count < 60 {
            print("🚨 Not enough feature points! Ask user to scan more.")
            showPlaneDetectionHint()
        }
        
        let configuration = ARWorldTrackingConfiguration()
//        configuration.planeDetection = [.horizontal]
        configuration.planeDetection = []
        configuration.isLightEstimationEnabled = true // Helps in low-light conditions
//        configuration.worldAlignment = .gravityAndHeading // Ensures detected plane aligns with gravity
        configuration.isAutoFocusEnabled = true // Enable auto-focus for better tracking stability
        
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        updateCameraButtonState()
        
        // Cancel any existing timer and start a new one
//        planeDetectionTimer?.invalidate()
//        planeDetectionTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(showPlaneDetectionHint), userInfo: nil, repeats: false)
    }
    
//    func startBoatAnchorDetection() {
//        print("⚓ Initializing Boat Anchor...")
//
//        // Ensure sufficient feature points before setting the anchor
//        if let featurePoints = sceneView.session.currentFrame?.rawFeaturePoints?.points, featurePoints.count < 30 {
//            print("🚨 Not enough feature points! Ask user to scan more.")
//            showBoatAnchorHint()
//        }
//        
//        // Configure ARSession for object-based anchoring (instead of plane)
//        let configuration = ARWorldTrackingConfiguration()
//        configuration.planeDetection = [] // Disable plane detection
//        configuration.isLightEstimationEnabled = true
//        configuration.isAutoFocusEnabled = true
//        
//        // Reset session to force rescan and avoid drift
//        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
//
//        // Drop a reference anchor at the device's current position
//        if let cameraTransform = sceneView.session.currentFrame?.camera.transform {
//            let boatAnchor = ARAnchor(name: "BoatAnchor", transform: cameraTransform)
//            sceneView.session.add(anchor: boatAnchor)
//            print("✅ Boat anchor placed at device location.")
//            
//            // Store the anchor reference for later tracking
//            self.firstPlaneAnchor = nil // Clear previous ground reference
//            self.boatAnchor = boatAnchor
//            isGroundPlaneDetected = false
//        } else {
//            print("❌ Failed to retrieve camera position for boat anchor.")
//        }
//
//        // Set up drift correction using IMU
////        setupBoatDriftCorrection()
//
//        // Cancel any existing hint timer and start a new one
//        planeDetectionTimer?.invalidate()
//        planeDetectionTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(showBoatAnchorHint), userInfo: nil, repeats: false)
//    }
    
    func captureFrameAsUIImage(from arSCNView: ARSCNView) -> UIImage? {
        // Capture the current view as a UIImage
        let image = arSCNView.snapshot()
        return image
    }
    
    // This method is called whenever an ARAnchor is added to the session
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // If it's a plane anchor, process only the first plane
        if let planeAnchor = anchor as? ARPlaneAnchor, planeAnchor.alignment == .horizontal {
            if firstPlaneAnchor == nil {
                firstPlaneAnchor = planeAnchor
//                isGroundPlaneDetected = true // ✅ Mark ground plane detected

//                print("First plane detected: \(planeAnchor.identifier)")
//                
//                DispatchQueue.main.async { [weak self] in
//                    self?.updateCameraButtonState()
//                }
//                
//                // ✅ Cancel the popup timer since the plane is found
//                planeDetectionTimer?.invalidate()
            
                // Visualize the plane
                let planeGeometry = ARSCNPlaneGeometry(device: sceneView.device!)
                planeGeometry?.update(from: planeAnchor.geometry)
                
                let gridMaterial = SCNMaterial()
                gridMaterial.diffuse.contents = createGridTexture(size: 512, gridColor: UIColor.green.withAlphaComponent(0.3), backgroundColor: .clear)
                gridMaterial.isDoubleSided = true
                planeGeometry?.materials = [gridMaterial]
                
                let meshNode = SCNNode(geometry: planeGeometry)
                meshNode.isHidden = false
                
                node.addChildNode(meshNode)
                
                // ✅ Store reference for toggling later
                debugNodes.append(meshNode)
            
            }
        } else {
            // Add a red sphere for all other anchors
            let sphere = SCNSphere(radius: 0.002) // Small red sphere
            sphere.firstMaterial?.diffuse.contents = UIColor.red
            
            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.isHidden = false
            
            node.addChildNode(sphereNode)
            
            // ✅ Store reference for toggling later
            debugNodes.append(sphereNode)
        
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor, planeAnchor.identifier == firstPlaneAnchor?.identifier {
            // Update the stored plane anchor
            firstPlaneAnchor = planeAnchor

            // Update the visual representation
            if let planeGeometry = node.geometry as? ARSCNPlaneGeometry {
                planeGeometry.update(from: planeAnchor.geometry)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor, planeAnchor.identifier == firstPlaneAnchor?.identifier {
            print("⚠️ First plane removed. Searching for a new one.")

            firstPlaneAnchor = nil
//            isGroundPlaneDetected = false

            DispatchQueue.main.async { [weak self] in
                self?.updateCameraButtonState()
            }

            // ✅ Restart plane detection so a new one can be assigned
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startPlaneDetection()
                self?.showPlaneDetectionHint()
            }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("Session error: \(error.localizedDescription)")
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateCameraButtonState()
        updateTrackingStatusLabel(for: camera.trackingState)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        print("Frame updated at: \(frame.timestamp)")
    }
    
    func createGridTexture(size: Int, gridColor: UIColor, backgroundColor: UIColor = .clear) -> UIImage {
        let scale = UIScreen.main.scale
        let gridSize = CGFloat(size)

        UIGraphicsBeginImageContextWithOptions(CGSize(width: gridSize, height: gridSize), false, scale)
        let context = UIGraphicsGetCurrentContext()!

        // Fill the background with transparent color
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: gridSize, height: gridSize))

        // Draw vertical lines with semi-transparent grid color
        context.setStrokeColor(gridColor.withAlphaComponent(0.5).cgColor) // Adjust alpha here
        context.setLineWidth(1.0)
        for x in stride(from: 0, to: Int(gridSize), by: size / 10) {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: Int(gridSize)))
        }

        // Draw horizontal lines with semi-transparent grid color
        for y in stride(from: 0, to: Int(gridSize), by: size / 10) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: Int(gridSize), y: y))
        }

        context.strokePath()

        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        return image
    }
    
    private func updateCameraButtonState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let isTrackingNormal = self.sceneView.session.currentFrame?.camera.trackingState == .normal
            let isPlaneAvailable = self.isGroundPlaneDetected

            if isTrackingNormal && isPlaneAvailable {
                self.cameraButton?.isEnabled = true
                self.cameraButton?.alpha = 1.0
                self.feedbackLabel?.text = "Ready"
                self.feedbackLabel?.textColor = .green
            } else {
                print("tracking: \(isTrackingNormal), plane: \(isPlaneAvailable)")
                self.cameraButton?.isEnabled = false
                self.cameraButton?.alpha = 0.5
                self.feedbackLabel?.text = "Reinitiating..."
                self.feedbackLabel?.textColor = .gray
            }
        }
    }
    
    private func setupTrackingStatusLabel() {
        trackingStatusLabel = UILabel(frame: CGRect(x: 10, y: 50, width: 300, height: 30))
        trackingStatusLabel.text = "Tracking: Initializing..."
        trackingStatusLabel.textColor = .white
        trackingStatusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        trackingStatusLabel.textAlignment = .left
        trackingStatusLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        trackingStatusLabel.layer.cornerRadius = 5
        trackingStatusLabel.layer.masksToBounds = true
        view.addSubview(trackingStatusLabel)
    }
    
    private func updateTrackingStatusLabel(for trackingState: ARCamera.TrackingState) {
        DispatchQueue.main.async {
            switch trackingState {
            case .normal:
                self.trackingStatusLabel.text = "Tracking: ✅ Normal"
                self.trackingStatusLabel.textColor = .green
            case .notAvailable:
                self.trackingStatusLabel.text = "Tracking: ❌ Not Available"
                self.trackingStatusLabel.textColor = .red
            case .limited(let reason):
                var reasonText = "Unknown"
                switch reason {
                case .excessiveMotion:
                    reasonText = "⚠️ Excessive Motion"
                case .insufficientFeatures:
                    reasonText = "⚠️ Insufficient Features"
                case .initializing:
                    reasonText = "⌛ Initializing"
                case .relocalizing:
                    reasonText = "📍 Relocalizing"
                @unknown default:
                    break
                }
                self.trackingStatusLabel.text = "Tracking: \(reasonText)"
                self.trackingStatusLabel.textColor = .yellow
            }
        }
    }
    
    func startMotionTracking() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.5 // Adjust for responsiveness
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
                guard let self = self, let motion = motion else { return }
                
                let pitch = motion.attitude.pitch * (180.0 / .pi) // Convert to degrees
                let roll = motion.attitude.roll * (180.0 / .pi)

                let totalTilt = abs(pitch) + abs(roll) // Sum of absolute tilts
                
                // Store recent tilts
                self.motionHistory.append(totalTilt)
                if self.motionHistory.count > self.sampleCount {
                    self.motionHistory.removeFirst() // Keep only the latest samples
                }

                // Determine if on a boat
                self.checkForBoatMotion()
            }
        }
    }
    
    func checkForBoatMotion() {
        let maxTilt = motionHistory.max() ?? 0
        let minTilt = motionHistory.min() ?? 0
        let tiltVariation = maxTilt - minTilt

        if tiltVariation > motionThreshold {
            if !isBoatMode {
                isBoatMode = true
                print("🚤 Detected BOAT mode! Switching to ARObjectAnchor.")
                switchToBoatMode()
            }
        } else {
            if isBoatMode {
                isBoatMode = false
                print("🏞️ Detected LAND mode! Switching to ARPlaneAnchor.")
                switchToLandMode()
            }
        }
    }

    func switchToBoatMode() {
        print("🔹 Now using ARObjectAnchor tracking.")
        // We will implement this in the next step
    }

    func switchToLandMode() {
        print("🔹 Now using ARPlaneAnchor tracking.")
        // We will implement this in the next step
    }

//    func setupBoatDriftCorrection() {
//        if motionManager.isDeviceMotionAvailable {
//            motionManager.deviceMotionUpdateInterval = 0.5
//            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
//                guard let self = self, let motion = motion, let boatAnchor = self.boatAnchor else { return }
//                
//                // Check if gravity vector has changed significantly
//                let deviceGravity = motion.gravity
//                let arGravity = self.sceneView.session.currentFrame?.camera.transform.columns.1
//                
//                let gravityDeviation = abs(Float(deviceGravity.y) - arGravity!.y ?? 0)
//                if gravityDeviation > 0.05 { // Threshold for drift correction
//                    print("⚠️ Boat anchor drift detected! Correcting position...")
//                    self.correctBoatAnchorPosition()
//                }
//            }
//        }
//    }
}


