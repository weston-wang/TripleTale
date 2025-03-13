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
    
    private var isProcessingCameraPress = false

    private var planeDetectionTimer: Timer?
    private var detectedPlanes: [UUID: ARPlaneAnchor] = [:] // Store multiple planes
    
    private var debugCounter = 0
    private var debugNodes: [SCNNode] = []
    private var debugMode: Bool = false


    private var tapCounter = 0
    var scaleFactor: Double = 500.0
    var lengthNudge: Double = 1.0
    var widthNudge: Double = 1.0
    var heightNudge: Double = 1.4
    
    private var motionManager = CMMotionManager()
    private var lastKnownPitch: Double = 0.0
    private var lastKnownRoll: Double = 0.0
    private var alignmentThreshold: Double = 75.0 // Degrees of tilt change allowed
    private var isReAligning = false

    private var cameraButton: UIButton?
    private var feedbackLabel: UILabel?
    
    private var bracketView: BracketView?
    private var imagePortion: CGFloat = 1.0
    
    private var firstPlaneAnchor: ARPlaneAnchor?
    private var isGroundPlaneDetected = false

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
        if debugMode {
            sceneView.debugOptions = [.showFeaturePoints]
        }
        view.addSubview(sceneView)

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
        
        startMotionTracking() // ✅ Start monitoring tilt changes

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

              debugMode.toggle()

              // Toggle debug options
              if debugMode {
                  // Enable debug mode
                  sceneView.debugOptions = [.showFeaturePoints]
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
        } else {
            self.view.showToast(message: "Could not capture image from scene!")
            isProcessingCameraPress = false
        }
    }

    
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
    

    func calculateAndDisplayWeight(with image: UIImage, completion: @escaping () -> Void) {
        guard let normalizedVertices = findEllipseVertices(from: image, for: self.imagePortion, debug: self.debugMode) else {
            DispatchQueue.main.async {
                self.showPopupMessage(title: "Error", message: "Could not detect valid fish contours. Please try again.")
                completion()
            }
            return
        }

        let (verticesAnchors,
             centroidAboveAnchor,
             centroidBelowAnchor,
             cornerAnchors) = buildRealWorldVerticesAnchors(self.sceneView, normalizedVertices, image.size)

        if verticesAnchors.isEmpty || cornerAnchors.isEmpty || centroidAboveAnchor == nil || centroidBelowAnchor == nil {
            DispatchQueue.main.async {
                self.showPopupMessage(title: "Error", message: "Failed to place anchors properly.")
                completion()
            }
            return
        }

        var (width, length, height) = measureVertices(verticesAnchors, cornerAnchors, centroidAboveAnchor!, centroidBelowAnchor!)

        if let planeAnchor = self.firstPlaneAnchor, let normVector = normalVector(from: cornerAnchors) {
            height = distanceToPlane(from: centroidAboveAnchor!, planeAnchor: planeAnchor, normal: normVector)
        } else {
            DispatchQueue.main.async {
                self.showPopupMessage(title: "Error", message: "No detected ground plane. Please scan the area again.")
                completion()
            }
            return
        }

        length *= Float(self.lengthNudge)
        width *= Float(self.widthNudge)
        height *= Float(self.heightNudge)

        let circumference = calculateCircumference(majorAxis: width, minorAxis: height)

        let (weightInLb, widthInInches, lengthInInches, heightInInches, circumferenceInInches) =
            calculateWeight(width, length, height, circumference, self.scaleFactor)

        imagePortion = 0.85

        let resultImageWidth = image.size.width * imagePortion
        let resultImageHeight = resultImageWidth * 16 / 9

        let croppedImage = image.croppedToAspectRatio(size: CGSize(width: resultImageWidth, height: resultImageHeight))

        if let combinedImage = generateResultImage(croppedImage!, nil, widthInInches, lengthInInches, heightInInches,
                                                   circumferenceInInches, weightInLb, "", debug: self.debugMode) {
            self.showImagePopup(combinedImage: combinedImage)
        } else {
            self.view.showToast(message: "Could not isolate fish from scene, too much clutter!")
        }

        DispatchQueue.main.async {
            completion()
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

        if let featurePoints = sceneView.session.currentFrame?.rawFeaturePoints?.points, featurePoints.count < 30 {
            print("🚨 Not enough feature points! Ask user to scan more.")
            showPlaneDetectionHint()
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .camera // Ensures detected plane aligns with camera
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true // Helps in low-light conditions
        configuration.isAutoFocusEnabled = true // Enable auto-focus for better tracking stability

        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        // Cancel any existing timer and start a new one
        planeDetectionTimer?.invalidate()
        planeDetectionTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(showPlaneDetectionHint), userInfo: nil, repeats: false)
    }
    
    func captureFrameAsUIImage(from arSCNView: ARSCNView) -> UIImage? {
        // Capture the current view as a UIImage
        let image = arSCNView.snapshot()
        return image
    }
    
    // This method is called whenever an ARAnchor is added to the session
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // If it's a plane anchor, process only the first plane
        if let planeAnchor = anchor as? ARPlaneAnchor, planeAnchor.alignment == .horizontal {
            detectedPlanes[planeAnchor.identifier] = planeAnchor

            // Select the closest plane dynamically
            firstPlaneAnchor = detectedPlanes.values.min(by: { distanceToCamera($0) < distanceToCamera($1) })
            isGroundPlaneDetected = true
            DispatchQueue.main.async { [weak self] in self?.updateCameraButtonState() }

            // ✅ Draw plane for every detected plane (instead of only the first one)
            let planeGeometry = ARSCNPlaneGeometry(device: sceneView.device!)
            planeGeometry?.update(from: planeAnchor.geometry)

            let gridMaterial = SCNMaterial()
            gridMaterial.diffuse.contents = createGridTexture(size: 1024, gridColor: UIColor.green.withAlphaComponent(0.3), backgroundColor: .clear)
            gridMaterial.isDoubleSided = true
            planeGeometry?.materials = [gridMaterial]

            let meshNode = SCNNode(geometry: planeGeometry)
            meshNode.name = planeAnchor.identifier.uuidString // Tag the node for tracking
            
            node.addChildNode(meshNode)
            // ✅ Cancel the hint popup since a plane is found
            planeDetectionTimer?.invalidate()
        } else {
            // Add a red sphere for all other anchors
            let sphere = SCNSphere(radius: 0.002) // Small red sphere
            sphere.firstMaterial?.diffuse.contents = UIColor.red

            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.isHidden = debugMode
            
            node.addChildNode(sphereNode)
            
            debugNodes.append(sphereNode)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            detectedPlanes[planeAnchor.identifier] = planeAnchor

            // ✅ Update firstPlaneAnchor dynamically
            firstPlaneAnchor = detectedPlanes.values.min(by: { distanceToCamera($0) < distanceToCamera($1) })

            // ✅ Update the correct plane geometry (look for the node with matching identifier)
            for child in node.childNodes {
                if let planeGeometry = child.geometry as? ARSCNPlaneGeometry, child.name == planeAnchor.identifier.uuidString {
                    planeGeometry.update(from: planeAnchor.geometry)
                }
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            detectedPlanes.removeValue(forKey: planeAnchor.identifier)

            // ✅ If the removed plane was firstPlaneAnchor, pick a new closest one
            if planeAnchor.identifier == firstPlaneAnchor?.identifier {
                firstPlaneAnchor = detectedPlanes.values.min(by: { distanceToCamera($0) < distanceToCamera($1) })
                isGroundPlaneDetected = (firstPlaneAnchor != nil)
            }

            // ✅ Remove only the corresponding plane visualization
            node.childNodes.forEach { child in
                if child.name == planeAnchor.identifier.uuidString {
                    child.removeFromParentNode()
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.updateCameraButtonState()
                self?.realignARSession()
            }
        }
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
        context.setLineWidth(2.0)
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

            let pitchDelta = abs(currentPitch - self.lastKnownPitch)
            let rollDelta = abs(currentRoll - self.lastKnownRoll)

            // Save new values
            self.lastKnownPitch = currentPitch
            self.lastKnownRoll = currentRoll

            // ✅ If the tilt exceeds threshold, trigger realignment
            if (pitchDelta > self.alignmentThreshold || rollDelta > self.alignmentThreshold) {
                print("🚨 Detected device tilt change: Pitch Δ\(pitchDelta), Roll Δ\(rollDelta)")
                self.realignARSession()
            }
        }
    }
    
    private func realignARSession() {
        guard !isReAligning else { return } // Prevent multiple triggers
        isReAligning = true

        DispatchQueue.main.async {
            self.feedbackLabel?.text = "Realigning..."
            self.feedbackLabel?.textColor = .red
        }

        print("🔄 Resetting AR tracking and realigning...")
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .camera // Keep boat-relative alignment
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        configuration.isAutoFocusEnabled = true
        
        // ✅ Clear debug nodes before resetting tracking
        for node in debugNodes {
            node.removeFromParentNode()
        }
        debugNodes.removeAll()

        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.isReAligning = false
            self?.feedbackLabel?.text = "Ready"
            self?.feedbackLabel?.textColor = .green
        }
    }
    
    // 📌 Helper function to calculate distance from camera to plane
    private func distanceToCamera(_ planeAnchor: ARPlaneAnchor) -> Float {
        guard let frame = sceneView.session.currentFrame else { return Float.greatestFiniteMagnitude }
        let cameraPosition = frame.camera.transform.columns.3 // Camera position in world space
        let planePosition = planeAnchor.transform.columns.3
        let dx = cameraPosition.x - planePosition.x
        let dy = cameraPosition.y - planePosition.y
        let dz = cameraPosition.z - planePosition.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

}


