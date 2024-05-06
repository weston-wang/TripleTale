//
//  ResultController.swift
//  TripleTale
//
//  Created by Wes Wang on 7/28/23.
//

import CoreML
import Vision
//import VisionKit
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

class ResultViewController: UIViewController {
    var inputImage: UIImage?
    var detectedFish: String?
    
//    let interaction = ImageAnalysisInteraction()

    @IBOutlet weak var resultImage: UIImageView!
    
    @IBOutlet weak var resultText: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let userImage = fixImageOrientation(image: inputImage!)

//        let analyzer = ImageAnalyzer()
        
        let resImage = cropObjectBasedOnSaliency(inputImage: userImage)
        
        self.resultImage.image = resImage
        
//        self.resultImage.addInteraction(interaction)
//        interaction.preferredInteractionTypes = .imageSubject
        
        
    
//      let cgImage = userImage.cgImage


//        let requestHandler = VNImageRequestHandler(cgImage: cgImage!, options: [:])
//        let contourRequest = VNDetectContoursRequest()
//
//        do {
//            try requestHandler.perform([contourRequest])
//
//            // Get the results from the request
//            guard let results = contourRequest.results as? [VNContoursObservation] else {
//                return
//            }
//
//            // Calculate the region around the center for contour detection
//            let centerRegion = CGRect(x: userImage.size.width / 4,
//                                      y: userImage.size.height / 4,
//                                      width: userImage.size.width / 2,
//                                      height: userImage.size.height / 2)
//
//            // Create a copy of the image to draw the contours on
//            UIGraphicsBeginImageContext(userImage.size)
//            userImage.draw(at: CGPoint.zero)
//            let context = UIGraphicsGetCurrentContext()
//
//            // Set the line color and width for drawing contours
//            context?.setStrokeColor(UIColor.green.cgColor)
//            context?.setLineWidth(5.0)
//
//            // Flip the context vertically
//           context?.scaleBy(x: 1, y: -1)
//           context?.translateBy(x: 0, y: -userImage.size.height)
//
//            // Define a threshold for minimum contour area
//            let minContourArea: CGFloat = 0.8  // Adjust this value as needed
//
//
//            for contourObservation in results {
//                // Calculate the area of the contour
//                let contourArea = contourObservation.normalizedPath.boundingBox.size.width * contourObservation.normalizedPath.boundingBox.size.height
//
//                // Only draw if the contour area is above the threshold
//                if contourArea >= minContourArea {
//                    // Access contour path
//                    let contourPath = contourObservation.normalizedPath
//
//                    // Draw the contour path
//                    let scaledPath = UIBezierPath(cgPath: contourPath)
//                    scaledPath.apply(CGAffineTransform(scaleX: userImage.size.width, y: userImage.size.height))
//                    context?.addPath(scaledPath.cgPath)
//                    context?.strokePath()
//                }
//
////                // Access the bounding box of the contour
////                let boundingBox = contourObservation.normalizedPath.boundingBox
////
////                // Check if the contour is within the center region
////                if centerRegion.contains(boundingBox) {
////                    // Access contour path
////                    let contourPath = contourObservation.normalizedPath
////
////                    // Draw the contour path
////                    let scaledPath = UIBezierPath(cgPath: contourPath)
////                    scaledPath.apply(CGAffineTransform(scaleX: userImage.size.width, y: userImage.size.height))
////                    context?.addPath(scaledPath.cgPath)
////                    context?.strokePath()
////                }
//            }
//
//            // Get the drawn image from the graphics context
//            let drawnImage = UIGraphicsGetImageFromCurrentImageContext()
//
//            // End the graphics context
//            UIGraphicsEndImageContext()
//
//            // Display the image with drawn contours
//            self.resultImage.image = drawnImage
//
//        } catch {
//            print("Error performing contour detection: \(error)")
//        }
        
