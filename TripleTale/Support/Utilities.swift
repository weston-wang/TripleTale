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

// Step 1: Crop the Image to the Bounding Box (optional)
func cropImageToNormalizedBoundingBox(image: UIImage, boundingBox: CGRect) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }
    let width = image.size.width
    let height = image.size.height
    
    // Convert normalized bounding box to pixel coordinates
    let rect = CGRect(x: boundingBox.origin.x * width,
                      y: boundingBox.origin.y * height,
                      width: boundingBox.width * width,
                      height: boundingBox.height * height)
    
    guard let croppedCgImage = cgImage.cropping(to: rect) else { return nil }
    return UIImage(cgImage: croppedCgImage, scale: image.scale, orientation: image.imageOrientation)
}

// Step 2: Preprocess Image
func preprocessImage(image: UIImage) -> CIImage? {
    guard let ciImage = CIImage(image: image) else { return nil }

    // Convert to grayscale
    let grayscaleFilter = CIFilter(name: "CIPhotoEffectMono")!
    grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
    guard let grayscaleImage = grayscaleFilter.outputImage else { return nil }
    
    // Apply Gaussian blur to reduce noise
    let blurFilter = CIFilter(name: "CIGaussianBlur")
    blurFilter?.setValue(grayscaleImage, forKey: kCIInputImageKey)
    blurFilter?.setValue(1.5, forKey: kCIInputRadiusKey)  // Reduce the blur intensity
    guard let blurredImage = blurFilter?.outputImage else { return nil }

    // Apply edge detection
    let edgeFilter = CIFilter(name: "CIEdges")
    edgeFilter?.setValue(blurredImage, forKey: kCIInputImageKey)
    edgeFilter?.setValue(25.0, forKey: "inputIntensity")  // Reduce the edge detection intensity
    guard let edgeImage = edgeFilter?.outputImage else { return nil }

    // Crop the image to discard the border pixels
//    let cropRect = edgeImage.extent.insetBy(dx: 10, dy: 10) // Adjust inset values as needed
//    let croppedEdgeImage = edgeImage.cropped(to: cropRect)

    return edgeImage
}

func ciImageToUIImage(ciImage: CIImage) -> UIImage? {
    let context = CIContext(options: nil)
    if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
        return UIImage(cgImage: cgImage)
    }
    return nil
}

func detectAllContours(in image: CIImage, completion: @escaping ([[CGPoint]]) -> Void) {
    let request = VNDetectContoursRequest { request, error in
        guard let observations = request.results as? [VNContoursObservation], let observation = observations.first else {
            completion([])
            return
        }
        
        var allContours: [[CGPoint]] = []
        
        print("Number of contours: \(observation.contourCount)")
        
        for i in 0..<observation.contourCount {
            guard let contour = try? observation.contour(at: i) else { continue }
            
            let points = contour.normalizedPoints.map { CGPoint(x: CGFloat($0.x), y: 1 - CGFloat($0.y)) }
            
            // Create path to check bounding box
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            
            let boundingBox = path.boundingBox
            
            // Define a threshold for excluding large contours that are likely borders
            let imageWidth = image.extent.width
            let imageHeight = image.extent.height
            let boundingBoxArea = boundingBox.width * boundingBox.height
            let imageArea = imageWidth * imageHeight
            
            // Ignore contours that are likely the image border based on area, aspect ratio, and proximity to image edges
            let imageAspectRatio = imageWidth / imageHeight
            let contourAspectRatio = boundingBox.width / boundingBox.height
            
            // Check if the bounding box is almost the size of the image and has a similar aspect ratio
            let isBorder = abs(contourAspectRatio - imageAspectRatio) < 0.1 &&
                           boundingBox.width > 0.9 * imageWidth && boundingBox.height > 0.9 * imageHeight
            
            // Check if the contour is too close to the image edges
            let margin: CGFloat = 0.01 // margin as a fraction of image dimensions
            let closeToEdge = boundingBox.minX < margin * imageWidth ||
                              boundingBox.minY < margin * imageHeight ||
                              boundingBox.maxX > (1 - margin) * imageWidth ||
                              boundingBox.maxY > (1 - margin) * imageHeight
            
            if isBorder && closeToEdge {
                continue
            }
            
            allContours.append(points)
        }
        
        completion(allContours)
    }

    request.detectsDarkOnLight = true  // Set to detect dark on light edges
    request.contrastAdjustment = 1.5   // Adjust contrast for better detection

    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    try? handler.perform([request])
}

