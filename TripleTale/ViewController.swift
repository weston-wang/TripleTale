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

class ViewController: UIViewController, ARSKViewDelegate, ARSessionDelegate {
    
    @IBOutlet weak var sceneView: ARSKView!
    
    let motionManager = CMMotionManager()
    
    private var isForwardFacing = false

    private var freezeButton: UIButton?
    private var isFrozen = false
    
    private var saveImage: UIImage?
    
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
    
    // MARK: - View controller lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Check if the accelerometer is available
        guard motionManager.isAccelerometerAvailable else {
            print("Accelerometer is not available")
            return
        }
        
        // Set the update interval for accelerometer data
        motionManager.accelerometerUpdateInterval = 0.1
        
        // Start receiving accelerometer updates
        motionManager.startAccelerometerUpdates(to: OperationQueue.main) { [weak self] (data, error) in
            guard let data = data, error == nil else {
                return
            }
            
            // Determine the device orientation based on accelerometer data
            self?.detectOrientation(acceleration: data.acceleration)
        }
        
        // Configure and present the SpriteKit scene that draws overlay content.
        let overlayScene = SKScene()
        overlayScene.scaleMode = .aspectFill
        sceneView.delegate = self
        sceneView.presentScene(overlayScene)
        sceneView.session.delegate = self
        
        freezeButton = UIButton(frame: CGRect(x: (view.bounds.width - 70)/2, y: view.bounds.height - 150,
                                                  width: 70, height: 70))
        freezeButton?.backgroundColor = .white
        freezeButton?.layer.cornerRadius = 35
        freezeButton?.clipsToBounds = true

        // Set the button images for different states
        freezeButton?.setImage(UIImage(named: "measure"), for: .normal)
        freezeButton?.setImage(UIImage(named: "pressed"), for: .highlighted)

        freezeButton?.imageView?.contentMode = .scaleAspectFill
        
        freezeButton?.isHidden = true
        
        freezeButton?.addTarget(self, action: #selector(toggleFreeze), for: .touchUpInside)
        view.addSubview(freezeButton!)

        // Hook up status view controller callback.
        statusViewController.restartExperienceHandler = { [unowned self] in
            self.restartSession()
        }
    }
    