        // 1. Detect face
        // 2. Crop image to everything below the face
        // 3. Find contour
        // 4. Fit elipse or lines
        // 5. use detected fish class to estimate girth
        // 6. use detected fish class to estimate weight L*G^2/const
        
//        let countourImage = OpenCVWrapper.detectAndShowContour(userImage)
//        self.resultImage.image = countourImage
        
        
//        detectFaces(in: userImage) { faceRects, error in
//            if let error = error {
//                print("Error detecting faces: \(error)")
//                return
//            }
//
//            if let faceRects = faceRects {
//                // Use faceRects to draw rectangles around detected faces or perform any other desired actions.
//                // Each CGRect in the array represents a detected face's bounding box in the image.
//                print("Detected \(faceRects.count) faces.")
//
//                let imageWithRectangles = self.drawRectanglesOnImage(image: userImage, boundingBoxes: faceRects)
//
//                self.resultImage.image = imageWithRectangles
//
//            } else {
//                print("No faces detected.")
//                self.resultImage.image = self.inputImage
//
//            }
//        }
        

    }
    func cropObjectBasedOnSaliency(inputImage: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: inputImage) else {
            return nil
        }
        
        let options: [VNImageOption: Any] = [:]
        let handler = VNImageRequestHandler(ciImage: ciImage, options: options)
        
        do {
//            let request = VNGenerateForegroundInstanceMaskRequest()
            if #available(iOS 17.0, *) {
//                let request = VNGenerateForegroundInstanceMaskRequest()
//                
//                #if targetEnvironment(simulator)
//                    request.usesCPUOnly = true
//                #endif
//                
//                let handler = VNImageRequestHandler(cgImage: ciImage.cgImage!)
//                try handler.perform([request])
//                
//                guard let result = request.results?.first else {
//                    return nil
//                }
//                
//                let output = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
//                print("done")
            } else {
                // Fallback on earlier versions
                let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
                try handler.perform([saliencyRequest])
                
                if let saliencyObservation = saliencyRequest.results?.first as? VNSaliencyImageObservation {
                    let salientRect = saliencyObservation.salientObjects?.first?.boundingBox ?? CGRect.zero
                    let croppedCIImage = ciImage.cropped(to: salientRect)
                    
                    let context = CIContext()
                    if let croppedCGImage = context.createCGImage(croppedCIImage, from: croppedCIImage.extent) {
                        return UIImage(cgImage: croppedCGImage)
                    }
                }
            }
        
        } catch {
            print("Error processing image: \(error)")
            return nil
        }
        
        return nil
    }

    
    
    func cropObject(from image: UIImage, with observation: VNRecognizedObjectObservation) -> UIImage? {
        let imageSize = image.size
        let boundingBox = observation.boundingBox
        
        // Convert the bounding box coordinates from normalized (0 to 1) to image coordinates
        let rect = CGRect(x: boundingBox.origin.x * imageSize.width,
                          y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height,
                          width: boundingBox.width * imageSize.width,
                          height: boundingBox.height * imageSize.height)
        
        // Get the CGImage of the original image
        guard let cgImage = image.cgImage else { return nil }
        
        // Create a new CGImage by cropping the original image using the bounding box
        guard let croppedCGImage = cgImage.cropping(to: rect) else { return nil }
        
        // Create a new UIImage from the cropped CGImage
        return UIImage(cgImage: croppedCGImage)
    }
    
    func performImageSegmentation(image: UIImage) -> MLMultiArray? {
        var segmentationResult: MLMultiArray?
        guard let url = Bundle.main.url(forResource: "DeepLabV3", withExtension: "mlmodelc")
        else {
            fatalError("can't find ML model in path")
        }

        guard let model = try? VNCoreMLModel(for: MLModel(contentsOf: url)) else {
            fatalError("Failed to load Core ML model.")
        }

        let request = VNCoreMLRequest(model: model) { request, error in
            guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
                  let segmentationMap = observations.first?.featureValue.multiArrayValue else {
                fatalError("Error processing the image.")
            }

            segmentationResult = segmentationMap
        }

        let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("Error performing segmentation.")
        }
        
        return segmentationResult
    }


    func fixImageOrientation(image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            // The image is already upright; no need to fix orientation.
            return image
        }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let fixedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let resultImage = fixedImage else {
            // Return the original image if the fix fails.
            return image
        }

        return resultImage
    }
    
    func drawRectanglesOnImage(image: UIImage, boundingBoxes: [CGRect]) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(at: CGPoint.zero)
        
        let context = UIGraphicsGetCurrentContext()!
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(2.0)
        
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
    
    func detectFaces(in image: UIImage, completion: @escaping ([CGRect]?, Error?) -> Void) {
        guard let ciImage = CIImage(image: image) else {
            completion(nil, NSError(domain: "InvalidImage", code: 0, userInfo: nil))
            return
        }
        
        // Create a face detection request
        let faceRequest = VNDetectFaceRectanglesRequest { request, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let results = request.results as? [VNFaceObservation] else {
                completion(nil, nil)
                return
            }
            
            // Extract bounding boxes of detected faces
            let faceRects = results.map { observation in
                return observation.boundingBox
            }
            
            completion(faceRects, nil)
        }
        
        // Perform face detection on the given CIImage
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        do {
            try handler.perform([faceRequest])
        } catch {
            completion(nil, error)
        }
    }
    
    
}

extension UIImage {
    func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)

        guard let buffer = pixelBuffer, status == kCVReturnSuccess else { return nil }

        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }

        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        guard let cgImage = self.cgImage else { return nil }
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return pixelBuffer
    }
    
//    func detectContours(in image: UIImage) -> [CvContour] {
//        guard let mat = image.cvMat() else { return [] }
//
//        var contours: [CvContour] = []
//        var hierarchy = CvHierarchy()
//
//        cvFindContours(mat, &hierarchy, &contours, MemoryLayout<CvContour>.size, CV_RETR_TREE, CV_CHAIN_APPROX_SIMPLE)
//
//        return contours
//    }

}

//extension UIImage {
//    func cvMat() -> Mat? {
//        guard let cgImage = self.cgImage else { return nil }
//        return Mat(cgImage: cgImage)
//    }
//}
