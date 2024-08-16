//
//  MaskOperations.swift
//  TripleTale
//
//  Created by Wes Wang on 8/5/24.
//  Copyright © 2024 Apple. All rights reserved.
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
import Accelerate


func isolateFish(from image: UIImage, for portion: CGFloat) -> CGRect? {
    guard let ciImage = CIImage(image: image) else { return nil }
    if let maskImage = generateMaskImage(from: ciImage, for: portion) {
//        let outputImage = applyMask(maskImage, to: ciImage)
        
        // Create a CIContext
        let context = CIContext()

        // Create a CGImage from the CIImage
        if let cgImage = context.createCGImage(maskImage, from: maskImage.extent) {
            // Convert the CGImage to a UIImage
            let maskUiImage = UIImage(cgImage: cgImage)
            
//            let boundingBox = boundingBoxForWhiteArea(in: maskUiImage)
            let boundingBox = boundingBoxForCenteredObject(in: maskUiImage)
            return boundingBox

        }
        
    }
    return nil
}

func applyMask(_ mask: CIImage?, to image: CIImage) -> UIImage? {
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

func generateMaskImage(from ciImage: CIImage, for portion: CGFloat) -> CIImage? {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    
    let roiRect = centerROI(for: ciImage, portion: portion)
    request.regionOfInterest = roiRect

    do {
        try handler.perform([request])
        if let result = request.results?.first {
            let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            
            // Create a blank image of the original size
            let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)
            let blankImage = CIImage(color: .black).cropped(to: ciImage.extent)

            // Calculate the translation for the mask
            let translateX = roiRect.origin.x * ciImage.extent.width
            let translateY = roiRect.origin.y * ciImage.extent.height

            // Apply translation to the mask
            let transformedMaskCIImage = maskCIImage.transformed(by: CGAffineTransform(translationX: translateX, y: translateY))

            // Composite the mask onto the blank image
            let finalImage = transformedMaskCIImage.composited(over: blankImage)

            return finalImage
        }
    } catch {
        print(error.localizedDescription)
    }
    return nil
}

func generateMaskImage(from ciImage: CIImage, for portion: CGFloat, widthMultiplier: CGFloat) -> CIImage? {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    
    let roiRect = centerEllipseROI(for: ciImage, portion: portion, widthMultiplier: widthMultiplier)
    request.regionOfInterest = roiRect

    do {
        try handler.perform([request])
        if let result = request.results?.first {
            let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            
            // Create a blank image of the original size
            let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)
            let blankImage = CIImage(color: .black).cropped(to: ciImage.extent)

            // Calculate the translation for the mask
            let translateX = roiRect.origin.x * ciImage.extent.width
            let translateY = roiRect.origin.y * ciImage.extent.height

            // Apply translation to the mask
            let transformedMaskCIImage = maskCIImage.transformed(by: CGAffineTransform(translationX: translateX, y: translateY))

            // Composite the mask onto the blank image
            let finalImage = transformedMaskCIImage.composited(over: blankImage)

            return finalImage
        }
    } catch {
        print(error.localizedDescription)
    }
    return nil
}

func centerEllipseROI(for ciImage: CIImage, portion: CGFloat, widthMultiplier: CGFloat) -> CGRect {
    let imageSize = ciImage.extent.size
    let ellipseHeight = imageSize.height * portion
    var ellipseWidth = (ellipseHeight / 3.0) * widthMultiplier
    ellipseWidth = min(ellipseWidth, imageSize.width) // Ensure width does not exceed image bounds

    let roiX = (imageSize.width - ellipseWidth) / 2.0
    let roiY = (imageSize.height - ellipseHeight) / 2.0

    return CGRect(x: roiX / imageSize.width, y: roiY / imageSize.height, width: ellipseWidth / imageSize.width, height: ellipseHeight / imageSize.height)
}

func detectContours(in image: UIImage, for portion: CGFloat) -> UIImage? {
    guard let ciImage = CIImage(image: image) else { return nil }
    
    let roiRect = centerROI(for: ciImage, portion: portion)
    
    // Step 2: Create the request
    let request = VNDetectContoursRequest()
    request.contrastAdjustment = 1.0
    request.detectsDarkOnLight = true
    request.regionOfInterest = roiRect
    
    // Step 3: Perform the request
    let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        print("Failed to perform contour detection: \(error)")
        return nil
    }
    
    guard let contoursObservation = request.results?.first as? VNContoursObservation else {
        print("No contours detected")
        return nil
    }
    
    // Step 4: Draw the contours on a new image
    let size = image.size
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    guard let context = UIGraphicsGetCurrentContext() else { return nil }
    
    // Draw the original image as the background
    image.draw(at: .zero)
    
    // Set up the drawing context
    context.setStrokeColor(UIColor.red.cgColor)
    context.setLineWidth(2.0)
    
    // Draw each contour within the ROI
    for i in 0..<contoursObservation.contourCount {
        if let contour = try? contoursObservation.contour(at: i) {
            let path = CGMutablePath()
            
            let points = contour.normalizedPoints
            if points.isEmpty { continue }
            
            // Convert normalized points to image space within the ROI and flip y-coordinate
            let firstPoint = CGPoint(
                x: roiRect.minX * size.width + roiRect.width * size.width * CGFloat(points[0].x),
                y: size.height - (roiRect.minY * size.height + roiRect.height * size.height * CGFloat(points[0].y))
            )
            path.move(to: firstPoint)
            
            for point in points.dropFirst() {
                let convertedPoint = CGPoint(
                    x: roiRect.minX * size.width + roiRect.width * size.width * CGFloat(point.x),
                    y: size.height - (roiRect.minY * size.height + roiRect.height * size.height * CGFloat(point.y))
                )
                path.addLine(to: convertedPoint)
            }
            path.closeSubpath()
            
            context.addPath(path)
            context.strokePath()
        }
    }
    
    // Step 5: Get the resulting image
    let resultImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return resultImage
}

func detectSalientRegion(in image: UIImage, for portion: CGFloat) -> UIImage? {
    guard let ciImage = CIImage(image: image) else { return nil }

    let request = VNGenerateAttentionBasedSaliencyImageRequest()

    let roiRect = centerROI(for: ciImage, portion: portion)

    // If ROI is provided, we set it to the request
    request.regionOfInterest = roiRect

    let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        print("Failed to perform saliency detection: \(error)")
        return nil
    }

    guard let observation = request.results?.first as? VNSaliencyImageObservation else {
        print("No saliency detected")
        return nil
    }

    // Get the salient region from the saliency observation
    guard let salientRegion = observation.salientObjects?.first else {
        print("No salient region detected")
        return nil
    }

    let size = image.size
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    guard let context = UIGraphicsGetCurrentContext() else { return nil }

    // Draw the original image as the background
    image.draw(at: .zero)

    // Draw the detected salient region (the bounding box)
    context.setStrokeColor(UIColor.red.cgColor)
    context.setLineWidth(2.0)
    context.stroke(salientRegion.boundingBox.applying(CGAffineTransform(scaleX: size.width, y: size.height)))

    let resultImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return resultImage
}
