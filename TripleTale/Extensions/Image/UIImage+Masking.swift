//
//  UIImage+Masking.swift
//  TripleTale
//
//  Created by Wes Wang on 6/2/25.
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

extension UIImage {
    func masked(with mask: CIImage) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }

        let inputCIImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CIBlendWithMask") else { return nil }
        filter.setValue(inputCIImage, forKey: kCIInputImageKey)
        filter.setValue(mask, forKey: kCIInputMaskImageKey)
        filter.setValue(CIImage(color: .clear).cropped(to: inputCIImage.extent), forKey: kCIInputBackgroundImageKey)

        guard let outputImage = filter.outputImage else { return nil }

        let width = Int(mask.extent.width)
        let height = Int(mask.extent.height)
        let bytesPerRow = width
        let colorSpace = CGColorSpaceCreateDeviceGray()

        let context = CIContext()
        guard let maskCG = context.createCGImage(mask, from: mask.extent),
              let bitmapContext = CGContext(data: nil,
                                            width: width,
                                            height: height,
                                            bitsPerComponent: 8,
                                            bytesPerRow: bytesPerRow,
                                            space: colorSpace,
                                            bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let buffer = bitmapContext.data else {
            return nil
        }

        bitmapContext.draw(maskCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Find bounding box of non-zero mask pixels
        var minX = width, minY = height, maxX = 0, maxY = 0
        for y in 0..<height {
            for x in 0..<width {
                let pixel = buffer.load(fromByteOffset: y * bytesPerRow + x, as: UInt8.self)
                if pixel > 10 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minX < maxX, minY < maxY else { return nil }

        // Flip y-axis because Core Image uses bottom-left origin
        let flippedCropRect = CGRect(
            x: minX,
            y: height - maxY,
            width: maxX - minX,
            height: maxY - minY
        ).integral

        guard let croppedCG = context.createCGImage(outputImage.cropped(to: flippedCropRect), from: flippedCropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCG, scale: self.scale, orientation: self.imageOrientation)
    }

    func maskedWithSameSize(with mask: CIImage) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }

        let inputCIImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CIBlendWithMask") else { return nil }
        filter.setValue(inputCIImage, forKey: kCIInputImageKey)
        filter.setValue(mask, forKey: kCIInputMaskImageKey)
        filter.setValue(CIImage(color: .clear).cropped(to: inputCIImage.extent), forKey: kCIInputBackgroundImageKey)

        guard let outputImage = filter.outputImage else { return nil }

        let context = CIContext()
        guard let fullSizeCG = context.createCGImage(outputImage, from: inputCIImage.extent) else {
            return nil
        }

        return UIImage(cgImage: fullSizeCG, scale: self.scale, orientation: self.imageOrientation)
    }

    func forceRGB() -> UIImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = 4 * width

        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let cgImage = self.cgImage else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(cgImage, in: rect)

        guard let newCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: newCGImage)
    }

    func applyBlurOutsideEllipse(portion: CGFloat) -> UIImage? {
        let imageSize = self.size
        let imageHeight = imageSize.height
        
        // Calculate the ellipse dimensions
        let ellipseHeight = imageHeight * portion
        let ellipseWidth = ellipseHeight / 3 * 1.1
        let ellipseRect = CGRect(x: (imageSize.width - ellipseWidth) / 2,
                                 y: (imageSize.height - ellipseHeight) / 2,
                                 width: ellipseWidth,
                                 height: ellipseHeight)
        
        // Create the ellipse path
        let ellipsePath = UIBezierPath(ovalIn: ellipseRect)
        
        // Create a mask layer
        let maskLayer = CAShapeLayer()
        maskLayer.frame = CGRect(origin: .zero, size: imageSize)
        maskLayer.fillRule = .evenOdd
        
        // The outer path is a rectangle covering the entire image
        let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: imageSize))
        outerPath.append(ellipsePath)
        
        maskLayer.path = outerPath.cgPath
        
        // Apply the mask to the image
        UIGraphicsBeginImageContextWithOptions(imageSize, false, self.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Draw the image
        self.draw(at: .zero)
        
        // Clip the context to the mask
        context.saveGState()
        context.addPath(maskLayer.path!)
        context.clip(using: .evenOdd)
        
        // Apply the blur effect outside the ellipse
        let blurredImage = self.applyingBlurWithRadius(10) // Adjust the radius as needed
        blurredImage?.draw(at: .zero)
        
        context.restoreGState()
        
        // Get the resulting image
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resultImage
    }
    
    func applyingBlurWithRadius(_ radius: CGFloat) -> UIImage? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        
        guard let outputImage = filter?.outputImage else { return nil }
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(outputImage, from: ciImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage, scale: self.scale, orientation: self.imageOrientation)
    }
    
}
