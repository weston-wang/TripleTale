//
//  ComputerVision.swift
//  tripletalear
//
//  Created by Wes Wang on 8/19/24.
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

func generateMaskImage(from image: UIImage, for portion: CGFloat) -> CIImage? {
    guard let ciImage = CIImage(image: image) else { return nil }

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
