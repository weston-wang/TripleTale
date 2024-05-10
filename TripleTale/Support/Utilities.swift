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

// Convert device orientation to image orientation for use by Vision analysis.
extension CGImagePropertyOrientation {
    init(_ deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portraitUpsideDown: self = .left
        case .landscapeLeft: self = .up
        case .landscapeRight: self = .down
        default: self = .right
        }
    }
}

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

func drawRectanglesOnImage(image: UIImage, boundingBoxes: [CGRect]) -> UIImage {
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    image.draw(at: CGPoint.zero)
    
    let context = UIGraphicsGetCurrentContext()!
    context.setStrokeColor(UIColor.green.cgColor)
    context.setLineWidth(5.0)
    
    for rect in boundingBoxes {
        let transformedRect = CGRect(x: rect.origin.x * image.size.width,
                                     y: (1 - rect.origin.y - rect.size.height) * image.size.height,
                                     width: rect.size.width * image.size.width,
                                     height: rect.size.height * image.size.height)
        context.stroke(transformedRect)
    }
    
    let newImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    
    return newImage
}

func cropImage(_ image: UIImage, withNormalizedRect normalizedRect: CGRect) -> UIImage? {
    // Calculate the actual rect based on image size
    let rect = CGRect(x: normalizedRect.origin.x * image.size.width,
        y: (1 - normalizedRect.origin.y - normalizedRect.size.height) * image.size.height,
        width: normalizedRect.size.width * image.size.width,
        height: normalizedRect.size.height * image.size.height)
    
    // Convert UIImage to CGImage to work with Core Graphics
    guard let cgImage = image.cgImage else { return nil }
    
    // Cropping the image with rect
    guard let croppedCgImage = cgImage.cropping(to: rect) else { return nil }
    
    // Convert cropped CGImage back to UIImage
    return UIImage(cgImage: croppedCgImage, scale: image.scale, orientation: image.imageOrientation)
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

func getScreenPosition(_ currentView: ARSKView, _ xPos: CGFloat, _ yPos: CGFloat) -> CGPoint {
    let normalizedPoint = CGPoint(x: xPos, y: yPos)
    
    let actualPosition = CGPoint(
        x: normalizedPoint.x * currentView.bounds.width,
        y: (1 - normalizedPoint.y) * currentView.bounds.height  // Adjusting for UIKit's coordinate system
    )
    
    return actualPosition
}

func addAnchor(_ currentView: ARSKView, _ point: CGPoint) -> ARAnchor {
   let newAnchor: ARAnchor
   
   let hitTestResults = currentView.hitTest(point, types: [.featurePoint, .estimatedHorizontalPlane])
   let result = hitTestResults.first
   newAnchor = ARAnchor(transform: result!.worldTransform)
   
   return newAnchor
}