// Step 4: Draw all Contours on the Image
func drawContours(on image: UIImage, contours: [[CGPoint]]) -> UIImage? {
    UIGraphicsBeginImageContext(image.size)
    guard let context = UIGraphicsGetCurrentContext() else { return nil }

    // Draw the original image
    image.draw(at: CGPoint.zero)
    
    // Define an array of colors to use for the contours
    let colors: [UIColor] = [
        .red, .green, .blue, .yellow, .cyan, .magenta, .orange, .purple, .brown, .gray
    ]
    
    // Draw all contours
    let scaleX = image.size.width
    let scaleY = image.size.height
    for (index, contour) in contours.enumerated() {
        if !contour.isEmpty {
            // Set contour stroke color and width
            context.setStrokeColor(colors[index % colors.count].cgColor)
            context.setLineWidth(2.0)
            
            context.beginPath()
            context.move(to: CGPoint(x: contour[0].x * scaleX, y: contour[0].y * scaleY))
            for point in contour.dropFirst() {
                context.addLine(to: CGPoint(x: point.x * scaleX, y: point.y * scaleY))
            }
            context.closePath()
            context.strokePath()
        }
    }

    // Get the new image with the contours
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return newImage
}

// Function to filter out border contours and calculate bounding box
func calculateBoundingBox(for contours: [[CGPoint]], imageSize: CGSize) -> CGRect {
    let imageWidth = imageSize.width
    let imageHeight = imageSize.height
    
    let margin: CGFloat = 0.01 // Margin as a fraction of image dimensions
    
    // Filter out border contours
    let filteredContours = contours.filter { contour in
        let boundingBox = contour.reduce(CGRect.null) { rect, point in
            rect.union(CGRect(x: point.x * imageWidth, y: point.y * imageHeight, width: 0, height: 0))
        }
        let closeToEdge = boundingBox.minX < margin * imageWidth ||
                          boundingBox.minY < margin * imageHeight ||
                          boundingBox.maxX > (1 - margin) * imageWidth ||
                          boundingBox.maxY > (1 - margin) * imageHeight
        return !closeToEdge
    }
    
    // Calculate bounding box for remaining contours
    let boundingBox = filteredContours.flatMap { $0 }.reduce(CGRect.null) { rect, point in
        rect.union(CGRect(x: point.x * imageWidth, y: point.y * imageHeight, width: 0, height: 0))
    }
    
    return boundingBox
}

func drawBoundingBox(on image: UIImage, boundingBox: CGRect) -> UIImage? {
    UIGraphicsBeginImageContext(image.size)
    guard let context = UIGraphicsGetCurrentContext() else { return nil }
    
    // Draw the original image
    image.draw(at: CGPoint.zero)
    
    // Draw bounding box
    context.setStrokeColor(UIColor.white.cgColor)
    context.setLineWidth(3.0)
    context.stroke(boundingBox)
    
    // Get the new image with the bounding box
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return newImage
}

// Complete Function to detect and draw the contour
func detectAndDrawLargestContour(in image: UIImage, boundingBox: CGRect?, completion: @escaping (UIImage?) -> Void) {
    var processedImage = image
    
    if let boundingBox = boundingBox {
        guard let croppedImage = cropImageToNormalizedBoundingBox(image: image, boundingBox: boundingBox) else {
            print("Failed to crop image")
            completion(nil)
            return
        }
        processedImage = croppedImage
    }
    
    guard let preprocessedCIImage = preprocessImage(image: processedImage) else {
        print("Failed to preprocess image")
        completion(nil)
        return
    }
    
    let edgeImage = ciImageToUIImage(ciImage: preprocessedCIImage)

    detectAllContours(in: preprocessedCIImage) { contours in
        let boundingBox = calculateBoundingBox(for: contours, imageSize: edgeImage!.size)
        if let imageWithContours = drawContours(on: edgeImage!, contours: contours),
           let finalImage = drawBoundingBox(on: imageWithContours, boundingBox: boundingBox) {
            // Do something with the final image, like displaying it
            completion(finalImage)

            print("Contours and bounding box drawn on image")
        }
    }
}
