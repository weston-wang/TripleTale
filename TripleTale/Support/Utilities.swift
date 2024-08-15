/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Utility functions and type extensions used throughout the projects.
*/

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

func saveDebugImage(_ inputPixelBuffer: CVPixelBuffer, _ inputBoundingBox: CGRect) {
    let ciImage = CIImage(cvPixelBuffer: inputPixelBuffer)
    let rotation = CGAffineTransform(rotationAngle: -.pi / 2)
    let rotatedCIImage = ciImage.transformed(by: rotation)

    let context = CIContext()
    guard let cgImage = context.createCGImage(rotatedCIImage, from: rotatedCIImage.extent) else { return }
    let image = UIImage(cgImage: cgImage)

    let imageWithBox = drawRectanglesOnImage(image: image, boundingBoxes: [inputBoundingBox])
    saveImageToGallery(imageWithBox)
}

func pixelBufferToUIImage(pixelBuffer: CVPixelBuffer) -> UIImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    
    let rotation = CGAffineTransform(rotationAngle: -.pi / 2)
    let rotatedCIImage = ciImage.transformed(by: rotation)

    let context = CIContext(options: nil)
    guard let cgImage = context.createCGImage(rotatedCIImage, from: rotatedCIImage.extent) else { return nil }
    return UIImage(cgImage: cgImage)
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


// Function to scale a point around the center with different scale factors for each direction
func scalePoint(point: simd_float3, center: simd_float3, verticalScaleFactor: Float, horizontalScaleFactor: Float) -> simd_float3 {
    let vector = point - center
    let scaledVector = simd_float3(x: vector.x * horizontalScaleFactor, y: vector.y * verticalScaleFactor, z: vector.z)
    return center + scaledVector
}

// Helper function to get the position from an anchor
func position(from anchor: ARAnchor) -> SIMD3<Float> {
    return SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
}

func centerROI(for image: CIImage, portion: CGFloat) -> CGRect {
    // Calculate the dimensions of the ROI
    let roiWidth = portion
    let roiHeight = portion
    
    // Calculate the position to center the ROI
    let roiX = (1.0 - roiWidth) / 2.0
    let roiY = (1.0 - roiHeight) / 2.0
    
    // Create and return the CGRect for the ROI
    return CGRect(x: roiX, y: roiY, width: roiWidth, height: roiHeight)
}

func reversePerspectiveEffectOnBoundingBox(boundingBox: CGRect, distanceToPhone: Float, totalDistance: Float) -> CGRect {
    // Calculate the inverse scaling factor for dimensions
    let scalingFactor = distanceToPhone / totalDistance

    // Reverse the bounding box dimensions
    let correctedWidth = boundingBox.width * CGFloat(scalingFactor)
    let correctedHeight = boundingBox.height * CGFloat(scalingFactor)
    
    // scaling factor is less than 1, so this
    let shiftX = (correctedWidth - boundingBox.width) / 2
    let shiftY = (correctedHeight - boundingBox.height) / 2

    // Reverse the bounding box position
    let correctedX = boundingBox.origin.x - shiftX
    let correctedY = boundingBox.origin.y - shiftY
    
    // Return the original bounding box
    return CGRect(x: correctedX, y: correctedY, width: correctedWidth, height: correctedHeight)
}

func reversePerspectiveEffectOnPoints(points: [CGPoint], distanceToPhone: Float, totalDistance: Float) -> [CGPoint] {
    // Calculate the inverse scaling factor for dimensions
    let scalingFactor = distanceToPhone / totalDistance

    // Apply the correction to each point
    let correctedPoints = points.map { point -> CGPoint in
        // Scale the x and y coordinates
        let correctedX = point.x * CGFloat(scalingFactor)
        let correctedY = point.y * CGFloat(scalingFactor)

        // Return the corrected point
        return CGPoint(x: correctedX, y: correctedY)
    }

    return correctedPoints
}

func generateEvenlySpacedPoints(from start: CGPoint, to end: CGPoint, count: Int) -> [CGPoint] {
    guard count > 1 else {
        return [start, end]
    }

    let deltaX = (end.x - start.x) / CGFloat(count - 1)
    let deltaY = (end.y - start.y) / CGFloat(count - 1)
    
    var points = [CGPoint]()
    for i in 0..<count {
        let x = start.x + deltaX * CGFloat(i)
        let y = start.y + deltaY * CGFloat(i)
        points.append(CGPoint(x: x, y: y))
    }
    
    return points
}

