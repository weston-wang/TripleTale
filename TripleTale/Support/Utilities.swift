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
import StoreKit

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

func resizeImageForModel(_ image: UIImage, width: Int = 320, height: Int = 320) -> UIImage? {
    let newSize = CGSize(width: width, height: height)

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
func scaleObjectToFacePlane(measuredLength: CGFloat, faceDistanceToCamera: CGFloat, objectDistanceToCamera: CGFloat) -> CGFloat {
    
    // Calculate the distance ratio (how much closer the object is compared to the face)
    let scalingRatio = objectDistanceToCamera / faceDistanceToCamera
    
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

/// Converts a UIImage into a CVPixelBuffer.
func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
    guard let cgImage = image.cgImage else { return nil }

    let frameSize = CGSize(width: cgImage.width, height: cgImage.height)
    var pixelBuffer: CVPixelBuffer?

    let options: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]

    let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                     Int(frameSize.width),
                                     Int(frameSize.height),
                                     kCVPixelFormatType_32BGRA, // Choose format appropriate for your depth data
                                     options as CFDictionary,
                                     &pixelBuffer)

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
    let pixelData = CVPixelBufferGetBaseAddress(buffer)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: pixelData,
                            width: Int(frameSize.width),
                            height: Int(frameSize.height),
                            bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

    context?.draw(cgImage, in: CGRect(origin: .zero, size: frameSize))
    CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
    
    return buffer
}

func createDepthDataFromDictionary(from depthImage: UIImage) -> AVDepthData? {
    // Convert the UIImage to a CGImage
    guard let cgImage = depthImage.cgImage else {
        print("Unable to convert UIImage to CGImage")
        return nil
    }

    let width = cgImage.width
    let height = cgImage.height

    // Create a pixel buffer to hold the depth data
    let depthPixelBufferOptions: [CFString: Any] = [
        kCVPixelBufferWidthKey: width,
        kCVPixelBufferHeightKey: height,
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_DisparityFloat32 // or kCVPixelFormatType_DepthFloat32
    ]

    var depthPixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_DisparityFloat32, depthPixelBufferOptions as CFDictionary, &depthPixelBuffer)

    guard let pixelBuffer = depthPixelBuffer else {
        print("Unable to create CVPixelBuffer")
        return nil
    }

    // Lock the pixel buffer to modify it
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    let depthPointer = CVPixelBufferGetBaseAddress(pixelBuffer)

    // Create a CGContext and draw the image into the pixel buffer
    let context = CGContext(data: depthPointer,
                            width: width,
                            height: height,
                            bitsPerComponent: 32, // Float32 format for depth
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                            space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)

    context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

    // Now we need to create the auxiliary dictionary for AVDepthData
    let auxDataInfo: [AnyHashable: Any] = [
        kCGImageAuxiliaryDataInfoData: pixelBuffer, // The pixel buffer
    ]

    // Create AVDepthData from the auxiliary dictionary
    do {
        let depthData = try AVDepthData(fromDictionaryRepresentation: auxDataInfo)
        return depthData
    } catch {
        print("Error creating AVDepthData from dictionary: \(error)")
        return nil
    }
}

func validateWristsLocations(foundPoints: [String : VNPoint], wristDistances: [String : Float], depthImage: UIImage) -> Bool {
    
    // get depth at head
    let headLoc = foundPoints["head"];

    // find closest wrist
    
    // get depths at wrists
    let leftWristLoc = foundPoints["leftWrist"];
    let rightWristLoc = foundPoints["rightWrist"];
    
    let headDepth = getDepthValue(atX: headLoc!.x, atY: headLoc!.y, depthMap: depthImage)
    let leftWristDepth = getDepthValue(atX: leftWristLoc!.x, atY: leftWristLoc!.y, depthMap: depthImage)
    let rightWristDepth = getDepthValue(atX: rightWristLoc!.x, atY: rightWristLoc!.y, depthMap: depthImage)

    

    return false
}

/// Converts a normalized VNPoint.location to a CGPoint in the image coordinate system.
/// - Parameters:
///   - point: The VNPoint to convert (assumed to be normalized between 0 and 1, with a lower-left origin).
///   - imageSize: The size of the image for conversion.
/// - Returns: The CGPoint in the image's coordinate space.
func convertNormalizedPointToCGPoint(_ point: CGPoint, imageSize: CGSize) -> CGPoint {
    // Convert normalized coordinates with a lower-left origin to UIKit's top-left origin
    let x = point.x * imageSize.width
    let y = (1.0 - point.y) * imageSize.height // Flip y-axis for UIKit
    return CGPoint(x: x, y: y)
}

// Convert grayscale pixel data back to a UIImage
func createUIImageFromGrayscalePixelData(pixelData: [UInt8], width: Int, height: Int) -> UIImage? {
    let bytesPerPixel = 1
    let bytesPerRow = bytesPerPixel * width
    let colorSpace = CGColorSpaceCreateDeviceGray()
    
    guard let context = CGContext(data: UnsafeMutableRawPointer(mutating: pixelData),
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue),
          let cgImage = context.makeImage() else {
        return nil
    }
    
    return UIImage(cgImage: cgImage)
}