    @objc func toggleFreeze() {
        DispatchQueue.main.async {
            self.isFrozen.toggle()  // Toggle the state of isFrozen
            
            let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
            feedbackGenerator.prepare()
            feedbackGenerator.impactOccurred()
            
            if self.isFrozen {
                if self.saveImage != nil {
                    // isolate fish through foreground vs background separation
                    if let fishBoundingBox = removeBackground(from: self.saveImage!) {
                        var centroidAnchor: ARAnchor?
                        var midpointAnchors: [ARAnchor]
                        
                        var nudgeRate: Float = 0.0
                        
                        if !self.isForwardFacing {
                            self.boundingBox = fishBoundingBox
                            
                            // calculate centroid beneath fish, will fail if not all corners available
                            let cornerAnchors = getCorners(self.sceneView, self.boundingBox!, self.saveImage!.size)
                            centroidAnchor = createNudgedCentroidAnchor(from: cornerAnchors, nudgePercentage: 0.1)

                        } else {
                            nudgeRate = 0.1
                            
                            let tightFishBoundingBox = nudgeBoundingBox(fishBoundingBox,nudgeRate)
                            self.boundingBox = tightFishBoundingBox

                            centroidAnchor = getTailAnchor(self.sceneView, self.boundingBox!, self.saveImage!.size)
                        }
                        
                        if centroidAnchor != nil {
                            // interact with AR world and define anchor points
                            midpointAnchors = getMidpoints(self.sceneView, self.boundingBox!, self.saveImage!.size)
                            
                            // measure in real world units
                            let (width, length, height, circumference) = self.measureDimensions(midpointAnchors, centroidAnchor!, scale: (1.0 + nudgeRate))
                            
                            // calculate weight
                            let (weightInLb, widthInInches, lengthInInches, heightInInches, circumferenceInInches) = calculateWeight(width, length, height, circumference)
                            
                            // save result to gallery
                            self.saveResult(widthInInches, lengthInInches, heightInInches, circumferenceInInches, weightInLb)
                        } else {
                            self.view.showToast(message: "Could not measure the fish, uneven surface!")
                        }
                    } else {
                        self.view.showToast(message: "Could not isolate fish from scene, too much clutter!")
                    }
                }
                
                self.isFrozen.toggle()
            }
        }
    }

    
    func startPlaneDetection() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        sceneView.session.run(configuration)
        
//        sceneView.session.delegate = nil // Not needed for plane detection
    }
    
    func startBodyTracking() {
        let configuration = ARBodyTrackingConfiguration()
        sceneView.session.run(configuration)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if isForwardFacing {
            startBodyTracking()
        } else {
            startPlaneDetection()
        }
//        // Create a session configuration
//        let configuration = ARWorldTrackingConfiguration()
//        configuration.planeDetection = [.horizontal]
//
//        // Run the view's session
//        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    // MARK: - Helpers
    private func measureDimensions(_ midpointAnchors: [ARAnchor], _ centroidAnchor: ARAnchor, scale: Float = 1.0) -> (Float, Float, Float, Float){
        var length: Float
        var width: Float
        var height: Float
        var circumference: Float
                
        var updatedMidpointAnchors: [ARAnchor]
        
        if !isForwardFacing {
            height = calculateHeightBetweenAnchors(anchor1: centroidAnchor, anchor2: midpointAnchors[4])

            let distanceToPhone = calculateDistanceToObject(midpointAnchors[4])
            let distanceToGround = calculateDistanceToObject(centroidAnchor)
                        
            // update boundingbox for calculations
            let updatedBoundingBox = reversePerspectiveEffectOnBoundingBox(boundingBox: self.boundingBox!, distanceToPhone: distanceToPhone, totalDistance: distanceToGround)
            updatedMidpointAnchors = getMidpoints(self.sceneView, updatedBoundingBox, self.saveImage!.size)
        } else {
            let heightL = calculateDepthBetweenAnchors(anchor1: midpointAnchors[4], anchor2: midpointAnchors[0])
            let heightR = calculateDepthBetweenAnchors(anchor1: midpointAnchors[4], anchor2: midpointAnchors[1])

            height = max(heightL, heightR) * 2.0 * scale
            
            updatedMidpointAnchors = midpointAnchors
        }
        
        width = calculateDistanceBetweenAnchors(anchor1: updatedMidpointAnchors[0], anchor2: updatedMidpointAnchors[1]) * scale
        length = calculateDistanceBetweenAnchors(anchor1: updatedMidpointAnchors[2], anchor2: updatedMidpointAnchors[3]) * scale
                
        circumference = calculateCircumference(majorAxis: width, minorAxis: height)
        
        return (width, length, height, circumference)
    }
    
    private func saveResult(_ widthInInches: Measurement<UnitLength>, _ lengthInInches: Measurement<UnitLength>, _ heightInInches: Measurement<UnitLength>, _ circumferenceInInches: Measurement<UnitLength>, _ weightInLb: Measurement<UnitMass>) {
        
        let formattedLength = String(format: "%.2f", lengthInInches.value)
        let formattedWeight = String(format: "%.2f", weightInLb.value)
        let formattedWidth = String(format: "%.2f", widthInInches.value)
        let formattedHeight = String(format: "%.2f", heightInInches.value)
        let formattedCircumference = String(format: "%.2f", circumferenceInInches.value)

//        self.anchorLabels[midpointAnchors[4].identifier] = "\(formattedWeight) lb, \(formattedLength) in "
        let imageWithBox = drawRectanglesOnImage(image: self.saveImage!, boundingBoxes: [self.boundingBox!])
        let newTextImage = imageWithBox.imageWithCenteredText("L \(formattedLength) in x W \(formattedWidth) in x H \(formattedHeight) in, C \(formattedCircumference) in, \(formattedWeight) lb", fontSize: 150, textColor: UIColor.white)

//        let newTextImage = self.saveImage!.imageWithCenteredText("\(formattedLength) in, \(formattedWeight) lb", fontSize: 150, textColor: UIColor.white)

        let overlayImage = UIImage(named: "shimano_logo")!
        let combinedImage = newTextImage!.addImageToBottomRightCorner(overlayImage: overlayImage)
        
        saveImageToGallery(combinedImage!)
        
        showImagePopup(combinedImage: combinedImage!)

    }
    
    private func detectOrientation(acceleration: CMAcceleration) {
        let previousFacingState = isForwardFacing
        
        if acceleration.y < -0.8 {
            isForwardFacing = true
        } else {
            isForwardFacing = false
        }
        
        if isForwardFacing != previousFacingState {
            self.restartSession()
        }
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
        
        self.saveImage = pixelBufferToUIImage(pixelBuffer: self.currentBuffer!)
        
        detectCurrentImage()
    }
    
    func showImagePopup(combinedImage: UIImage) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        
        // Create an image view with the image
        let imageView = UIImageView(image: combinedImage)
        imageView.contentMode = .scaleAspectFit
        
        // Set the desired width and height for the image view with padding
        let maxWidth: CGFloat = 270
        let maxHeight: CGFloat = 480
        
        // Calculate the aspect ratio
        let aspectRatio = combinedImage.size.width / combinedImage.size.height
        
        // Determine the width and height based on the aspect ratio
        var imageViewWidth = maxWidth
        var imageViewHeight = maxWidth / aspectRatio
        
        if imageViewHeight > maxHeight {
            imageViewHeight = maxHeight
            imageViewWidth = maxHeight * aspectRatio
        }
        
        // Create a container view for the image view to add constraints
        let containerView = UIView()
        containerView.addSubview(imageView)
        
        // Set up auto layout constraints
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: imageViewWidth),
            imageView.heightAnchor.constraint(equalToConstant: imageViewHeight),
            imageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: imageViewWidth + 20),  // Adding padding
            containerView.heightAnchor.constraint(equalToConstant: imageViewHeight + 20) // Adding padding
        ])
        
        // Add the container view to the alert controller
        alert.view.addSubview(containerView)
        
        // Set up the container view's constraints within the alert view
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            containerView.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 20),
            containerView.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -45)
        ])
        
        // Add an action to dismiss the alert
        alert.addAction(UIAlertAction(title: "Fish on!", style: .default, handler: nil))
        
        // Present the alert controller
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: - Vision classification
    
    // Vision classification request and model
    /// - Tag: ClassificationRequest
    private lazy var classificationRequest: VNCoreMLRequest = {
        do {
            // Instantiate the model from its generated Swift class.
            let model = try VNCoreMLModel(for: tripleTaleModel.model)
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                self?.processClassifications(for: request, error: error)
            })

            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()

    /// - Tag: DetectionRequest
    private lazy var detectionRequest: VNCoreMLRequest = {
        do {
            // Instantiate the model from its generated Swift class.
//            let model = try VNCoreMLModel(for: yolo3Model.model)
            let model = try VNCoreMLModel(for: tripleTaleModel.model)

            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                self?.processDetections(for: request, error: error)
            })
            
            // Use CPU for Vision processing to ensure that there are adequate GPU resources for rendering.
