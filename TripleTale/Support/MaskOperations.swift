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
