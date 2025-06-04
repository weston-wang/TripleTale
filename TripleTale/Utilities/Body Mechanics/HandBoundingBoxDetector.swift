//
//  HandBoundingBoxDetector.swift
//  TripleTale
//
//  Created by Wes Wang on 9/6/24.
//
import Vision
import UIKit

class HandBoundingBoxDetector {

    func detectHandBoundingBox(in image: UIImage, completion: @escaping (CGRect?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Create a VNImageRequestHandler for the image
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Create a VNDetectHumanHandPoseRequest
        let request = VNDetectHumanHandPoseRequest { (request, error) in
            if let error = error {
                print("Hand pose detection error: \(error)")
                completion(nil)
                return
            }

            // Process the request results
            guard let observations = request.results as? [VNHumanHandPoseObservation], let firstObservation = observations.first else {
                completion(nil)
                return
            }

            // Get the bounding box for the hand by finding the extremities of the recognized points
            if let boundingBox = self.calculateHandBoundingBox(from: firstObservation, imageWidth: imageWidth, imageHeight: imageHeight) {
                completion(boundingBox)
            } else {
                completion(nil)
            }
        }

        // Perform the request
        do {
            try requestHandler.perform([request])
        } catch {
            print("Failed to perform request: \(error)")
            completion(nil)
        }
    }

    private func calculateHandBoundingBox(from observation: VNHumanHandPoseObservation, imageWidth: CGFloat, imageHeight: CGFloat) -> CGRect? {
        var minX: CGFloat = imageWidth
        var maxX: CGFloat = 0.0
        var minY: CGFloat = imageHeight
        var maxY: CGFloat = 0.0

        // Iterate over all possible joints and find the extremities
        let jointNames: [VNHumanHandPoseObservation.JointName] = [
            .wrist, .thumbCMC, .thumbMP, .thumbTip,
            .indexMCP, .indexPIP, .indexTip,
            .middleMCP, .middlePIP, .middleTip,
            .ringMCP, .ringPIP, .ringTip,
            .littleMCP, .littlePIP, .littleTip
        ]

        for jointName in jointNames {
            if let point = try? observation.recognizedPoint(jointName), point.confidence > 0.5 {
                let xInPixels = point.location.x * imageWidth
                let yInPixels = (1.0 - point.location.y) * imageHeight // Flip y-axis for image coordinates

                minX = min(minX, xInPixels)
                maxX = max(maxX, xInPixels)
                minY = min(minY, yInPixels)
                maxY = max(maxY, yInPixels)
            }
        }

        // Return nil if no points were detected
        if minX == imageWidth && maxX == 0.0 && minY == imageHeight && maxY == 0.0 {
            return nil
        }

        // The bounding box is formed by the extreme points
        let boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return boundingBox
    }
}