//            request.usesCPUOnly = true
            
            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }()
    
    // The pixel buffer being held for analysis; used to serialize Vision requests.
    private var currentBuffer: CVPixelBuffer?
    
    // Queue for dispatching vision classification requests
    private let visionQueue = DispatchQueue(label: "com.tripletale.tripletaleapp")
    
    private func detectCurrentImage() {
        // Most computer vision tasks are not rotation agnostic so it is important to pass in the orientation of the image with respect to device.
        let orientation = CGImagePropertyOrientation(UIDevice.current.orientation)
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentBuffer!, orientation: orientation)
        visionQueue.async {
            do {
                // Release the pixel buffer when done, allowing the next buffer to be processed.
                defer { self.currentBuffer = nil }
                try requestHandler.perform([self.classificationRequest])
//                try requestHandler.perform([self.detectionRequest])
            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
    }
    
    // Classification results
    private var identifierString = ""
    private var confidence: VNConfidence = 0.0
    private var boundingBox: CGRect?
    
    func processDetections(for request: VNRequest, error: Error?) {
        guard let results = request.results else {
            print("Unable to classify image.\n\(error!.localizedDescription)")
            return
        }
        // The `results` will always be `VNClassificationObservation`s, as specified by the Core ML model in this project.
        let detections = results as! [VNRecognizedObjectObservation]
        
        // Show a label for the highest-confidence result (but only above a minimum confidence threshold).
        if let bestResult = detections.first(where: { result in result.confidence > 0.5 }),
           let label = bestResult.labels.first!.identifier.split(separator: ",").first {
            identifierString = String(label)
            confidence = bestResult.confidence
            boundingBox = bestResult.boundingBox
//            print("Detected \(label) with bounding box: \(String(describing: boundingBox))")

        } else {
            identifierString = ""
            confidence = 0
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.displayClassifierResults()
        }
    }
    
    func processClassifications(for request: VNRequest, error: Error?) {
        guard let results = request.results else {
            print("Unable to classify image.\n\(error!.localizedDescription)")
            return
        }
        // The `results` will always be `VNClassificationObservation`s, as specified by the Core ML model in this project.
        let classifications = results as! [VNClassificationObservation]

        // Show a label for the highest-confidence result (but only above a minimum confidence threshold).
        if let bestResult = classifications.first(where: { result in result.confidence > 0.5 }),
            let label = bestResult.identifier.split(separator: ",").first {
            identifierString = String(label)
            confidence = bestResult.confidence
        } else {
            identifierString = ""
            confidence = 0
        }

        DispatchQueue.main.async { [weak self] in
            self?.displayClassifierResults()
        }
    }
    
    // Show the classification results in the UI.
    private func displayClassifierResults() {
        guard !self.identifierString.isEmpty else {
            freezeButton?.isHidden = true
            return // No object was classified.
        }
        freezeButton?.isHidden = false

        let message = String(format: "Detected \(self.identifierString) with %.2f", self.confidence * 100) + "% confidence"
        statusViewController.showMessage(message)
    }
    
    // MARK: - Tap gesture handler & ARSKViewDelegate
    
    // Labels for classified objects by ARAnchor UUID
    private var anchorLabels = [UUID: String]()
    
    // When an anchor is added, provide a SpriteKit node for it and set its text to the classification label.
    /// - Tag: UpdateARContent
    func view(_ view: ARSKView, didAdd node: SKNode, for anchor: ARAnchor) {
        // Check if the anchor is an ARPlaneAnchor
        if anchor is ARPlaneAnchor {
            print("A plane anchor was added. Ignoring label assignment for plane anchors.")
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
        statusViewController.showTrackingQualityInfo(for: camera.trackingState, autoHide: true)
        
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
        
        var configuration: ARConfiguration
        if !isForwardFacing {
            configuration = ARWorldTrackingConfiguration()
        } else {
            configuration = ARBodyTrackingConfiguration()
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
