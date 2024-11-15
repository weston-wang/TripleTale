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

    private var tapCounter = 0
    var scaleFactor: Double = 500.0
    var lengthNudge: Double = 1.2
    var widthNudge: Double = 1.2
    
    private var cameraButton: UIButton?
    private var feedbackLabel: UILabel?
    
    var bracketView: BracketView?
    private var imagePortion: CGFloat = 1.0

    private var isForwardFacing = false
    
    // Classification results
    private var identifierString = ""
    private var confidence: VNConfidence = 0.0
    private var boundingBox: CGRect?
    
    // The pixel buffer being held for analysis; used to serialize Vision requests.
    private var currentBuffer: CVPixelBuffer?
    private var currentImage: UIImage?
    private var galleryImage: UIImage?
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
        
        // Add the bracket view to the main view
        bracketView = BracketView(frame: view.bounds)
        bracketView?.isUserInteractionEnabled = false // Make sure it doesn't intercept touch events
        view.addSubview(bracketView!)
        
        // Create a transparent view for the bottom left corner
        createCornerView(withSize: 100)
        
        // Call the function to create and add the camera button
        setupCameraButton()

        // Start AR
        startPlaneDetection()

        // Initial bracket update
        updateBracketSize()
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
    
    @objc func handleCameraButtonPress() {
        // Haptic feedback
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()

        // Capture the current frame
        if let image = captureFrameAsUIImage(from: sceneView) {
            calculateAndDisplayWeight(with: image)
        } else {
            self.view.showToast(message: "Could not capture image from scene!")
        }
    }
    
    func calculateAndDisplayWeight(with image: UIImage) {
        let normalizedVertices = findEllipseVertices(from: image, for: self.imagePortion, debug: true)!

        let fishAnchors = buildRealWorldVerticesAnchors(self.sceneView, normalizedVertices, image.size)
        
        var (width, length, height) = measureVertices(fishAnchors.0, fishAnchors.3, fishAnchors.1, fishAnchors.2)
        
        length = length * Float(self.lengthNudge)
        width = width * Float(self.widthNudge)
        
        let circumference = calculateCircumference(majorAxis: width, minorAxis: height)
        
        let (weightInLb, widthInInches, lengthInInches, heightInInches, circumferenceInInches) = calculateWeight(width, length, height, circumference, self.scaleFactor)
                          
        if let combinedImage = generateResultImage(image, nil , widthInInches, lengthInInches, heightInInches, circumferenceInInches, weightInLb, self.identifierString) {
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
    
    func startPlaneDetection() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]

        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func captureFrameAsUIImage(from arSCNView: ARSCNView) -> UIImage? {
        // Capture the current view as a UIImage
        let image = arSCNView.snapshot()
        return image
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
        } else {
            // Enable the camera button
            DispatchQueue.main.async { [weak self] in
                self?.cameraButton?.isEnabled = true
                self?.cameraButton?.alpha = 1.0 // Reset the alpha for enabled state
                
                self?.feedbackLabel?.text = "Ready!"
                self?.feedbackLabel?.textColor = .white // Change text color for clarity
            }
            
            // Create a visual representation of the anchor (e.g., a sphere)
            let sphere = SCNSphere(radius: 0.002) // 0.2 cm sphere
            
            sphere.firstMaterial?.diffuse.contents = UIColor.green // Example color

            // Create a node with this geometry
            let sphereNode = SCNNode(geometry: sphere)

            // Attach the node to the anchor's node
            node.addChildNode(sphereNode)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("Session error: \(error.localizedDescription)")
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            // Do nothing, everything is fine
            break
        case .notAvailable, .limited:
            DispatchQueue.main.async { [weak self] in
                self?.cameraButton?.isEnabled = false
                self?.cameraButton?.alpha = 0.5
                self?.feedbackLabel?.text = "Reinitiating..."
                self?.feedbackLabel?.textColor = .gray
            }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        print("Frame updated at: \(frame.timestamp)")
    }
    
}


