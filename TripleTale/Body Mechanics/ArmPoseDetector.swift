//
//  ArmPoseDetector.swift
//  TripleTale
//
//  Created by Wes Wang on 9/6/24.
//

import UIKit
import Vision

class ArmPoseDetector {
    
    func detectArmBendAngles(in image: UIImage, completion: @escaping (CGPoint?, CGPoint?, CGPoint?, CGPoint?, CGPoint?, CGPoint?, [String: CGFloat]?, Bool) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil, nil, nil, nil, nil, nil, nil, false)
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
        
        do {
            try requestHandler.perform([bodyPoseRequest])
            guard let results = bodyPoseRequest.results, let observation = results.first else {
                // No results detected
                completion(nil, nil, nil, nil, nil, nil, nil, false)
                return
            }
            
            // Extract the shoulder, elbow, and wrist key points for both left and right arms
            let leftShoulder = try? observation.recognizedPoint(.leftShoulder)
            let leftElbow = try? observation.recognizedPoint(.leftElbow)
            let leftWrist = try? observation.recognizedPoint(.leftWrist)
            
            let rightShoulder = try? observation.recognizedPoint(.rightShoulder)
            let rightElbow = try? observation.recognizedPoint(.rightElbow)
            let rightWrist = try? observation.recognizedPoint(.rightWrist)
            
            // Boolean to check if at least one point was detected with sufficient confidence
            var detectedSomething = false

            // Check if the recognized points have sufficient confidence (threshold 0.5)
            if let ls = leftShoulder, let le = leftElbow, let lw = leftWrist, ls.confidence > 0.5, le.confidence > 0.5, lw.confidence > 0.5,
               let rs = rightShoulder, let re = rightElbow, let rw = rightWrist, rs.confidence > 0.5, re.confidence > 0.5, rw.confidence > 0.5 {
                
                // Convert normalized points to actual coordinates in the image size
                let leftShoulderPoint = CGPoint(x: ls.location.x * image.size.width, y: (1 - ls.location.y) * image.size.height)
                let leftElbowPoint = CGPoint(x: le.location.x * image.size.width, y: (1 - le.location.y) * image.size.height)
                let leftWristPoint = CGPoint(x: lw.location.x * image.size.width, y: (1 - lw.location.y) * image.size.height)
                
                let rightShoulderPoint = CGPoint(x: rs.location.x * image.size.width, y: (1 - rs.location.y) * image.size.height)
                let rightElbowPoint = CGPoint(x: re.location.x * image.size.width, y: (1 - re.location.y) * image.size.height)
                let rightWristPoint = CGPoint(x: rw.location.x * image.size.width, y: (1 - rw.location.y) * image.size.height)

                detectedSomething = true // At least one valid point was detected
                
                // Calculate the elbow angles
                let leftElbowAngle = self.calculateArmBendAngle(from: observation, side: "left")
                let rightElbowAngle = self.calculateArmBendAngle(from: observation, side: "right")
                
                // Complete with detected points and flag that detection was successful
                completion(leftShoulderPoint, leftElbowPoint, leftWristPoint, rightShoulderPoint, rightElbowPoint, rightWristPoint, ["leftElbowAngle": leftElbowAngle, "rightElbowAngle": rightElbowAngle], detectedSomething)
            } else {
                // Points were not detected or had low confidence
                completion(nil, nil, nil, nil, nil, nil, nil, detectedSomething)
            }
            
        } catch {
            print("Error performing body pose request: \(error)")
            completion(nil, nil, nil, nil, nil, nil, nil, false)
        }
    }

    private func calculateArmBendAngle(from observation: VNHumanBodyPoseObservation, side: String) -> CGFloat {
        let shoulderPointName = side == "left" ? VNHumanBodyPoseObservation.JointName.leftShoulder : VNHumanBodyPoseObservation.JointName.rightShoulder
        let elbowPointName = side == "left" ? VNHumanBodyPoseObservation.JointName.leftElbow : VNHumanBodyPoseObservation.JointName.rightElbow
        let wristPointName = side == "left" ? VNHumanBodyPoseObservation.JointName.leftWrist : VNHumanBodyPoseObservation.JointName.rightWrist
        
        guard let shoulder = try? observation.recognizedPoint(shoulderPointName),
              let elbow = try? observation.recognizedPoint(elbowPointName),
              let wrist = try? observation.recognizedPoint(wristPointName),
              shoulder.confidence > 0.5, elbow.confidence > 0.5, wrist.confidence > 0.5 else {
            return 0.0
        }
        
        // Convert normalized coordinates to CGPoint
        let shoulderPoint = CGPoint(x: shoulder.location.x, y: 1 - shoulder.location.y)
        let elbowPoint = CGPoint(x: elbow.location.x, y: 1 - elbow.location.y)
        let wristPoint = CGPoint(x: wrist.location.x, y: 1 - wrist.location.y)
        
        // Calculate the angle between shoulder -> elbow and elbow -> wrist
        return calculateAngle(shoulder: shoulderPoint, elbow: elbowPoint, wrist: wristPoint)
    }

    private func calculateAngle(shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint) -> CGFloat {
        // Create vectors for upper arm (shoulder -> elbow) and forearm (elbow -> wrist)
        let upperArmVector = CGVector(dx: elbow.x - shoulder.x, dy: elbow.y - shoulder.y)
        let forearmVector = CGVector(dx: wrist.x - elbow.x, dy: wrist.y - elbow.y)

        // Calculate the dot product and magnitudes (lengths) of the vectors
        let dotProduct = (upperArmVector.dx * forearmVector.dx) + (upperArmVector.dy * forearmVector.dy)
        let upperArmMagnitude = sqrt(upperArmVector.dx * upperArmVector.dx + upperArmVector.dy * upperArmVector.dy)
        let forearmMagnitude = sqrt(forearmVector.dx * forearmVector.dx + forearmVector.dy * forearmVector.dy)

        // Calculate the angle between the vectors in radians and convert it to degrees
        let cosineAngle = dotProduct / (upperArmMagnitude * forearmMagnitude)
        let angleInRadians = acos(cosineAngle)
        let angleInDegrees = angleInRadians * (180.0 / .pi)

        return angleInDegrees
    }
}
