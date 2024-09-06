//
//  Utilities.swift
//  tripletalear
//
//  Created by Wes Wang on 8/18/24.
//

import Foundation
import ARKit
import CoreML
import Vision
import UIKit
import AVFoundation
import Photos
import CoreGraphics
import CoreImage
import SceneKit

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

func pixelBufferToUIImage(pixelBuffer: CVPixelBuffer) -> UIImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    
    let rotation = CGAffineTransform(rotationAngle: -.pi / 2)
    let rotatedCIImage = ciImage.transformed(by: rotation)

    let context = CIContext(options: nil)
    guard let cgImage = context.createCGImage(rotatedCIImage, from: rotatedCIImage.extent) else { return nil }
    return UIImage(cgImage: cgImage)
}

func depthPixelBufferToUIImage(pixelBuffer: CVPixelBuffer) -> UIImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

    let context = CIContext(options: nil)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
    return UIImage(cgImage: cgImage)
}


func processObservations(for request: VNRequest, error: Error?) -> (identifierString: String, confidence: VNConfidence, boundingBox: CGRect?)? {
    guard let results = request.results else {
        print("Unable to process image.\n\(error?.localizedDescription ?? "Unknown error")")
        return nil
    }

    let threshold: Float = 0.0
    
    var identifierString = ""
    var confidence: VNConfidence = 0
    var boundingBox: CGRect? = nil

    if let detections = results as? [VNRecognizedObjectObservation] {
        // Handle object detections
        if let bestResult = detections.first(where: { result in result.confidence > threshold }),
           let label = bestResult.labels.first?.identifier.split(separator: ",").first {
            identifierString = String(label)
            confidence = bestResult.confidence
            boundingBox = bestResult.boundingBox
        }
    } else if let classifications = results as? [VNClassificationObservation] {
        // Handle classifications
        if let bestResult = classifications.first(where: { result in result.confidence > threshold }),
           let label = bestResult.identifier.split(separator: ",").first {
            identifierString = String(label)
            confidence = bestResult.confidence
        }
    } else {
        print("Unknown result type: \(type(of: results))")
        return nil
    }

    return (identifierString, confidence, boundingBox)
}

