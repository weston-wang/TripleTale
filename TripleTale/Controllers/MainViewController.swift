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

    let isMLDetection = false
    
    let motionManager = CMMotionManager()
    private var isForwardFacing = false

    private var freezeButton: UIButton?
    private var isFrozen = false
    
    private var saveImage: UIImage?
    
    // Labels for classified objects by ARAnchor UUID
    private var anchorLabels = [UUID: String]()
    
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
    
    // MARK: - Main logic
    @objc func toggleFreeze() {
        DispatchQueue.main.async {
            self.isFrozen.toggle()  // Toggle the state of isFrozen
            
            let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
            feedbackGenerator.prepare()
            feedbackGenerator.impactOccurred()

            if self.isFrozen {
                if let userImage = self.saveImage {
                    
                    var inputImage = userImage
                    if self.isForwardFacing {
                        inputImage = userImage.cropCenter(to: 50)!
                    }
                    
                    if let resultImage = processImage(inputImage, self.sceneView, self.isForwardFacing) {
                        self.showImagePopup(combinedImage: resultImage)
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
            let previousFacing = self!.isForwardFacing
            self!.isForwardFacing = self!.detectOrientation(acceleration: data.acceleration)
            
            if self!.isForwardFacing != previousFacing {
                self!.restartSession()
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
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if isForwardFacing {
            startBodyTracking()
        } else {
            startPlaneDetection()
        }
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
        if isForwardFacing {
            width = view.bounds.width * 0.5 // Example size for forward-facing, adjust as needed
        } else {
            width = view.bounds.width * 0.85 // Example size for not forward-facing, adjust as needed
        }
        
        let height = width * 16 / 9 // Maintain 9:16 aspect ratio
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
        sceneView.session.run(configuration)
    }
    
    func startBodyTracking() {
        let configuration = ARBodyTrackingConfiguration()
        sceneView.session.run(configuration)
    }
    
    func detectOrientation(acceleration: CMAcceleration) -> Bool {
        return  acceleration.y < -0.8
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

        let message = String(format: "Detected \(self.identifierString) with %.2f", self.confidence * 100) + "% confidence"
        statusViewController.showMessage(message)
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
        
        // Update the bracket size based on the current state
        updateBracketSize()
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