func applySmallDither(to vertices: [CGPoint]) -> [CGPoint] {
    let ditherAmount: CGFloat = 0.005 // Small dither in normalized coordinates
    return vertices.map { point in
        let dx = (CGFloat.random(in: -ditherAmount...ditherAmount))
        let dy = (CGFloat.random(in: -ditherAmount...ditherAmount))
        return CGPoint(x: min(1.0, max(0.0, point.x + dx)),
                       y: min(1.0, max(0.0, point.y + dy))) // Keep within [0,1] range
    }
}

func imageToMultiArray(_ image: UIImage, targetSize: CGSize = CGSize(width: 320, height: 320)) -> MLMultiArray? {
    guard let cgImage = image.cgImage else {
        print("Failed to get CGImage")
        return nil
    }

    return cgImageToMultiArray(cgImage, targetSize: targetSize)
}

func cgImageToMultiArray(_ cgImage: CGImage, targetSize: CGSize = CGSize(width: 320, height: 320)) -> MLMultiArray? {
    let width = Int(targetSize.width)
    let height = Int(targetSize.height)

    // Create RGB context
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    )

    guard let ctx = context else {
        print("Failed to create CGContext")
        return nil
    }

    // Draw the resized image into the context
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let pixelBuffer = ctx.data else {
        print("Failed to get pixel data")
        return nil
    }

    // Create MLMultiArray (1, 320, 320, 3)
    guard let array = try? MLMultiArray(shape: [1, NSNumber(value: height), NSNumber(value: width), 3], dataType: .float32) else {
        print("Failed to create MLMultiArray")
        return nil
    }

    let buffer = pixelBuffer.bindMemory(to: UInt8.self, capacity: width * height * 4)

    for y in 0..<height {
        for x in 0..<width {
            let pixelIndex = (y * width + x) * 4
            let r = Float(buffer[pixelIndex])
            let g = Float(buffer[pixelIndex + 1])
            let b = Float(buffer[pixelIndex + 2])

            let offset = (y * width + x) * 3
            array[[0, y as NSNumber, x as NSNumber, 0]] = NSNumber(value: r)
            array[[0, y as NSNumber, x as NSNumber, 1]] = NSNumber(value: g)
            array[[0, y as NSNumber, x as NSNumber, 2]] = NSNumber(value: b)
        }
    }

    return array
}

func multiArrayToUIImage(_ multiArray: MLMultiArray, width: Int = 320, height: Int = 320) -> UIImage? {
    guard multiArray.dataType == .float32 else {
        print("Expected MLMultiArray with Float32 type")
        return nil
    }

    let count = width * height
    let floatPointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: count)
    let buffer = UnsafeBufferPointer(start: floatPointer, count: count)

    // Optional: Normalize or clamp pixel range as needed
    let pixelData = buffer.map { UInt8(min(max($0 * 255.0, 0), 255)) }

    guard let cfData = CFDataCreate(nil, pixelData, count),
          let provider = CGDataProvider(data: cfData) else {
        print("Failed to create CGDataProvider")
        return nil
    }

    guard let cgImage = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        print("Failed to create CGImage")
        return nil
    }

    return UIImage(cgImage: cgImage)
}

func softmaxClassMaskToBinaryImage(_ multiArray: MLMultiArray, threshold: Float = 0.5) -> UIImage? {
    var shape = multiArray.shape.map { $0.intValue }
    if shape.count == 4 && shape[0] == 1 {
        shape.removeFirst() // remove batch dimension → shape becomes [2, 320, 320]
    }
    guard shape.count == 3 else {
        print("Expected shape [num_classes, height, width], got \(shape)")
        return nil
    }

    let numClasses = shape[0]
    let height = shape[1]
    let width = shape[2]

    let count = height * width
    let floatPointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: shape[0] * shape[1] * shape[2])
    let buffer = UnsafeBufferPointer(start: floatPointer, count: numClasses * count)

    var scores = [Float](repeating: 0, count: count)
    var classes = [UInt8](repeating: 0, count: count)

    // Normalize (optional, mirrors your Python code)
    let minVal = buffer.min() ?? 0
    let maxVal = buffer.max() ?? 1
    let range = maxVal - minVal

    for i in 0..<count {
        var maxScore: Float = -Float.infinity
        var bestClass: UInt8 = 0

        for c in 0..<numClasses {
            let index = c * count + i
            let raw = buffer[index]
            let normalized = range > 0 ? (raw - minVal) / range : 0

            if normalized > maxScore {
                maxScore = normalized
                bestClass = UInt8(c)
            }
        }

        scores[i] = maxScore
        classes[i] = bestClass
    }

    // Threshold to binary mask
    let pixelData = (0..<count).map { scores[$0] > threshold && classes[$0] == 1 ? UInt8(255) : UInt8(0) }

    guard let cfData = CFDataCreate(nil, pixelData, count),
          let provider = CGDataProvider(data: cfData) else {
        return nil
    }

    guard let cgImage = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        return nil
    }

    return UIImage(cgImage: cgImage)
}

