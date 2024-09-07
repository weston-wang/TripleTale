//
//  ArmPose3DDetector.swift
//  TripleTale
//
//  Created by Wes Wang on 9/6/24.
//

import UIKit
import Vision
import simd

struct ArmPose3DDetector {
    
    func detectArmBendAngles(in image: UIImage, completion: @escaping ([String: VNPoint], [String: Float], Bool) -> Void) {
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
                        
            // Extract the shoulder, elbow, and wrist 3D key points for both left and right arms using localPosition
            if let head = try? observation.recognizedPoint(.centerHead) {
                
                let leftShoulderPoint = try! observation.pointInImage(.leftShoulder)
                let leftElbowPoint = try! observation.pointInImage(.leftElbow)
                let leftWristPoint = try! observation.pointInImage(.leftWrist)
                
                let rightShoulderPoint = try! observation.pointInImage(.rightShoulder)
                let rightElbowPoint = try! observation.pointInImage(.rightElbow)
                let rightWristPoint = try! observation.pointInImage(.rightWrist)
                
                let headPoint = try! observation.pointInImage(.centerHead)
                let rootPoint = try! observation.pointInImage(.root)

                let headRelPos = try? observation.cameraRelativePosition(.centerHead)
                let rightWristRelPos = try? observation.cameraRelativePosition(.rightWrist)
                let rightElbowRelPos = try? observation.cameraRelativePosition(.rightElbow)
                let rightShoulderRelPos = try? observation.cameraRelativePosition(.rightShoulder)

                let leftWristRelPos = try? observation.cameraRelativePosition(.leftWrist)
                let leftElbowRelPos = try? observation.cameraRelativePosition(.leftElbow)
                let leftShoulderRelPos = try? observation.cameraRelativePosition(.leftShoulder)

                // Return both 2D points in image and 4D positions in space
                let pointsInImage: [String: VNPoint] = [
//                    "leftShoulder": leftShoulderPoint,
//                    "leftElbow": leftElbowPoint,
                    "leftWrist": leftWristPoint,
//                    "rightShoulder": rightShoulderPoint,
//                    "rightElbow": rightElbowPoint,
                    "rightWrist": rightWristPoint,
                    "head": headPoint,
                    "root": rootPoint
                ]

                let distancesInM: [String: Float] = [
//                    "leftShoulder": cameraRelativePositionToDistance(leftShoulderRelPos!),
//                    "leftElbow": cameraRelativePositionToDistance(leftElbowRelPos!),
                    "leftWrist": cameraRelativePositionToDistance(leftElbowRelPos!),
//                    "rightShoulder": cameraRelativePositionToDistance(rightShoulderRelPos!),
//                    "rightElbow": cameraRelativePositionToDistance(rightElbowRelPos!),
                    "rightWrist": cameraRelativePositionToDistance(rightWristRelPos!),
                    "head": cameraRelativePositionToDistance(headRelPos!)
                ]

                completion(pointsInImage, distancesInM, true)
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
