//
//  ArmPose3DDetector.swift
//  TripleTale
//
//  Created by Wes Wang on 9/6/24.
//

import UIKit
import Vision
import simd

class ArmPose3DDetector {
    
    func detectArmBendAngles(in image: UIImage, completion: @escaping ([String: VNPoint], [String: simd_float4], Bool) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([:], [:], false)
            return
        }

        // Create a VNImageRequestHandler with the RGB image
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let bodyPose3DRequest = VNDetectHumanBodyPose3DRequest()

        do {
            try requestHandler.perform([bodyPose3DRequest])
            guard let results = bodyPose3DRequest.results, let observation = results.first else {
                // No results detected
                completion([:], [:], false)
                return
            }
            
           let test = try? observation.pointInImage(.leftElbow)
            
            // Extract the shoulder, elbow, and wrist 3D key points for both left and right arms using localPosition
            if let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
               let leftElbow = try? observation.recognizedPoint(.leftElbow),
               let leftWrist = try? observation.recognizedPoint(.leftWrist),
               let rightShoulder = try? observation.recognizedPoint(.rightShoulder),
               let rightElbow = try? observation.recognizedPoint(.rightElbow),
               let rightWrist = try? observation.recognizedPoint(.rightWrist),
               let head = try? observation.recognizedPoint(.centerHead) {
                
                // Extract simd_float3 from the simd_float4x4 localPosition matrix
                let leftShoulderPoint = self.extractPosition(from: leftShoulder.position)
                let leftElbowPoint = self.extractPosition(from: leftElbow.position)
                let leftWristPoint = self.extractPosition(from: leftWrist.position)
                
                let rightShoulderPoint = self.extractPosition(from: rightShoulder.position)
                let rightElbowPoint = self.extractPosition(from: rightElbow.position)
                let rightWristPoint = self.extractPosition(from: rightWrist.position)
                
                // Calculate the elbow angles using 3D vectors
                let leftElbowAngle = self.calculateArmBendAngle3D(shoulder: leftShoulderPoint, elbow: leftElbowPoint, wrist: leftWristPoint)
                let rightElbowAngle = self.calculateArmBendAngle3D(shoulder: rightShoulderPoint, elbow: rightElbowPoint, wrist: rightWristPoint)
                
                let headRelPos = try? observation.cameraRelativePosition(.centerHead)
                let rightWristRelPos = try? observation.cameraRelativePosition(.rightWrist)
                let leftWristRelPos = try? observation.cameraRelativePosition(.leftWrist)
                let rightElbowRelPos = try? observation.cameraRelativePosition(.rightElbow)
                let leftElbowRelPos = try? observation.cameraRelativePosition(.leftElbow)
                
                print("head 4d: \(head)")
                print("head 4d local pos: \(head.localPosition)")
                print("head 4d pos: \(head.position)")

                print("head relative distance: \(cameraRelativePositionToDistance(headRelPos!)) m")
                print("right wrist relative distance: \(cameraRelativePositionToDistance(rightWristRelPos!)) m")
                print("left wrist relative distance: \(cameraRelativePositionToDistance(leftWristRelPos!)) m")
                print("right elbow relative distance: \(cameraRelativePositionToDistance(rightElbowRelPos!)) m")
                print("left elbow relative distance: \(cameraRelativePositionToDistance(leftElbowRelPos!)) m")

                completion(leftShoulderPoint, leftElbowPoint, leftWristPoint, rightShoulderPoint, rightElbowPoint, rightWristPoint, ["leftElbowAngle": leftElbowAngle, "rightElbowAngle": rightElbowAngle], true)
            } else {
                // Points were not detected
                completion([:], [:], false)
            }
            
        } catch {
            print("Error performing body pose 3D request: \(error)")
            completion([:], [:], false)
        }
    }

    // Helper function to extract simd_float3 from simd_float4x4
    private func extractPosition(from matrix: simd_float4x4) -> simd_float3 {
        return simd_float3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }


    /// Calculates the pitch, yaw, and roll between the shoulder, elbow, and wrist joints.
    /// - Parameters:
    ///   - shoulder: The position of the shoulder in 3D space.
    ///   - elbow: The position of the elbow in 3D space.
    ///   - wrist: The position of the wrist in 3D space.
    /// - Returns: A simd_float3 containing the pitch, yaw, and roll.
    func calculateArmBendAngle3D(shoulder: simd_float3, elbow: simd_float3, wrist: simd_float3) -> simd_float3 {
        
        // Vector from shoulder to elbow (translation vector)
        let translationChild = elbow - shoulder

        // Calculate pitch (rotation around x-axis)
        let pitch: Float = Float.pi / 2
        
        // Calculate yaw (rotation around y-axis)
        let yaw: Float = acos(translationChild.z / simd_length(translationChild))
        
        // Calculate roll (rotation around z-axis)
        let roll: Float = atan2(translationChild.y, translationChild.x)
        
        // Return the angle vector
        return simd_float3(pitch, yaw, roll)
    }
    
    func cameraRelativePositionToDistance(_ matrix: simd_float4x4) -> Float {
        // Extract the translation component (the 4th column of the 4x4 matrix)
        let translation = simd_make_float3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        
        // Calculate the Euclidean distance
        return simd_length(translation)
    }
}
