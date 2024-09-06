//
//  ElbowAngleDetector.swift
//  TripleTale
//
//  Created by Wes Wang on 9/6/24.
//

import UIKit
import Vision

class ElbowAngleDetector {

    func detectElbowAngle(in image: UIImage, completion: @escaping (CGFloat?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }

        // Create a VNImageRequestHandler for the image
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Create a VNDetectHumanBodyPoseRequest
        let request = VNDetectHumanBodyPoseRequest { (request, error) in
            if let error = error {
                print("Pose detection error: \(error)")
                completion(nil)
                return
            }

            // Process the request results
            guard let observations = request.results as? [VNHumanBodyPoseObservation], let firstObservation = observations.first else {
                completion(nil)
                return
            }

            // Extract the body joint points
            if let elbowAngle = self.calculateElbowAngle(from: firstObservation) {
                completion(elbowAngle)
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

    private func calculateElbowAngle(from observation: VNHumanBodyPoseObservation) -> CGFloat? {
        // Get the 2D points of interest: shoulder, elbow, and wrist
        guard let shoulder = try? observation.recognizedPoint(.leftShoulder),
              let elbow = try? observation.recognizedPoint(.leftElbow),
              let wrist = try? observation.recognizedPoint(.leftWrist),
              shoulder.confidence > 0.5, elbow.confidence > 0.5, wrist.confidence > 0.5 else {
            return nil
        }

        // Convert the normalized points to CGPoint
        let shoulderPoint = CGPoint(x: shoulder.location.x, y: 1 - shoulder.location.y) // Flip y for image coordinate system
        let elbowPoint = CGPoint(x: elbow.location.x, y: 1 - elbow.location.y)
        let wristPoint = CGPoint(x: wrist.location.x, y: 1 - wrist.location.y)

        // Calculate the elbow angle
        let angle = self.angleBetweenPoints(shoulder: shoulderPoint, elbow: elbowPoint, wrist: wristPoint)
        return angle
    }

    private func angleBetweenPoints(shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint) -> CGFloat {
        // Create vectors for upper arm (shoulder -> elbow) and forearm (elbow -> wrist)
        let upperArmVector = CGVector(dx: elbow.x - shoulder.x, dy: elbow.y - shoulder.y)
        let forearmVector = CGVector(dx: wrist.x - elbow.x, dy: wrist.y - elbow.y)

        // Calculate the dot product and magnitudes
        let dotProduct = (upperArmVector.dx * forearmVector.dx) + (upperArmVector.dy * forearmVector.dy)
        let magnitudeUpperArm = sqrt(upperArmVector.dx * upperArmVector.dx + upperArmVector.dy * upperArmVector.dy)
        let magnitudeForearm = sqrt(forearmVector.dx * forearmVector.dx + forearmVector.dy * forearmVector.dy)

        // Calculate the angle in radians and convert to degrees
        let cosineAngle = dotProduct / (magnitudeUpperArm * magnitudeForearm)
        let angleInRadians = acos(cosineAngle)
        let angleInDegrees = angleInRadians * (180.0 / .pi)

        return angleInDegrees // Return the elbow angle in degrees
    }
}