func extract2DCoordinates(from anchors: [ARAnchor]) -> [CGPoint] {
    return anchors.map { CGPoint(x: CGFloat($0.transform.columns.3.x), y: CGFloat($0.transform.columns.3.z)) }
}

func transpose(_ matrix: [[Double]]) -> [[Double]] {
    guard let firstRow = matrix.first else { return [] }
    var transposed = [[Double]](repeating: [Double](repeating: 0.0, count: matrix.count), count: firstRow.count)
    for (i, row) in matrix.enumerated() {
        for (j, value) in row.enumerated() {
            transposed[j][i] = value
        }
    }
    return transposed
}

func multiply(_ matrixA: [[Double]], _ matrixB: [[Double]]) -> [[Double]] {
    let rowsA = matrixA.count
    let colsA = matrixA[0].count
    let rowsB = matrixB.count
    let colsB = matrixB[0].count

    guard colsA == rowsB else { return [] }

    var result = [[Double]](repeating: [Double](repeating: 0.0, count: colsB), count: rowsA)
    for i in 0..<rowsA {
        for j in 0..<colsB {
            for k in 0..<colsA {
                result[i][j] += matrixA[i][k] * matrixB[k][j]
            }
        }
    }
    return result
}

func inverse(_ matrix: [[Double]]) -> [[Double]]? {
    let n = matrix.count
    var a = matrix
    var b = [[Double]](repeating: [Double](repeating: 0.0, count: n), count: n)

    for i in 0..<n {
        b[i][i] = 1.0
    }

    for i in 0..<n {
        let pivot = a[i][i]
        guard pivot != 0 else { return nil }
        for j in 0..<n {
            a[i][j] /= pivot
            b[i][j] /= pivot
        }
        for k in 0..<n {
            if k != i {
                let factor = a[k][i]
                for j in 0..<n {
                    a[k][j] -= factor * a[i][j]
                    b[k][j] -= factor * b[i][j]
                }
            }
        }
    }
    return b
}

func getTopDownHomographyMatrix(cameraTransform: simd_float4x4) -> matrix_float4x4 {
    // Extract rotation (the upper-left 3x3 part of the 4x4 matrix)
    let rotationMatrix = matrix_float3x3(columns: (
        simd_make_float3(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z),
        simd_make_float3(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z),
        simd_make_float3(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
    ))
    
    print("rot mat: \(rotationMatrix)")
    
    // Invert the rotation matrix to reverse the current rotation
    let inverseRotationMatrix = rotationMatrix.inverse
    
    // Convert to a 4x4 matrix for homogeneous coordinates
    var topDownTransform = matrix_identity_float4x4
    topDownTransform.columns.0 = vector_float4(inverseRotationMatrix.columns.0, 0)
    topDownTransform.columns.1 = vector_float4(inverseRotationMatrix.columns.1, 0)
    topDownTransform.columns.2 = vector_float4(inverseRotationMatrix.columns.2, 0)
    topDownTransform.columns.3 = vector_float4(0, 0, 0, 1) // No translation
    
    // Optionally, apply an additional rotation for portrait mode
    let portraitModeMatrix = matrix_float4x4([
        [0, -1,  0, 0],
        [1,  0,  0, 0],
        [0,  0,  1, 0],
        [0,  0,  0, 1]
    ])
    
    // Combine the transformations
    let finalMatrix = portraitModeMatrix * topDownTransform
    
    return finalMatrix
}

func convertToHomographyMatrix(_ matrix: matrix_float4x4) -> matrix_float3x3 {
    let homographyMatrix = matrix_float3x3([
        vector_float3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
        vector_float3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
        vector_float3(matrix.columns.3.x, matrix.columns.3.y, 1)
    ])
    
    return homographyMatrix
}

func applyHomography(to image: UIImage, using homographyMatrix: matrix_float3x3) -> UIImage? {
    let ciImage = CIImage(image: image)
    
    // Convert matrix_float3x3 to a format compatible with Core Image
    let homography = CIFilter(name: "CIPerspectiveTransform")
    
    // Set the corners of the quadrilateral in the original image
    homography?.setValue(ciImage, forKey: kCIInputImageKey)
    homography?.setValue(CIVector(x: 0, y: 0), forKey: "inputTopLeft")
    homography?.setValue(CIVector(x: image.size.width, y: 0), forKey: "inputTopRight")
    homography?.setValue(CIVector(x: 0, y: image.size.height), forKey: "inputBottomLeft")
    homography?.setValue(CIVector(x: image.size.width, y: image.size.height), forKey: "inputBottomRight")
    
    // Apply the transformation
    let context = CIContext()
    if let outputImage = homography?.outputImage,
       let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
        return UIImage(cgImage: cgImage)
    }
    
    return nil
}

