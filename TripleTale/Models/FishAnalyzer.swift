//
//  FishCalculator.swift
//  TripleTale
//
//  Created by Wes Wang on 8/6/23.
//

import UIKit
import Vision
import CoreML

struct FishAnalyzer {
    let inputImage: UIImage
    
    let fishRatio: [String:Float] = ["calico bass":0.58, "yellow tail":0.74, "white sea bass":0.97, "california halibut":0.21]
    let weightFactor: [String:Float] = ["calico bass":1200.0, "yellow tail":800.0, "white sea bass":1200.0, "california halibut":1000.0]

    func classifyFish() -> VNClassificationObservation? {
        guard let ciImage = CIImage(image: inputImage) else {
            fatalError("couldn't convert uiimage to CIImage")
        }
        
        guard let url = Bundle.main.url(forResource: "newFishModel", withExtension: "mlmodelc")
        else {
            fatalError("can't find ML model in path")
        }

        guard let recogModel = try? VNCoreMLModel(for: MLModel(contentsOf: url))
        else {
            fatalError("can't load ML model")
        }
        let request = VNCoreMLRequest(model: recogModel)
        
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        try? handler.perform([request])
        
        guard let results = request.results as? [VNClassificationObservation]
        else {
            fatalError("ML Model did not produce results")
        }
        
        for curResult in results {
            let identifier = curResult.identifier
            let confidence = curResult.confidence
            print("Identifier: \(identifier), Confidence: \(confidence)")
        }
        
        if let firstResult = results.first {
            return firstResult
        } else {
            return nil
        }
    }

    
    func detectFaces(completion: @escaping ([CGRect]?, Error?) -> Void) {
        guard let ciImage = CIImage(image: inputImage) else {
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
    
}
