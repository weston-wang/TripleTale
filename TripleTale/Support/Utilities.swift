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


func removeBackground(from image: UIImage) -> (UIImage?, UIImage?, CGRect?) {
    guard let ciImage = CIImage(image: image) else { return (nil, nil, nil) }
    if let maskImage = generateMaskImage(from: ciImage) {
        let outputImage = applyMask(maskImage, to: ciImage)
        
        // Create a CIContext
        let context = CIContext()

        // Create a CGImage from the CIImage
        if let cgImage = context.createCGImage(maskImage, from: maskImage.extent) {
            // Convert the CGImage to a UIImage
            let maskUiImage = UIImage(cgImage: cgImage)
            
//            let boundingBox = boundingBoxForWhiteArea(in: maskUiImage)
            let boundingBox = boundingBoxForCenteredObject(in: maskUiImage)
            return (outputImage, maskUiImage, boundingBox)

        }
        
    }
    return (nil, nil, nil)
}

private func generateMaskImage(from ciImage: CIImage) -> CIImage? {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    
    do {
        try handler.perform([request])
        if let result = request.results?.first {
            let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)

            return CIImage(cvPixelBuffer: maskPixelBuffer)
        }
    } catch {
        print(error.localizedDescription)
    }
    return nil
}

private func calculateBoundingBox(from maskImage: CIImage) -> CGRect? {
    let context = CIContext()
    guard let cgImage = context.createCGImage(maskImage, from: maskImage.extent) else { return nil }

    let width = cgImage.width
    let height = cgImage.height
    guard let data = cgImage.dataProvider?.data else { return nil }
    let pixelData = CFDataGetBytePtr(data)

    var minX = width
    var minY = height
    var maxX: Int = 0
    var maxY: Int = 0

    for y in 0..<height {
        for x in 0..<width {
            let pixelIndex = y * width + x
            let luma = pixelData![pixelIndex]
            if luma > 0 { // Check if the pixel is part of the foreground
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }

    if minX >= maxX || minY >= maxY { return nil }

    let normalizedBoundingBox = CGRect(
        x: CGFloat(minX) / CGFloat(width),
        y: CGFloat(minY) / CGFloat(height),
        width: CGFloat(maxX - minX) / CGFloat(width),
        height: CGFloat(maxY - minY) / CGFloat(height)
    )

    return normalizedBoundingBox
}

private func applyMask(_ mask: CIImage?, to image: CIImage) -> UIImage? {
    guard let mask = mask else { return nil }
    let filter = CIFilter(name: "CIBlendWithMask")
    filter?.setValue(image, forKey: kCIInputImageKey)
    filter?.setValue(mask, forKey: kCIInputMaskImageKey)
    filter?.setValue(CIImage(color: .clear).cropped(to: image.extent), forKey: kCIInputBackgroundImageKey)
    
    let context = CIContext()
    if let outputImage = filter?.outputImage, let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
        return UIImage(cgImage: cgImage)
    }
    return nil
}

func boundingBoxForWhiteArea(in image: UIImage) -> CGRect? {
    guard let cgImage = image.cgImage else {
        return nil
    }

    let width = cgImage.width
    let height = cgImage.height

    // Create a bitmap context for the image
    let colorSpace = CGColorSpaceCreateDeviceGray()
    var pixelData = [UInt8](repeating: 0, count: width * height)
    let context = CGContext(data: &pixelData,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: width,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)

    context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0

    // Find the bounding box of the white area
    for y in 0..<height {
        for x in 0..<width {
            let pixelIndex = y * width + x
            if pixelData[pixelIndex] == 255 { // Assuming white is represented as 255
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
        }
    }

    guard minX <= maxX && minY <= maxY else {
        return nil
    }

    let boundingBox = CGRect(x: CGFloat(minX) / CGFloat(width),
                             y: CGFloat(minY) / CGFloat(height),
                             width: CGFloat(maxX - minX + 1) / CGFloat(width),
                             height: CGFloat(maxY - minY + 1) / CGFloat(height))

    return boundingBox
}

func boundingBoxForCenteredObject(in image: UIImage) -> CGRect? {
    guard let cgImage = image.cgImage else {
        return nil
    }

    let width = cgImage.width
    let height = cgImage.height

    // Create a bitmap context for the image
    let colorSpace = CGColorSpaceCreateDeviceGray()
    var pixelData = [UInt8](repeating: 0, count: width * height)
    let context = CGContext(data: &pixelData,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: width,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)

    context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var visited = Set<Int>()
    var components: [(minX: Int, minY: Int, maxX: Int, maxY: Int)] = []

    let directions = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    func bfs(startX: Int, startY: Int) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        var queue = [(x: Int, y: Int)]()
        queue.append((startX, startY))
        visited.insert(startY * width + startX)

        var minX = startX
        var minY = startY
        var maxX = startX
        var maxY = startY

        while !queue.isEmpty {
            let (x, y) = queue.removeFirst()

            for (dx, dy) in directions {
                let nx = x + dx
                let ny = y + dy
                let index = ny * width + nx

                if nx >= 0 && nx < width && ny >= 0 && ny < height && !visited.contains(index) && pixelData[index] == 255 {
                    visited.insert(index)
                    queue.append((nx, ny))
                    if nx < minX { minX = nx }
                    if ny < minY { minY = ny }
                    if nx > maxX { maxX = nx }
                    if ny > maxY { maxY = ny }
                }
            }
        }

        return (minX, minY, maxX, maxY)
    }

    // Identify all white pixel groups and their bounding boxes
    for y in 0..<height {
        for x in 0..<width {
            let index = y * width + x
            if pixelData[index] == 255 && !visited.contains(index) {
                let boundingBox = bfs(startX: x, startY: y)
                components.append(boundingBox)
            }
        }
    }

    // Find the component closest to the center
    let centerX = width / 2
    let centerY = height / 2
    var closestComponent: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
    var minDistance = Int.max

    for component in components {
        let componentCenterX = (component.minX + component.maxX) / 2
        let componentCenterY = (component.minY + component.maxY) / 2
        let distance = abs(componentCenterX - centerX) + abs(componentCenterY - centerY)

        if distance < minDistance {
            minDistance = distance
            closestComponent = component
        }
    }

    // Normalize the bounding box coordinates
    if let bounds = closestComponent {
        let normalizedBoundingBox = CGRect(x: CGFloat(bounds.minX) / CGFloat(width),
                                           y: CGFloat(bounds.minY) / CGFloat(height),
                                           width: CGFloat(bounds.maxX - bounds.minX + 1) / CGFloat(width),
                                           height: CGFloat(bounds.maxY - bounds.minY + 1) / CGFloat(height))
        return normalizedBoundingBox
    }

    return nil
}
