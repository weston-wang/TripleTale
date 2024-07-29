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

func findAnchors(_ fishBoundingBox: CGRect, _ imageSize: CGSize, _ currentView: ARSKView, _ isForward: Bool) -> (ARAnchor?, [ARAnchor], Float) {
    var centroidAnchor: ARAnchor?
    var midpointAnchors: [ARAnchor]
    
    var useBoundingBox: CGRect
    
    var nudgeRate: Float = 0.0
    
    if !isForward {
        useBoundingBox = fishBoundingBox
        
        // calculate centroid beneath fish, will fail if not all corners available
        let cornerAnchors = getCorners(currentView, fishBoundingBox, imageSize)
        centroidAnchor = createNudgedCentroidAnchor(from: cornerAnchors, nudgePercentage: 0.1)

    } else {
        nudgeRate = 0.1
        
        let tightFishBoundingBox = nudgeBoundingBox(fishBoundingBox,nudgeRate)
        useBoundingBox = tightFishBoundingBox

        centroidAnchor = getTailAnchor(currentView, tightFishBoundingBox, imageSize)
    }
    
    if centroidAnchor != nil {
        // interact with AR world and define anchor points
        midpointAnchors = getMidpoints(currentView, useBoundingBox, imageSize)
        
        return(centroidAnchor, midpointAnchors, nudgeRate)
    } else {
        return(nil, [], nudgeRate)
    }
}
