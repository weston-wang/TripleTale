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

extension UIView {
    func showToast(message: String, duration: TimeInterval = 8.0) {
        let toastLabel = UILabel(frame: CGRect(x: self.frame.size.width / 2 - 150, y: 40, width: 300, height: 35)) // Adjusted y coordinate
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toastLabel.textColor = UIColor.white
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.boldSystemFont(ofSize: 12.0) // Changed to bold system font
        toastLabel.text = message
        toastLabel.alpha = 1.0
        toastLabel.layer.cornerRadius = 10
        toastLabel.clipsToBounds = true
        self.addSubview(toastLabel)
        UIView.animate(withDuration: duration, delay: 0.1, options: .curveEaseOut, animations: {
            toastLabel.alpha = 0.0
        }, completion: {(isCompleted) in
            toastLabel.removeFromSuperview()
        })
    }
}

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

extension UIImage {
    func imageWithText(_ text: String, atPoint point: CGPoint, fontSize: CGFloat, textColor: UIColor) -> UIImage? {
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor
        ]
        
        // Start drawing image context
        UIGraphicsBeginImageContextWithOptions(self.size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        // Draw the original image
        self.draw(in: CGRect(origin: CGPoint.zero, size: self.size))
        
        // Define text rectangle
        let rect = CGRect(origin: point, size: self.size)
        
        // Draw text in the rect
        text.draw(in: rect, withAttributes: textAttributes)
        
        // Get the new image
        return UIGraphicsGetImageFromCurrentImageContext()
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

func pixelBufferToUIImage(pixelBuffer: CVPixelBuffer) -> UIImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    
    let rotation = CGAffineTransform(rotationAngle: -.pi / 2)
    let rotatedCIImage = ciImage.transformed(by: rotation)

    let context = CIContext(options: nil)
    guard let cgImage = context.createCGImage(rotatedCIImage, from: rotatedCIImage.extent) else { return nil }
    return UIImage(cgImage: cgImage)
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

func getScreenPosition(_ currentView: ARSKView, _ normalizedX: CGFloat, _ normalizedY: CGFloat, _ capturedImageSize: CGSize) -> CGPoint {
    let imageWidth = capturedImageSize.width
    let imageHeight = capturedImageSize.height
    
    let viewWidth = currentView.bounds.width
    let viewHeight = currentView.bounds.height
    
    let imageAspectRatio = imageWidth / imageHeight
    let viewAspectRatio = viewWidth / viewHeight
    
    var adjustedX = normalizedX
    var adjustedY = normalizedY
    
    if imageAspectRatio > viewAspectRatio {
        // Image is wider than the view
        let scaleFactor = viewHeight / imageHeight
        let scaledImageWidth = imageWidth * scaleFactor
        let croppedWidth = (scaledImageWidth - viewWidth) / 2 / scaledImageWidth
        
        adjustedX = (normalizedX - croppedWidth) / (1 - 2 * croppedWidth)
    } else {
        // View is wider than the image
        let scaleFactor = viewWidth / imageWidth
        let scaledImageHeight = imageHeight * scaleFactor
        let croppedHeight = (scaledImageHeight - viewHeight) / 2 / scaledImageHeight
        
        adjustedY = (normalizedY - croppedHeight) / (1 - 2 * croppedHeight)
    }
    
    // Map the adjusted normalized coordinates to the current view bounds
    let actualPosition = CGPoint(
        x: adjustedX * viewWidth,
        y: (1 - adjustedY) * viewHeight  // Adjusting for UIKit's coordinate system
    )
    
    return actualPosition
}

// Example usa

func addAnchor(_ currentView: ARSKView, _ point: CGPoint) -> ARAnchor {
   let newAnchor: ARAnchor
   
   let hitTestResults = currentView.hitTest(point, types: [.featurePoint, .estimatedHorizontalPlane])
   let result = hitTestResults.first
   newAnchor = ARAnchor(transform: result!.worldTransform)
   
   return newAnchor
}

func getMidpoints(_ currentView: ARSKView, _ boundingBox: CGRect, _ capturedImageSize: CGSize) -> [ARAnchor] {
    var cornerAnchors: [ARAnchor] = []
    
    let leftMiddle = getScreenPosition(currentView, boundingBox.origin.x, boundingBox.origin.y + boundingBox.size.height / 2, capturedImageSize)
    let anchorLeft = addAnchor(currentView, leftMiddle)

    let rightMiddle = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width, boundingBox.origin.y + boundingBox.size.height / 2, capturedImageSize)
    let anchorRight = addAnchor(currentView, rightMiddle)
    
    let topMiddle = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width / 2, boundingBox.origin.y, capturedImageSize)
    let anchorTop = addAnchor(currentView, topMiddle)
    