func convertCGImageToGrayscalePixelData(_ cgImage: CGImage) -> [UInt8]? {
    let width = cgImage.width
    let height = cgImage.height
    let bitsPerComponent = 8
    let bytesPerPixel = 1
    let bytesPerRow = width * bytesPerPixel

    var pixelData = [UInt8](repeating: 0, count: width * height)
    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard let context = CGContext(data: &pixelData,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: bitsPerComponent,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
        return nil
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixelData
}

func position(from anchor: ARAnchor) -> SIMD3<Float> {
    return SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
}

func distanceBetween(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
    let dx = point2.x - point1.x
    let dy = point2.y - point1.y
    return sqrt(dx * dx + dy * dy)
}

func scalePoint(point: simd_float3, center: simd_float3, verticalScaleFactor: Float, horizontalScaleFactor: Float) -> simd_float3 {
    let vector = point - center
    let scaledVector = simd_float3(x: vector.x * horizontalScaleFactor, y: vector.y * verticalScaleFactor, z: vector.z)
    return center + scaledVector
}

func getDepthMap(from currentFrame: ARFrame) -> UIImage? {
    // First, try to get sceneDepth from LiDAR-equipped devices
    if let sceneDepth = currentFrame.sceneDepth {
        return pixelBufferToUIImage(pixelBuffer: sceneDepth.depthMap)
    }
    
    // If sceneDepth is not available, check for smoothedSceneDepth (better quality for non-LiDAR devices)
    if let smoothedSceneDepth = currentFrame.smoothedSceneDepth {
        return pixelBufferToUIImage(pixelBuffer: smoothedSceneDepth.depthMap)
    }
    
    // Fallback to estimatedDepthData if smoothedSceneDepth is not available
    if let estimatedDepthData = currentFrame.estimatedDepthData {
        return pixelBufferToUIImage(pixelBuffer: estimatedDepthData)
    }
    
    // If no depth data is available, return nil
    print("Depth data not available on this device.")
    return nil
}

// Function to scale the fish length to the same plane as the face
func scaleLengthToFacePlane(fishLengthPx: CGFloat, fishDepth: CGFloat, faceDepth: CGFloat) -> CGFloat {
    // Scale the fish length using the depth ratio
    let scalingFactor = (1/faceDepth) / (1/fishDepth)
    let scaledFishLengthPx = fishLengthPx * scalingFactor
    return scaledFishLengthPx
}

// Function to get the depth value at specific coordinates (centerX, centerY) from a UIImage
func getDepthValue(atX centerX: CGFloat, atY centerY: CGFloat, depthMap: UIImage) -> CGFloat? {
    // Ensure the coordinates are within bounds of the image
    guard let cgImage = depthMap.cgImage else {
        print("Error: Unable to access CGImage from UIImage")
        return nil
    }
    
    let imageWidth = CGFloat(cgImage.width)
    let imageHeight = CGFloat(cgImage.height)
    
    // Ensure the coordinates are within the bounds of the image
    guard centerX >= 0 && centerX < imageWidth && centerY >= 0 && centerY < imageHeight else {
        print("Error: Coordinates are outside the image bounds")
        return nil
    }
    
    // Create a bitmap context to extract the pixel data
    guard let dataProvider = cgImage.dataProvider,
          let pixelData = dataProvider.data else {
        print("Error: Unable to get pixel data from CGImage")
        return nil
    }
    
    let data = CFDataGetBytePtr(pixelData)
    
    // Calculate the byte index for the specified coordinates
    let bytesPerPixel = 1  // Assuming it's an 8-bit grayscale image (1 byte per pixel)
    let byteIndex = Int(centerY) * cgImage.bytesPerRow + Int(centerX) * bytesPerPixel
    
    // Extract the grayscale pixel value (depth) at the specified coordinates
    let pixelValue = data?[byteIndex]
    
    // Convert the pixel value to a CGFloat
    if let pixelValue = pixelValue {
        return CGFloat(pixelValue) / 255.0  // Normalize to [0, 1]
    } else {
        print("Error: Failed to extract pixel value")
        return nil
    }
}

func resizeImageForModel(_ image: UIImage) -> UIImage? {
    let newSize = CGSize(width: 518, height: 392)

    // Resize the image to the new dimensions
    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return resizedImage
}

/// Resize depth map back to the original input image size
func resizeDepthMap(_ depthImage: UIImage, to originalSize: CGSize) -> UIImage? {
    UIGraphicsBeginImageContextWithOptions(originalSize, false, 1.0)
    depthImage.draw(in: CGRect(origin: .zero, size: originalSize))
    let resizedDepthImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return resizedDepthImage
}

func thresholdGrayscaleImage(pixelData: [UInt8], width: Int, height: Int, threshold: UInt8) -> [UInt8] {
    var binaryData = pixelData
    for i in 0..<pixelData.count {
        binaryData[i] = pixelData[i] > threshold ? 255 : 0
    }
    return binaryData
}

// Function to calculate the center of an array of CGPoint
func calculateCenter(of points: [CGPoint]) -> CGPoint? {
    guard !points.isEmpty else { return nil }  // Return nil if the array is empty
    
    var totalX: CGFloat = 0
    var totalY: CGFloat = 0
    
    // Sum all x and y values
    for point in points {
        totalX += point.x
        totalY += point.y
    }
    
    // Calculate the average x and y values
    let centerX = totalX / CGFloat(points.count)
    let centerY = totalY / CGFloat(points.count)
    
    return CGPoint(x: centerX, y: centerY)
}

// Function to scale the object as if it were in the same plane as the face
func scaleObjectToFacePlane(measuredLength: CGFloat, distanceToFace: CGFloat, objectDistanceFromTorso: CGFloat) -> CGFloat {
    // Distance to the face (assuming 2 feet or 0.6 meters)
    let distanceToCamera: CGFloat = distanceToFace
    
    // Calculate the distance ratio (how much closer the object is compared to the face)
    let objectDistanceToCamera = distanceToCamera - objectDistanceFromTorso
    let scalingRatio = objectDistanceToCamera / distanceToCamera
    
    // Scale the measured length of the object
    let scaledLength = measuredLength * scalingRatio
    
    return scaledLength
}

func estimateHandDistanceFromTorso(elbowAngle: CGFloat, upperArmLength: CGFloat, forearmLength: CGFloat) -> CGFloat {
    // Elbow angle is assumed to be in degrees, convert to radians for calculation
    let elbowAngleInRadians = elbowAngle * (.pi / 180.0)
    
    // When the elbow is fully extended (180 degrees), the hand is farthest from the torso
    // The forearm is assumed to be fully extended horizontally forward when the elbow is fully extended.
    // As the elbow bends, the forearm shortens its distance to the torso.

    // Calculate how far the hand is in front of the elbow along the x-axis based on elbow angle
    let forwardDistance = forearmLength * cos(elbowAngleInRadians)
    
    // In this model, we are estimating the distance from the torso to the hand,
    // which will be the length of the upper arm plus the forward component of the forearm.
    let totalForwardDistance = upperArmLength + forwardDistance
    
    return totalForwardDistance
}
