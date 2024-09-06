//
//  FingerWidthDetector.swift
//  TripleTale
//
//  Created by Wes Wang on 9/6/24.
//

import Vision
import UIKit

class FingerWidthDetector {

    func detectFingerWidths(in image: UIImage, completion: @escaping ([String: CGFloat]?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }

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

            // Extract the finger joint points and calculate widths
            if let fingerWidths = self.calculateFingerWidths(from: firstObservation) {
                completion(fingerWidths)
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

    private func calculateFingerWidths(from observation: VNHumanHandPoseObservation) -> [String: CGFloat]? {
        var fingerWidths = [String: CGFloat]()
        
        // Finger names (thumb, index, middle, ring, pinky)
        let fingers = ["thumb", "indexFinger", "middleFinger", "ringFinger", "littleFinger"]
        
        // Loop through each finger and calculate the width
        for finger in fingers {
            if let width = self.calculateWidthForFinger(finger, from: observation) {
                fingerWidths[finger] = width
            }
        }
        
        return fingerWidths
    }

    private func calculateWidthForFinger(_ finger: String, from observation: VNHumanHandPoseObservation) -> CGFloat? {
        // Mapping of fingers to the relevant points for estimating width
        let jointNameMapping: [String: (VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            "thumb": (.thumbCMC, .thumbTip),
            "indexFinger": (.indexMCP, .indexTip),
            "middleFinger": (.middleMCP, .middleTip),
            "ringFinger": (.ringMCP, .ringTip),
            "littleFinger": (.littleMCP, .littleTip)
        ]
        
        // Extract the joints for the finger's width calculation
        guard let (knuckleJoint, tipJoint) = jointNameMapping[finger] else {
            return nil
        }

        // Try to get the recognized points for the knuckle and tip joints
        guard let knucklePoint = try? observation.recognizedPoint(knuckleJoint),
              let tipPoint = try? observation.recognizedPoint(tipJoint),
              knucklePoint.confidence > 0.5, tipPoint.confidence > 0.5 else {
            return nil
        }

        // Convert normalized points to CGPoint for easier calculations
        let knuckleCGPoint = CGPoint(x: knucklePoint.location.x, y: 1 - knucklePoint.location.y) // Flip y for image coordinates
        let tipCGPoint = CGPoint(x: tipPoint.location.x, y: 1 - tipPoint.location.y)

        // Calculate the width of the finger by estimating the perpendicular distance
        let fingerWidth = self.distanceBetweenPoints(knuckleCGPoint, tipCGPoint)

        return fingerWidth
    }

    private func distanceBetweenPoints(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        // Simple distance formula between two points
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return sqrt(dx * dx + dy * dy)
    }
}