func correctImagePerspective(cameraTransform: simd_float4x4, image: UIImage) -> UIImage? {
    // Step 1: Get the top-down homography matrix
    let topDownMatrix = getTopDownHomographyMatrix(cameraTransform: cameraTransform)
    
    // Step 2: Convert to a 3x3 homography matrix
    let homographyMatrix = convertToHomographyMatrix(topDownMatrix)
    
    // Step 3: Apply the homography to the image
    return applyHomography(to: image, using: homographyMatrix)
}

func depthMapToBinaryMask(depthPixelBuffer: CVPixelBuffer) -> UIImage? {
    CVPixelBufferLockBaseAddress(depthPixelBuffer, .readOnly)
    
    let width = CVPixelBufferGetWidth(depthPixelBuffer)
    let height = CVPixelBufferGetHeight(depthPixelBuffer)
    
    // Access the depth data
    let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer)
    let buffer = baseAddress!.assumingMemoryBound(to: Float32.self)
    
    // Find the depth value at the center of the image
    let centerX = width / 2
    let centerY = height / 2
    let centerDepthValue = buffer[centerY * width + centerX]
    
    // Define a threshold around the center depth value
    let depthThreshold: Float32 = 0.02 // Adjust based on your needs
    
    // Create a binary mask
    var maskBuffer = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            let index = y * width + x
            let depthValue = buffer[index]
            
            if abs(depthValue - centerDepthValue) < depthThreshold {
                maskBuffer[index] = 255 // Object region
            } else {
                maskBuffer[index] = 0   // Background
            }
        }
    }
    
    CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly)
    
    // Convert the mask buffer to a UIImage
    let maskData = Data(maskBuffer)
    let providerRef = CGDataProvider(data: maskData as CFData)
    
    guard let maskCGImage = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: providerRef!,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        return nil
    }
    
    let binaryMaskImage = UIImage(cgImage: maskCGImage)
    
    // Rotate the binary mask by 90 degrees (adjust the direction as needed)
    let rotatedMaskImage = binaryMaskImage.rotated(byDegrees: 90) // Use 90 or -90 depending on the rotation direction
    
    return rotatedMaskImage
}

func applyNonLinearDepthTransformation(depthMap: CVPixelBuffer) -> CVPixelBuffer? {
    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    
    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)
    let pixelFormatType = CVPixelBufferGetPixelFormatType(depthMap)
    
    guard pixelFormatType == kCVPixelFormatType_DepthFloat32 else {
        // Ensure the pixel format is 32-bit float (as depth maps typically are)
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        return nil
    }
    
    let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
    let buffer = baseAddress!.assumingMemoryBound(to: Float32.self)
    
    var transformedDepthMap = [Float32](repeating: 0.0, count: width * height)
    
    // Apply a non-linear transformation to each depth value
    for y in 0..<height {
        for x in 0..<width {
            let index = y * width + x
            let depthValue = buffer[index]
            
            // Apply an example transformation (e.g., exponential)
            let transformedValue = exp(depthValue)
            transformedDepthMap[index] = transformedValue
        }
    }
    
    CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
    
    // Create a new CVPixelBuffer to hold the transformed data
    var newPixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        pixelFormatType,
        nil,
        &newPixelBuffer
    )
    
    guard status == kCVReturnSuccess, let newBuffer = newPixelBuffer else {
        return nil
    }
    
    // Copy the transformed data into the new CVPixelBuffer
    CVPixelBufferLockBaseAddress(newBuffer, [])
    let newBaseAddress = CVPixelBufferGetBaseAddress(newBuffer)
    let newBufferPointer = newBaseAddress!.assumingMemoryBound(to: Float32.self)
    
    for i in 0..<(width * height) {
        newBufferPointer[i] = transformedDepthMap[i]
    }
    
    CVPixelBufferUnlockBaseAddress(newBuffer, [])
    
    return newBuffer
}
