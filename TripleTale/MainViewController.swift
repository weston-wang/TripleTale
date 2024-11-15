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
    
    private var tapCounter = 0
    var scaleFactor: Double = 500.0
    var lengthNudge: Double = 1.2
    var widthNudge: Double = 1.2
    
    private var cameraButton: UIButton?
    
    var bracketView: BracketView?
    private var imagePortion: CGFloat = 1.0

    let motionManager = CMMotionManager()
    private var isForwardFacing = false
    
    let armPose3DDetector = ArmPose3DDetector()

    // Classification results
    private var identifierString = ""
    private var confidence: VNConfidence = 0.0
    private var boundingBox: CGRect?
    
    // The pixel buffer being held for analysis; used to serialize Vision requests.
    private var currentBuffer: CVPixelBuffer?
    private var currentImage: UIImage?
    private var galleryImage: UIImage?
    private var depthImage: UIImage?
    private var visionQueue = DispatchQueue(label: "com.tripleTale.visionQueue")

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

        // DISABLED: Call the function to create and add the gallery button
        setupGalleryButton()

        // Start AR
        startPlaneDetection()

        // Initial bracket update
        updateBracketSize()
        
        // DISABLED: Start Device Motion Updates
//        startDeviceMotionUpdates()
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
    
    @objc private func loadImageFromGallery() {
        let imagePickerController = UIImagePickerController()
        imagePickerController.delegate = self
        imagePickerController.sourceType = .photoLibrary
        present(imagePickerController, animated: true, completion: nil)
    }
    
    @objc func handleCameraButtonPress() {
        // Haptic feedback
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()

        // Call processImage
        processCameraImage()
    }
    
    func processGalleryImage(_ inputImage: UIImage?) {
        if let image = inputImage?.downscale(to: 1280) {
            
            var distanceToFace: CGFloat = 5.0  // Distance from the camera to the face in feet, nominal
            var distanceToFish: CGFloat = 4.0  // Distance from torso to object in feet (1 foot in front)
            
            let faceLengthIn: Float = 7.3        // average adult face length 7.0 - 7.8 inch
            let minGap: Float = 0.1             // wrist should be at least 0.1 m in front of torso
            let verticesToForkRatio = 0.95
            
            var wristAndHeadDistance = ""
            
            var facePoint: VNPoint = VNPoint(x: 0.0, y: 0.0)
            
            var leftWristPoint: VNPoint = VNPoint(x: 0.0, y: 0.0)
            var rightWristPoint: VNPoint = VNPoint(x: 0.0, y: 0.0)
            var distanceToLeftWrist: CGFloat = 4.0
            var distanceToRightWrist: CGFloat = 4.0
            
            let resizedImage = resizeImageForModel(image)
            self.processDepthImage(from: resizedImage!) { depthImage in
                let resizedDepthImage = resizeDepthMap(depthImage, to: image.size)
                
                let thresholdedImage = thresholdImage(resizedDepthImage!, threshold: 255 * 0.85)
                saveImageToGallery(thresholdedImage!)

                self.armPose3DDetector.detectWrists(in: resizedImage!) { pointsInImage, distancesInM, detected in
                    if detected {
                        print("2D Points in Image: \(pointsInImage)")
                        print("Distances to camera: \(distancesInM)")
                        
                        facePoint = pointsInImage["head"]!
                        
                        leftWristPoint = pointsInImage["leftWrist"]!
                        rightWristPoint = pointsInImage["rightWrist"]!
                        
                        distanceToLeftWrist = CGFloat(distancesInM["leftWrist"]! * 3.28084)
                        distanceToRightWrist = CGFloat(distancesInM["rightWrist"]! * 3.28084)

                        let distanceToFaceInM = distancesInM["head"]
                        let distanceToWristInM = [distancesInM["leftWrist"], distancesInM["rightWrist"]].compactMap({ $0 }).min()
                        
                        // check if wrist depth map is valid,  assuming fish depth is close to 255
                        wristAndHeadDistance = "face to cam: \(distanceToFaceInM!) m, left wrist: \(distancesInM["leftWrist"]!) m, right wrist: \(distancesInM["rightWrist"]!) m"
                        
                        if (distanceToFaceInM! - distanceToWristInM!) > minGap {
                            distanceToFace = CGFloat(distanceToFaceInM! * 3.28084)  // conver meters to inches
                            distanceToFish = CGFloat(distanceToWristInM! * 3.28084)
                            
                            print("reassigning distance to fish: \(distanceToFish) ft")
                            print("reassigning distance to face: \(distanceToFace) ft")
                        }
                    }
                }
        
                let (vertices, ellipse, contour) = findDepthEllipseVertices(from: resizedDepthImage!, debug: false)
                
                print("image size: \(image.size), depth size: \(resizedDepthImage!.size)")
                
                let dim1 = distanceBetween(vertices![0], vertices![2])
                let dim2 = distanceBetween(vertices![1], vertices![3])
                
                let fishLength = [dim1, dim2].max()
                
                print("detected fish length: \(fishLength!) px")
                
                if let topFaceRect = detectTopFaceBoundingBox(in: image) {
                    print("detected face: \(topFaceRect) px")
                    
                    // move object to same plane as fish, still in pixels
                    let updatedFishLength = scaleObjectToFacePlane(measuredLength: CGFloat(fishLength!), faceDistanceToCamera: distanceToFace, objectDistanceToCamera: distanceToFish)
                    
                    print("updated fish length: \(updatedFishLength) px")
                    
                    wristAndHeadDistance = wristAndHeadDistance + "\n fish length: \(fishLength!) px, face length: \(topFaceRect.height) px"
                    
                    // convert to real world units in inches
                    let fishLengthIn = updatedFishLength / topFaceRect.height * CGFloat(faceLengthIn) / verticesToForkRatio
            
                    if let combinedImage = generateDebugImage(image, topFaceRect, facePoint, distanceToFace, leftWristPoint, distanceToLeftWrist, rightWristPoint, distanceToRightWrist, contour!, ellipse!, vertices!, fishLength!) {
                        
                        let textPoint = CGPoint(x: 0, y: combinedImage.size.height - 100)
                        let finalImage = combinedImage.imageWithText("\(String(format: "%.2f", fishLengthIn)) in", atPoint: textPoint, fontSize: 100, textColor: UIColor.white)!
                        
                        saveImageToGallery(finalImage)
                        
                        // Ensure that the UI update (showing the image popup) happens on the main thread
                        DispatchQueue.main.async {
                            self.showImagePopup(combinedImage: finalImage)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.view.showToast(message: "Could not isolate fish from scene, too much clutter!")
                        }
                    }
                    
                } else {
                    print("No face detected.")
                }
            }
        }
    }
    
    func processCameraImage() {
        DispatchQueue.main.async {
            var image: UIImage?
            
            // forward facing case is disabled for now, now in this conditional
            if self.isForwardFacing, let depthImage = self.depthImage {
                let croppedImage = depthImage.croppedToAspectRatio(size: depthImage.size)
                image = croppedImage?.resized(to: depthImage.size)
            } else {
                image = self.captureFrameAsUIImage(from: self.sceneView)
            }

            if let image = image {
                self.calculateAndDisplayWeight(with: image)
            }
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
                          
        if let combinedImage = generateResultImage(self.currentImage!, nil , widthInInches, lengthInInches, heightInInches, circumferenceInInches, weightInLb, self.identifierString) {
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

        button.isHidden = false

        button.addTarget(self, action: #selector(handleCameraButtonPress), for: .touchUpInside)

        // Add the button to the view
        view.addSubview(button)
    }
    
    // Function to create and add the button with an SF Symbol
    private func setupGalleryButton() {
        let galleryButton = UIButton(type: .system)

        // Set the SF Symbol with a larger configuration
        let largeConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold, scale: .large)
        let symbolImage = UIImage(systemName: "photo.artframe.circle", withConfiguration: largeConfig)
        galleryButton.setImage(symbolImage, for: .normal)

        // Optionally, set the tint color for the button
        galleryButton.tintColor = .white

        galleryButton.addTarget(self, action: #selector(loadImageFromGallery), for: .touchUpInside)
        galleryButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(galleryButton)
        
        // Set constraints for the button to be at the bottom right corner
        NSLayoutConstraint.activate([
            galleryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            galleryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let selectedImage = info[.originalImage] as? UIImage {
            self.galleryImage = selectedImage
            processGalleryImage(selectedImage)
        }
        dismiss(animated: true, completion: nil)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
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
    
    func startPlaneDetection() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Enable depth data (only works on LiDAR-equipped devices)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        } else {
            print("Device does not support scene depth")
        }
        
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
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
//                self.depthImage = getDepthMap(from: currentFrame)

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