    let bottomMiddle = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width / 2, boundingBox.origin.y + boundingBox.size.height, capturedImageSize)
    let anchorBottom = addAnchor(currentView, bottomMiddle)
    
    let center = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width / 2, boundingBox.origin.y + boundingBox.size.height / 2, capturedImageSize)
    let anchorCenter = addAnchor(currentView, center)
    
    let reference = getScreenPosition(currentView, boundingBox.origin.x, boundingBox.origin.y, capturedImageSize)
    let anchorReference = addAnchor(currentView, reference)
    
    cornerAnchors.append(anchorLeft)
    cornerAnchors.append(anchorRight)
    cornerAnchors.append(anchorTop)
    cornerAnchors.append(anchorBottom)
    cornerAnchors.append(anchorCenter)
    cornerAnchors.append(anchorReference)

    return cornerAnchors
}


func getCorners(_ currentView: ARSKView, _ boundingBox: CGRect, _ capturedImageSize: CGSize) -> [ARAnchor] {
    var cornerAnchors: [ARAnchor] = []
    
    let leftTop = getScreenPosition(currentView, boundingBox.origin.x, boundingBox.origin.y + boundingBox.size.height, capturedImageSize)
    let anchorLT = addAnchor(currentView, leftTop)

    let rightTop = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width, boundingBox.origin.y + boundingBox.size.height, capturedImageSize)
    let anchorRT = addAnchor(currentView, rightTop)
    
    let leftBottom = getScreenPosition(currentView, boundingBox.origin.x, boundingBox.origin.y, capturedImageSize)
    let anchorLB = addAnchor(currentView, leftBottom)
    
    let rightBottom = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width, boundingBox.origin.y, capturedImageSize)
    let anchorRB = addAnchor(currentView, rightBottom)
    
    cornerAnchors.append(anchorLT)
    cornerAnchors.append(anchorRT)
    cornerAnchors.append(anchorLB)
    cornerAnchors.append(anchorRB)

    return cornerAnchors
}


func transformHeightAnchor(ref refAnchor: ARAnchor, cen centerAnchor: ARAnchor) -> ARAnchor {
    let anchor1Transform = refAnchor.transform
    let anchor1Position = SIMD3<Float>(anchor1Transform.columns.3.x, anchor1Transform.columns.3.y, anchor1Transform.columns.3.z)

    let anchor2Transform = centerAnchor.transform
    let anchor2Position = SIMD3<Float>(anchor2Transform.columns.3.x, anchor2Transform.columns.3.y, anchor2Transform.columns.3.z)

    var newTransform = anchor2Transform  // Start with the current transform
    newTransform.columns.3.x = anchor1Position.x
    newTransform.columns.3.y = anchor2Position.y
    newTransform.columns.3.z = anchor1Position.z  // If you want to match Z as well
    
    return ARAnchor(transform: newTransform)
}

func createNudgedCentroidAnchor(from cornerAnchors: [ARAnchor], nudgePercentage: Float) -> ARAnchor? {
    // Ensure there are at least 4 anchors
    guard cornerAnchors.count >= 4 else {
        return nil
    }

    // Helper function to get the position from an anchor
    func position(from anchor: ARAnchor) -> SIMD3<Float> {
        return SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
    }

    // Get the positions of the anchors
    var lTPos = position(from: cornerAnchors[0])
    var rTPos = position(from: cornerAnchors[1])
    var lBPos = position(from: cornerAnchors[2])
    var rBPos = position(from: cornerAnchors[3])

    // Calculate the width and height based on anchor positions
    let width = simd_length(rTPos - lTPos)
    let height = simd_length(rTPos - rBPos)

    // Nudge each position by the specified percentage
    lTPos.x -= width * nudgePercentage
    lTPos.y += height * nudgePercentage
    
    rTPos.x += width * nudgePercentage
    rTPos.y += height * nudgePercentage
    
    lBPos.x -= width * nudgePercentage
    lBPos.y -= height * nudgePercentage
    
    rBPos.x += width * nudgePercentage
    rBPos.y -= height * nudgePercentage

    // Calculate the centroid
    let centroid = (lTPos + rTPos + lBPos + rBPos) / 4.0

    // Create a new transform with the centroid position
    var centroidTransform = matrix_identity_float4x4
    centroidTransform.columns.3 = SIMD4<Float>(centroid.x, centroid.y, centroid.z, 1.0)

    // Create and return a new ARAnchor at the centroid position
    return ARAnchor(transform: centroidTransform)
}

func reversePerspectiveEffectOnBoundingBox(boundingBox: CGRect, distanceToPhone: Float, totalDistance: Float) -> CGRect {
    // Calculate the inverse scaling factor for dimensions
    let scalingFactor = distanceToPhone / totalDistance

    // Reverse the bounding box dimensions
    let originalWidth = boundingBox.width * CGFloat(scalingFactor)
    let originalHeight = boundingBox.height * CGFloat(scalingFactor)

    // Reverse the bounding box position
    let originalX = boundingBox.origin.x * CGFloat(scalingFactor)
    let originalY = boundingBox.origin.y * CGFloat(scalingFactor)

    // Return the original bounding box
    return CGRect(x: originalX, y: originalY, width: originalWidth, height: originalHeight)
}
