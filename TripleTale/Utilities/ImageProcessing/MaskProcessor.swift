//
//  MaskProcessor.swift
//  TripleTale
//
//  Created by Wes Wang on 6/9/25.
//
import CoreImage
import UIKit
import Vision

struct MaskProcessor {
    static func generateMaskImage(from image: UIImage, for portion: CGFloat) -> CIImage? {
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
    
    static func fillHolesInMask(_ cgImage: CGImage) -> UIImage? {
        let ciImage = CIImage(cgImage: cgImage)

        // 1. Apply dilation (morphology maximum)
        guard let dilate = CIFilter(name: "CIMorphologyMaximum") else { return nil }
        dilate.setValue(ciImage, forKey: kCIInputImageKey)
        dilate.setValue(1, forKey: kCIInputRadiusKey)
        guard let dilated = dilate.outputImage else { return nil }

        // 2. Apply erosion (morphology minimum)
        guard let erode = CIFilter(name: "CIMorphologyMinimum") else { return nil }
        erode.setValue(dilated, forKey: kCIInputImageKey)
        erode.setValue(1, forKey: kCIInputRadiusKey)
        guard let closed = erode.outputImage else { return nil }

        // 3. Convert back to UIImage
        let context = CIContext()
        guard let outputCG = context.createCGImage(closed, from: closed.extent) else { return nil }

        return UIImage(cgImage: outputCG)
    }
    
    private static func centerROI(for image: CIImage, portion: CGFloat) -> CGRect {
        // Calculate the dimensions of the ROI
        let roiWidth = portion
        let roiHeight = portion
        
        // Calculate the position to center the ROI
        let roiX = (1.0 - roiWidth) / 2.0
        let roiY = (1.0 - roiHeight) / 2.0
        
        // Create and return the CGRect for the ROI
        return CGRect(x: roiX, y: roiY, width: roiWidth, height: roiHeight)
    }
}
