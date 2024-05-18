/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the ARKitVision sample.
*/

import UIKit
import SpriteKit
import ARKit
import Vision

class ViewController: UIViewController, ARSKViewDelegate, ARSessionDelegate {
    
    @IBOutlet weak var sceneView: ARSKView!
    
    private var lastAnchor: ARAnchor?
    private var refAnchor: ARAnchor?

    private var freezeButton: UIButton?
    private var isFrozen = false
    
    private var saveImage: UIImage?
    
    /// The ML model to be used for detection of arbitrary objects
    private var _tripleTaleModel: TripleTaleV4!
    private var tripleTaleModel: TripleTaleV4! {
        get {
            if let model = _tripleTaleModel { return model }
            _tripleTaleModel = {
                do {
                    let configuration = MLModelConfiguration()
                    return try TripleTaleV4(configuration: configuration)
                } catch {
                    fatalError("Couldn't create TripleTaleV4 due to: \(error)")
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
                // Pause the AR session
                let bottomLeft = CGPoint(x: 0, y: self.sceneView.bounds.maxY - 30)
                self.refAnchor = addAnchor(self.sceneView, bottomLeft)
//                
//                let position = self.refAnchor!.transform.columns.3
//                print("ref position: \(position)")
                
                self.sceneView.session.add(anchor: self.refAnchor!)
                self.anchorLabels[self.refAnchor!.identifier] = "ref"
                
                /// Measurements
                    let cornerAnchors = getCorners(self.sceneView, self.boundingBox!, self.saveImage!.size)
//                let normCenterAnchor = transformHeightAnchor(self.refAnchor!, cornerAnchors[4])
                let normCenterAnchor = transformHeightAnchor(ref: cornerAnchors[5], cen: cornerAnchors[4])

                // for debugging
                self.sceneView.session.add(anchor: cornerAnchors[0])
                self.sceneView.session.add(anchor: cornerAnchors[1])
                self.sceneView.session.add(anchor: cornerAnchors[2])
                self.sceneView.session.add(anchor: cornerAnchors[3])
                self.sceneView.session.add(anchor: cornerAnchors[4])
                self.sceneView.session.add(anchor: cornerAnchors[5])
//                self.sceneView.session.add(anchor: normCenterAnchor)
//                
                self.anchorLabels[cornerAnchors[0].identifier] = "l"
                self.anchorLabels[cornerAnchors[1].identifier] = "r"
                self.anchorLabels[cornerAnchors[2].identifier] = "t"
                self.anchorLabels[cornerAnchors[3].identifier] = "b"
//                self.anchorLabels[cornerAnchors[4].identifier] = "c"
                self.anchorLabels[cornerAnchors[5].identifier] = "ref"
//                self.anchorLabels[normCenterAnchor.identifier] = "c_t"
                
                
                // size calculation
                let width = calculateDistanceBetweenAnchors(anchor1: cornerAnchors[0], anchor2: cornerAnchors[1])
                let length = calculateDistanceBetweenAnchors(anchor1: cornerAnchors[2], anchor2: cornerAnchors[3])
                let height = calculateDistanceBetweenAnchors(anchor1: self.refAnchor!, anchor2: normCenterAnchor)
//                let height = calculateDistanceBetweenAnchors(anchor1: cornerAnchors[5], anchor2: normCenterAnchor)

                let circumference = calculateCircumference(majorAxis: width, minorAxis: height)
                
                let widthInMeters = Measurement(value: Double(width), unit: UnitLength.meters)
                let lengthInMeters = Measurement(value: Double(length), unit: UnitLength.meters)
                let heightInMeters = Measurement(value: Double(height), unit: UnitLength.meters)
                let circumferenceInMeters = Measurement(value: Double(circumference), unit: UnitLength.meters)

                let widthInInches = widthInMeters.converted(to: .inches)
                let lengthInInches = lengthInMeters.converted(to: .inches)
                let heightInInches = heightInMeters.converted(to: .inches)
                let circumferenceInInches = circumferenceInMeters.converted(to: .inches)

                let weight = lengthInInches.value * circumferenceInInches.value * circumferenceInInches.value / 1200.0
                let weightInLb = Measurement(value: weight, unit: UnitMass.pounds)
                
                let formattedWidth = String(format: "%.2f", widthInInches.value)
                let formattedLength = String(format: "%.2f", lengthInInches.value)
                let formattedHeight = String(format: "%.2f", heightInInches.value)
                let formattedCircumference = String(format: "%.2f", circumferenceInInches.value)
                let formattedWeight = String(format: "%.2f", weightInLb.value)

                self.anchorLabels[cornerAnchors[4].identifier] = "\(formattedWeight) lb, \(formattedLength) in "
                
                self.view.showToast(message: "W \(formattedWidth) in x L \(formattedLength) in x H \(formattedHeight) in, C \(formattedCircumference) in")
                
                // saving image
                
                
                    let imageWithBox = drawRectanglesOnImage(image: self.saveImage!, boundingBoxes: [self.boundingBox!])

                    let point = CGPoint(x: 50, y: 50)  // Modify as needed
                    let fontSize: CGFloat = 45
                    let textColor = UIColor.white
                    let newTextImage = imageWithBox.imageWithText("\(self.identifierString): \(formattedWeight) lb, W \(formattedWidth) in x L \(formattedLength) in x H \(formattedHeight) in, C \(formattedCircumference) in", atPoint: point, fontSize: fontSize, textColor: textColor)
                    
                    saveImageToGallery(newTextImage!)
                }

                self.isFrozen.toggle()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
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
    
    // MARK: - Vision classification
    
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
                try requestHandler.perform([self.detectionRequest])
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
        lastAnchor = nil
        
        let configuration = ARWorldTrackingConfiguration()
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
