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
    let scalingFactor = faceDepth / fishDepth
    let scaledFishLengthPx = fishLengthPx * scalingFactor
    return scaledFishLengthPx
}

func getDepthAtCenter(of rect: CGRect, depthMap: UIImage) -> CGFloat? {
    // Convert UIImage to CIImage
    guard let ciImage = CIImage(image: depthMap) else {
        print("Error: Unable to create CIImage from UIImage")
        return nil
    }
    
    // Create a Core Image context
    let context = CIContext()
    
    // Get the extent (dimensions) of the CIImage
    let depthMapExtent = ciImage.extent
    
    // Get the center point of the CGRect
    let centerX = rect.midX
    let centerY = rect.midY
    
    // Ensure the coordinates are within bounds of the image
    guard depthMapExtent.contains(CGPoint(x: centerX, y: centerY)) else {
        print("Error: Center point is outside depth map bounds")
        return nil
    }
    
    // Calculate the scaled coordinates for the depth map
    let depthX = centerX / rect.width * depthMapExtent.width
    let depthY = centerY / rect.height * depthMapExtent.height
    
    // Create a bitmap representation of the depth map in grayscale
    var pixelValue: [UInt8] = [0] // For grayscale, only 1 channel (UInt8)
    context.render(ciImage, toBitmap: &pixelValue, rowBytes: 1, bounds: CGRect(x: Int(depthX), y: Int(depthY), width: 1, height: 1), format: .R8, colorSpace: nil)
    
    // Convert the pixel value to a CGFloat
    let depthValue = CGFloat(pixelValue[0])
    
    return depthValue
}

func resizeImageForModel(_ image: UIImage) -> UIImage? {
    let originalSize = image.size
    let width = originalSize.width
    let height = originalSize.height
    
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
