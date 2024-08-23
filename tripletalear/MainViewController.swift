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

class MainViewController: UIViewController, ARSCNViewDelegate {

    var sceneView: ARSCNView!
    
    private var tapCounter = 0
    var scaleFactor: Double = 500.0
    var lengthNudge: Double = 1.2
    var widthNudge: Double = 1.2
    
    private var freezeButton: UIButton?
    private var isFrozen = false
    
    var bracketView: BracketView?
    private var imagePortion: CGFloat = 1.0

    let motionManager = CMMotionManager()
    private var isForwardFacing = false
    
    // Classification results
    private var identifierString = ""
    private var confidence: VNConfidence = 0.0
    private var boundingBox: CGRect?
    
    // The pixel buffer being held for analysis; used to serialize Vision requests.
    private var currentBuffer: CVPixelBuffer?
    private var currentImage: UIImage?
    private var depthImage: UIImage?
    private var visionQueue = DispatchQueue(label: "visionQueue")

    /// The ML model to be used for detection of fish
    private var tripleTaleModel: TripleTaleV2 = {
        do {
            let configuration = MLModelConfiguration()
            return try TripleTaleV2(configuration: configuration)
        } catch {
            fatalError("Couldn't create TripleTaleV2 due to: \(error)")
        }
    }()
    
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
    
    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView = ARSCNView(frame: self.view.frame)
        sceneView.delegate = self
        view.addSubview(sceneView)
        
        // Add the bracket view to the main view
        bracketView = BracketView(frame: view.bounds)
        bracketView?.isUserInteractionEnabled = false // Make sure it doesn't intercept touch events
        view.addSubview(bracketView!)
        
        // Add the freeze button and other UI elements
        freezeButton = createFreezeButton()
        view.addSubview(freezeButton!)
        
        // Create a transparent view for the bottom left corner
        let cornerView = createCornerView(withSize: 100)
        view.addSubview(cornerView)

        // Start AR
        startPlaneDetection()

        // Initial bracket update
        updateBracketSize()
        