func multiArrayToGrayscaleImage(_ multiArray: MLMultiArray) -> UIImage? {
    guard multiArray.dataType == .float16 || multiArray.dataType == .float32 else {
        print("❌ Unsupported MultiArray data type")
        return nil
    }

    let shape = multiArray.shape.map { $0.intValue }
    guard shape.count >= 3 else {
        print("❌ Unexpected shape for mask array")
        return nil
    }

    let height = shape[shape.count - 2]
    let width = shape[shape.count - 1]
    let totalCount = width * height

    let floatData: [Float]
    if multiArray.dataType == .float16 {
        floatData = (0..<totalCount).map {
            Float(truncating: multiArray[$0] as NSNumber)
        }
    } else {
        floatData = (0..<totalCount).map {
            multiArray[$0].floatValue
        }
    }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: totalCount)
    for i in 0..<totalCount {
        buffer[i] = UInt8(clamping: Int(floatData[i] * 255))
    }

    let grayColorSpace = CGColorSpaceCreateDeviceGray()
    let context = CGContext(data: buffer,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: width,
                            space: grayColorSpace,
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)

    guard let cgImage = context?.makeImage() else {
        buffer.deallocate()
        return nil
    }

    let uiImage = fillHolesInMask(cgImage)
//    let uiImage = UIImage(cgImage: cgImage)
    buffer.deallocate()
    return uiImage
}

/// Projects a point along a ray direction from origin to a target Z-depth
func backProjectToZPlane(
    origin: simd_float3,
    direction: simd_float3,
    targetZ: Float
) -> simd_float3 {
    let t = (targetZ - origin.z) / direction.z
    return origin + direction * t
}

/// Back-projects all but the closest anchor to the Z-plane of the closest one
/// - Parameters:
///   - anchors: array of 4 anchors placed from raycasts
///   - raycastOrigins: same order as anchors; origin of each ray
///   - raycastDirections: same order; original ray direction used to place each anchor
/// - Returns: a dictionary mapping each original anchor to its back-projected position
func backProjectAnchorsToSameDepth(
    anchors: [ARAnchor],
    queries: [ARRaycastQuery]
) -> [ARAnchor] {
    guard anchors.count == queries.count else {
        print("❌ Mismatch: anchors and queries count must match.")
        return []
    }

    // Step 1: Calculate distance (t) along each ray (for anchors at indices 0 and 2 only)
    var tValues: [Float] = []
    for i in [0, 2] {
        let anchorPos = anchors[i].transform.columns.3.xyz
        let rayOrigin = queries[i].origin
        let rayDir = simd_normalize(queries[i].direction)
        let displacement = anchorPos - rayOrigin
        let t = simd_dot(displacement, rayDir)
        tValues.append(t)
    }

    // Step 2: Get the minimum t (closest to camera)
    guard let tMin = tValues.min() else {
        print("❌ Failed to compute minimum t")
        return []
    }

    // Step 3: Backproject all rays to that t and create new anchors
    var newAnchors: [ARAnchor] = []

    for i in 0..<anchors.count {
        let rayOrigin = queries[i].origin
        let rayDir = simd_normalize(queries[i].direction)
        let newPos = rayOrigin + tMin * rayDir

        // Construct transform with newPos
        var newTransform = matrix_identity_float4x4
        newTransform.columns.3 = simd_float4(newPos.x, newPos.y, newPos.z, 1.0)

        let newAnchor = ARAnchor(transform: newTransform)
        newAnchors.append(newAnchor)
    }

    return newAnchors
}

func uiImageOrientation(from radians: CGFloat) -> UIImage.Orientation {
    switch radians {
    case CGFloat.pi / 2:
        return .left
    case -CGFloat.pi / 2:
        return .right
    case CGFloat.pi, -CGFloat.pi:
        return .down
    default:
        return .up
    }
}

func popUpImageOrientation(from radians: CGFloat) -> UIImage.Orientation {
    switch radians {
    case CGFloat.pi / 2:
        return .right
    case -CGFloat.pi / 2:
        return .left
    case CGFloat.pi, -CGFloat.pi:
        return .down
    default:
        return .up
    }
}

func printActiveEntitlements() {
    Task {
        print("📦 Checking active entitlements...")
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                print("""
                ✅ Active Subscription:
                • Product ID: \(transaction.productID)
                • Purchase Date: \(transaction.purchaseDate)
                • Expiration Date: \(transaction.expirationDate?.description ?? "None")
                • Is Upgraded: \(transaction.isUpgraded)
                """)
            case .unverified(let transaction, let error):
                print("❌ Unverified transaction: \(transaction.productID), error: \(error)")
            }
        }
    }
}

func areAnchorHeightsWithinTolerance(_ anchors: [ARAnchor], tolerance: Float = 0.1) -> Bool {
    guard anchors.count > 1 else { return true }
    
    // Extract all Y positions
    let yValues = anchors.map { $0.transform.columns.3.y }
    
    // Get min and max
    guard let minY = yValues.min(), let maxY = yValues.max() else {
        return true
    }
    
    return (maxY - minY) <= tolerance
}
