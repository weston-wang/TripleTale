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

func extractXYCoordinates(from anchors: [ARAnchor]) -> [CGPoint] {
    return anchors.map { CGPoint(x: CGFloat($0.transform.columns.3.x), y: CGFloat($0.transform.columns.3.y)) }
}

