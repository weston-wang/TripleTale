//
//  ImageConverter.swift
//  TripleTale
//
//  Created by Wes Wang on 6/3/25.
//

import UIKit
import CoreImage
import CoreVideo

struct ImageConverter {
    
    /// Converts a UIImage into a CVPixelBuffer.
    static func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }

        let frameSize = CGSize(width: cgImage.width, height: cgImage.height)
        var pixelBuffer: CVPixelBuffer?

        let options: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(frameSize.width),
                                         Int(frameSize.height),
                                         kCVPixelFormatType_32BGRA, // Choose format appropriate for your depth data
                                         options as CFDictionary,
                                         &pixelBuffer)

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(buffer)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData,
                                width: Int(frameSize.width),
                                height: Int(frameSize.height),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        context?.draw(cgImage, in: CGRect(origin: .zero, size: frameSize))
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return buffer
    }

    static func pixelBufferToUIImage(pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let rotation = CGAffineTransform(rotationAngle: -.pi / 2)
        let rotatedCIImage = ciImage.transformed(by: rotation)

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(rotatedCIImage, from: rotatedCIImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func convertCGImageToGrayscalePixelData(_ cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        let bitsPerComponent = 8
        let bytesPerPixel = 1
        let bytesPerRow = width * bytesPerPixel

        var pixelData = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: &pixelData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelData
    }
    
    // Convert grayscale pixel data back to a UIImage
    static func createUIImageFromGrayscalePixelData(pixelData: [UInt8], width: Int, height: Int) -> UIImage? {
        let bytesPerPixel = 1
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        guard let context = CGContext(data: UnsafeMutableRawPointer(mutating: pixelData),
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let cgImage = context.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    static func resizeMaskToOriginal(maskImage: UIImage, targetSize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        maskImage.draw(in: CGRect(origin: .zero, size: targetSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
    }
    
    
    /// Resize and pad a mask image so that the longest side becomes `targetLongestSide`, and then pad to a square of `outputSize`×`outputSize`.
    /// This is useful for mask images that should not be interpolated (preserve edges).
    static func resizeAndPadMaskImage(_ image: UIImage, targetLongestSide: CGFloat = 224, outputSize: CGFloat = 256) -> UIImage? {
        let originalSize = image.size
        let scale = targetLongestSide / max(originalSize.width, originalSize.height)
        let newSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)

        // Resize the image while preserving the mask nature (no interpolation)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        if let context = UIGraphicsGetCurrentContext() {
            context.interpolationQuality = .none
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()

        // Create square canvas with transparent background
        let canvasSize = CGSize(width: outputSize, height: outputSize)
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 1.0)
        let origin = CGPoint(
            x: (outputSize - newSize.width) / 2.0,
            y: (outputSize - newSize.height) / 2.0
        )
        resizedImage.draw(in: CGRect(origin: origin, size: newSize))
        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return finalImage
    }
    
    static func thresholdGrayscaleImage(pixelData: [UInt8], width: Int, height: Int, threshold: UInt8) -> [UInt8] {
        var binaryData = pixelData
        for i in 0..<pixelData.count {
            binaryData[i] = pixelData[i] > threshold ? 255 : 0
        }
        return binaryData
    }
}
