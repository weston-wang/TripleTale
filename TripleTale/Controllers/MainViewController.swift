//
//  ViewController.swift
//  TripleTale
//
//  Created by Wes Wang on 7/28/23.
//
import CoreML
import Vision
import UIKit
import AVFoundation
import Photos
import CoreGraphics

class MainViewController: UIViewController, UINavigationControllerDelegate {
    var dots: [UIView] = []
    
    var userImage: UIImage?
    
    var fishClass: String?
    var fishLength: Float = 0.0
    var fishWidth: Float = 0.0
    var fishDepth: Float = 0.0
    var fishGirth: Float = 0.0
    var fishRatio: Float = 1.0
    
    var fishWeight: Float = 0.0
    
    var faceWidth: Float = 0.0
    var faceScale: Float = 1.0
    
    var imageScale: Float?
    
    var depthDataProcessor: DepthDataProcessor?
    
    @IBOutlet weak var lengthIcon: UIImageView!
    @IBOutlet weak var weightIcon: UIImageView!
    @IBOutlet weak var lengthText: UILabel!
    @IBOutlet weak var weightText: UILabel!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var resultText: UITextView!
    
    @IBAction func imageSelectButton(_ sender: UIButton) {

        lengthIcon.isHidden = true
        weightIcon.isHidden = true
        resultText.isHidden = true
        
        lengthText.isHidden = true
        weightText.isHidden = true
        
        
        showImagePicker(sender) { cameraImage, depthImage in
            if cameraImage != nil {
                self.detectFish(in: cameraImage!) { (boundingBox, label, error) in
                    if let error = error {
                        print("Error: \(error.localizedDescription)")
                    } else if let boundingBox = boundingBox, let label = label {
                        print("Detected \(label) with bounding box: \(boundingBox)")
                        let imageWithBox = self.drawRectanglesOnImage(image: cameraImage!, boundingBoxes: [boundingBox])
                        
                        self.updateImageView(with: imageWithBox)
                        self.resultText.text = label
                        self.resultText.isHidden = false
                        
                        let croppedCameraImage = self.cropImage(cameraImage!, withNormalizedRect: boundingBox)
                        let croppedDepthImage = self.cropImage(depthImage!, withNormalizedRect: boundingBox)
                        
//                        self.saveImageToGallery(croppedCameraImage!)
//                        self.saveImageToGallery(croppedDepthImage!)
                    } else {
                        print("No fish detected with high confidence.")
                    }
                }
            } else {
                print("No image selected.")
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        depthDataProcessor = DepthDataProcessor()
        
        let scale = UIScreen.main.scale
        print("screen scale \(scale)")
        
        lengthIcon.isHidden = true
        weightIcon.isHidden = true
        resultText.isHidden = true
        
        lengthText.isHidden = true
        weightText.isHidden = true
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "gotoResult" {
            let destinationVC = segue.destination as! ResultViewController
            destinationVC.inputImage = userImage
            destinationVC.detectedFish = fishClass
        }
    }
    
    func showImagePicker(_ sender: UIButton, completion: @escaping (UIImage?, UIImage?) -> Void) {
        depthDataProcessor?.setupCamera()

        // Present the custom camera view controller
        let cameraVC = CameraViewController()
        cameraVC.modalPresentationStyle = .fullScreen

        let overlayView = CameraOverlayView(frame: self.view.bounds)
        cameraVC.cameraOverlay = overlayView.guideForCameraOverlay()

        cameraVC.photoCaptureCompletion = { capturedImage, depthImage in
            print("Completion called with image: \(capturedImage != nil)")
            print("Depth image available: \(depthImage != nil)")
  
            completion(capturedImage, depthImage)
        }

        present(cameraVC, animated: true, completion: nil)
        
    }
}

// MARK: fish calculations
extension MainViewController {
    func detectFish(in image: UIImage, completion: @escaping (CGRect?, String?, Error?) -> Void) {
        // Load the ML model
        guard let modelURL = Bundle.main.url(forResource: "YOLOv3", withExtension: "mlmodelc"),
              let visionModel = try? VNCoreMLModel(for: MLModel(contentsOf: modelURL)) else {
            completion(nil, nil, NSError(domain: "com.example.VisionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to load the model"]))
            return
        }
        
        // Create a request for the Vision Core ML model
        let request = VNCoreMLRequest(model: visionModel) { (request, error) in
            DispatchQueue.main.async {
                if let error = error {
                    completion(nil, nil, error)
                    return
                }
                
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    completion(nil, nil, NSError(domain: "com.example.VisionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No results"]))
                    return
                }
                
                // Find the object with the highest confidence
                if let bestObservation = results.max(by: { a, b in a.confidence < b.confidence }) {
                    // Get the label of the highest confidence
                    let bestLabel = bestObservation.labels.first?.identifier ?? "Unknown"
                    completion(bestObservation.boundingBox, bestLabel, nil)
                } else {
                    completion(nil, nil, NSError(domain: "com.example.VisionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No high-confidence results"]))
                }
            }
        }
        
        // Create a handler and perform the request
        guard let ciImage = CIImage(image: image) else {
            completion(nil, nil, NSError(domain: "com.example.VisionError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"]))
            return
        }
        
        let handler = VNImageRequestHandler(ciImage: ciImage)
        do {
            try handler.perform([request])
        } catch {
            completion(nil, nil, error)
        }
    }
    
    func fishCalculations() {
        var calculator = DotsCalculator(userDots: dots)
        calculator.calculateLengthsBetweenOpposingVertices()
        
        fishLength = calculator.length! / imageScale! * faceScale * 0.9
        fishWidth = calculator.width! / imageScale! * faceScale * 0.9
        fishDepth = fishWidth * fishRatio
        
        fishGirth = .pi * ( 3.0 * (fishWidth + fishDepth) - sqrt( (3.0 * fishDepth + fishWidth) * (fishDepth + 3.0 * fishWidth) ) )
        
        switch fishClass {
        case "calico bass":
            fishWeight = fishLength * fishLength * fishGirth / 1200.0
        case "white sea bass":
            fishWeight = fishLength * fishLength * fishGirth / 1200.0
        case "california halibut":
            fishWeight = fishLength * fishLength * fishLength / 1000.0
        case "yellow tail":
            fishWeight = fishLength * fishGirth * fishGirth / 800.0
        default:
            fishWeight = fishLength * fishGirth * fishGirth / 1200.0
        }
        
        fishWeight = fishWeight / 3.0
        
        resultText.text = "Fish: \(fishClass!)\n Length: \(fishLength) in, Width: \(fishWidth) in, Depth: \(fishDepth), Girth: \(fishGirth), Weight: \(fishWeight) lb"
        
        
        lengthIcon.isHidden = false
        weightIcon.isHidden = false
        resultText.isHidden = false
        lengthText.isHidden = false
        weightText.isHidden = false
        
        resultText.text = "\(fishClass!)"
        lengthText.text = String(format: "%.1f in", fishLength)
        weightText.text = String(format: "%.1f lb", fishWeight)
    }
    
}

