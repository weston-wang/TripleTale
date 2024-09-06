//
//  FingerBendDetector.swift
//  TripleTale
//
//  Created by Wes Wang on 9/6/24.
//

import Vision
import UIKit

class FingerBendDetector {

    func detectFingerAngles(in image: UIImage, completion: @escaping ([String: CGFloat]?) -> Void) {
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

            // Extract the finger joint points and calculate angles
            if let fingerAngles = self.calculateFingerAngles(from: firstObservation) {
                completion(fingerAngles)
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

    private func calculateFingerAngles(from observation: VNHumanHandPoseObservation) -> [String: CGFloat]? {
        var fingerAngles = [String: CGFloat]()
        
        // Finger names (thumb, index, middle, ring, pinky)
        let fingers = ["thumb", "indexFinger", "middleFinger", "ringFinger", "littleFinger"]
        
        // Loop through each finger and calculate the bend angle
        for finger in fingers {
            if let angle = self.calculateBendAngle(for: finger, from: observation) {
                fingerAngles[finger] = angle
            }
        }
        
        return fingerAngles
    }

    private func calculateBendAngle(for finger: String, from observation: VNHumanHandPoseObservation) -> CGFloat? {
        // Map finger to the relevant joints
        let jointNameMapping: [String: (VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            "thumb": (.thumbCMC, .thumbMP, .thumbTip),
            "indexFinger": (.indexMCP, .indexPIP, .indexTip),
            "middleFinger": (.middleMCP, .middlePIP, .middleTip),
            "ringFinger": (.ringMCP, .ringPIP, .ringTip),
            "littleFinger": (.littleMCP, .littlePIP, .littleTip)
        ]
        
        // Extract joint names for the given finger
        guard let (joint1, joint2, joint3) = jointNameMapping[finger] else {
            return nil
        }

        // Try to get the recognized points for the joints
        guard let jointPoint1 = try? observation.recognizedPoint(joint1),
              let jointPoint2 = try? observation.recognizedPoint(joint2),
              let jointPoint3 = try? observation.recognizedPoint(joint3),
              jointPoint1.confidence > 0.5, jointPoint2.confidence > 0.5, jointPoint3.confidence > 0.5 else {
            return nil
        }

        // Convert normalized points to CGPoint for easier calculations
        let point1 = CGPoint(x: jointPoint1.location.x, y: 1 - jointPoint1.location.y) // Flip y for image coordinates
        let point2 = CGPoint(x: jointPoint2.location.x, y: 1 - jointPoint2.location.y)
        let point3 = CGPoint(x: jointPoint3.location.x, y: 1 - jointPoint3.location.y)

        // Calculate the angle between the joints (similar to elbow calculation)
        let bendAngle = self.angleBetweenPoints(joint1: point1, joint2: point2, joint3: point3)

        return bendAngle
    }

    private func angleBetweenPoints(joint1: CGPoint, joint2: CGPoint, joint3: CGPoint) -> CGFloat {
        // Create vectors for the finger segments (joint1 -> joint2 and joint2 -> joint3)
        let vector1 = CGVector(dx: joint2.x - joint1.x, dy: joint2.y - joint1.y)
        let vector2 = CGVector(dx: joint3.x - joint2.x, dy: joint3.y - joint2.y)

        // Calculate the dot product and magnitudes
        let dotProduct = (vector1.dx * vector2.dx) + (vector1.dy * vector2.dy)
        let magnitude1 = sqrt(vector1.dx * vector1.dx + vector1.dy * vector1.dy)
        let magnitude2 = sqrt(vector2.dx * vector2.dx + vector2.dy * vector2.dy)

        // Calculate the angle in radians and convert to degrees
        let cosineAngle = dotProduct / (magnitude1 * magnitude2)
        let angleInRadians = acos(cosineAngle)
        let angleInDegrees = angleInRadians * (180.0 / .pi)

        return angleInDegrees // Return the bend angle in degrees
    }
}