        // Start Device Motion Updates
        startDeviceMotionUpdates()
    }
    
    func startBodyTracking() {
        // Create and run body tracking configuration
        let configuration = ARBodyTrackingConfiguration()
        
        // Enable depth data (only works on LiDAR-equipped devices)
        if ARBodyTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        } else if ARBodyTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARBodyTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        } else {
            print("Device does not support scene depth")
        }
        
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func getDepthMap(from currentFrame: ARFrame) -> UIImage? {
        // First, try to get sceneDepth from LiDAR-equipped devices
        if let sceneDepth = currentFrame.sceneDepth {
            return pixelBufferToUIImage(pixelBuffer: sceneDepth.depthMap)
        }
        
        // If sceneDepth is not available, check for smoothedSceneDepth (better quality for non-LiDAR devices)
        if let smoothedSceneDepth = currentFrame.smoothedSceneDepth {
            return pixelBufferToUIImage(pixelBuffer: smoothedSceneDepth.depthMap)
        }
        
        // Fallback to estimatedDepthData if smoothedSceneDepth is not available
        if let estimatedDepthData = currentFrame.estimatedDepthData {
            return pixelBufferToUIImage(pixelBuffer: estimatedDepthData)
        }
        
        // If no depth data is available, return nil
        print("Depth data not available on this device.")
        return nil
    }
    
    func startPlaneDetection() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    
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
    
    @objc func toggleFreeze() {
        DispatchQueue.main.async {
            self.isFrozen.toggle()  // Toggle the state of isFrozen
            
            let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
            feedbackGenerator.prepare()
            feedbackGenerator.impactOccurred()
            
            if self.isFrozen {
                if let image = self.captureFrameAsUIImage(from: self.sceneView) {
                    self.depthImage = self.depthImage!.croppedToAspectRatio(size: image.size)
                    self.depthImage = self.depthImage!.resized(to: image.size)
                    saveImageToGallery(self.depthImage!)

                    self.calculateAndDisplayWeight(with: image, at: self.imagePortion)
                }
                
                self.isFrozen.toggle()
            }
        }
    }
    
    func calculateAndDisplayWeight(with image: UIImage, at portion: CGFloat) {
        let normalizedVertices = findEllipseVertices(from: image, for: portion, debug: true)!

        let fishAnchors = buildRealWorldVerticesAnchors(self.sceneView, normalizedVertices, image.size)
        
        var (width, length, height) = measureVertices(fishAnchors.0, fishAnchors.3, fishAnchors.1, fishAnchors.2)
        
        length = length * Float(self.lengthNudge)
        width = width * Float(self.widthNudge)
        
        let circumference = calculateCircumference(majorAxis: width, minorAxis: height)
        
        let (weightInLb, widthInInches, lengthInInches, heightInInches, circumferenceInInches) = calculateWeight(width, length, height, circumference, self.scaleFactor)
                          
        if let combinedImage = generateResultImage(self.currentImage!, nil , widthInInches, lengthInInches, heightInInches, circumferenceInInches, weightInLb, self.identifierString) {
            self.showImagePopup(combinedImage: combinedImage)
        } else {
            self.view.showToast(message: "Could not isolate fish from scene, too much clutter!")
        }
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

        button.isHidden = false

        button.addTarget(self, action: #selector(toggleFreeze), for: .touchUpInside)
        return button
    }
    
    func createCornerView(withSize size: CGFloat, backgroundColor: UIColor = .clear) -> UIView {
        let cornerView = UIView()
        cornerView.backgroundColor = backgroundColor
        
        // Set the frame to place the view near the bottom left corner
        let xPosition: CGFloat = 20 // Adjust as needed
        let yPosition: CGFloat = view.bounds.height - size - 20 // Adjust as needed
        cornerView.frame = CGRect(x: xPosition, y: yPosition, width: size, height: size)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        cornerView.addGestureRecognizer(tapGesture)

        return cornerView
    }
    
    func startDeviceMotionUpdates() {
        // Check if the motion is available
        guard motionManager.isDeviceMotionAvailable else {
            print("Motion Sensor is not available")
            return
        }

        // Start Device Motion Updates
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
            guard let self = self else { return }
            guard let motion = motion else { return }

            let previousFacing = self.isForwardFacing
            self.isForwardFacing = self.detectOrientation(attitude: motion.attitude)

            if self.isForwardFacing != previousFacing {
                // Update the bracket size based on the current state
                self.updateBracketSize()
            }
        }
    }
    
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
    
    func detectOrientation(attitude: CMAttitude) -> Bool {
        return  attitude.pitch * 180 / .pi > 60.0
    }
    
    func captureFrameAsUIImage(from arSCNView: ARSCNView) -> UIImage? {
        // Capture the current view as a UIImage
        let image = arSCNView.snapshot()
        return image
    }
    
    func handleResult(identifier: String, confidence: VNConfidence, boundingBox: CGRect?) {
        // Update your UI or perform other actions with the identifier, confidence, and boundingBox
        self.identifierString = identifier
        self.confidence = confidence
        self.boundingBox = boundingBox ?? .zero
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let currentFrame = sceneView.session.currentFrame else { return }

        // Get the pixel buffer from the current ARFrame
        currentBuffer = currentFrame.capturedImage
        
        // Lock the pixel buffer base address
        CVPixelBufferLockBaseAddress(currentBuffer!, .readOnly)
        
        // Perform the ML request on the visionQueue
        let orientation = CGImagePropertyOrientation(rawValue: UInt32(UIDevice.current.orientation.rawValue))!
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentBuffer!, orientation: orientation)
        
        visionQueue.async {
            defer {
                // Unlock the pixel buffer when done, allowing the next buffer to be processed
                CVPixelBufferUnlockBaseAddress(self.currentBuffer!, .readOnly)
            }
            
            do {
                // Perform the ML request
                try requestHandler.perform([self.mlRequest])
                
                // Convert the pixel buffer to UIImage
                self.currentImage = pixelBufferToUIImage(pixelBuffer: self.currentBuffer!)
                self.depthImage = self.getDepthMap(from: currentFrame)

            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
    }
    
    // This method is called whenever an ARAnchor is added to the session
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if !(anchor is ARPlaneAnchor) {
            // Create a visual representation of the anchor (e.g., a sphere)
            let sphere = SCNSphere(radius: 0.002) // 0.2 cm sphere
            
            sphere.firstMaterial?.diffuse.contents = UIColor.red // Example color

            // Create a node with this geometry
            let sphereNode = SCNNode(geometry: sphere)

            // Attach the node to the anchor's node
            node.addChildNode(sphereNode)
        }
    }
    
}