// MARK: utility functions
extension MainViewController {
    func updateImageView(with image: UIImage) {
        DispatchQueue.main.async {
            self.imageView.image = image
        }
    }
    
    func saveImageToGallery(_ image: UIImage) {
        // Request authorization
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                // Authorization is given, proceed to save the image
                PHPhotoLibrary.shared().performChanges {
                    // Add the image to an album
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                } completionHandler: { success, error in
                    if let error = error {
                        // Handle the error
                        print("Error saving photo: \(error.localizedDescription)")
                    } else if success {
                        // The image was saved successfully
                        print("Success: Photo was saved to the gallery.")
                    }
                }
            } else {
                // Handle the case of no authorization
                print("No permission to access photo library.")
            }
        }
    }
    
    func drawRectanglesOnImage(image: UIImage, boundingBoxes: [CGRect]) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(at: CGPoint.zero)
        
        let context = UIGraphicsGetCurrentContext()!
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(5.0)
        
        for rect in boundingBoxes {
            let transformedRect = CGRect(x: rect.origin.x * image.size.width,
                                         y: (1 - rect.origin.y - rect.size.height) * image.size.height,
                                         width: rect.size.width * image.size.width,
                                         height: rect.size.height * image.size.height)
            context.stroke(transformedRect)
        }
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return newImage
    }
    
    func cropImage(_ image: UIImage, withNormalizedRect normalizedRect: CGRect) -> UIImage? {
        // Calculate the actual rect based on image size
        let rect = CGRect(
            x: normalizedRect.origin.x * image.size.width,
            y: normalizedRect.origin.y * image.size.height,
            width: normalizedRect.size.width * image.size.width,
            height: normalizedRect.size.height * image.size.height
        )
        
        // Convert UIImage to CGImage to work with Core Graphics
        guard let cgImage = image.cgImage else { return nil }
        
        // Cropping the image with rect
        guard let croppedCgImage = cgImage.cropping(to: rect) else { return nil }
        
        // Convert cropped CGImage back to UIImage
        return UIImage(cgImage: croppedCgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
