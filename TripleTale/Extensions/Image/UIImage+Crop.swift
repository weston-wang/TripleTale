//
//  UIImage+Crop.swift
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
    func cropCenter(to percent: CGFloat) -> UIImage? {
        let width = self.size.width
        let height = self.size.height
        let newWidth = width * percent
        let newHeight = height * percent
        let cropRect = CGRect(x: (width - newWidth) / 2, y: (height - newHeight) / 2, width: newWidth, height: newHeight)
        
        guard let cgImage = self.cgImage?.cropping(to: cropRect) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage, scale: self.scale, orientation: self.imageOrientation)
    }
    
    func cropEllipse(centeredIn size: CGSize) -> UIImage? {
        // Calculate the rectangle for the ellipse
        let rect = CGRect(x: (self.size.width - size.width) / 2,
                          y: (self.size.height - size.height) / 2,
                          width: size.width,
                          height: size.height)
        
        // Begin a new image context
        UIGraphicsBeginImageContextWithOptions(rect.size, false, self.scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        // Translate context so that the ellipse is centered in the final image
        context.translateBy(x: -rect.origin.x, y: -rect.origin.y)
        
        // Create the path for the ellipse
        let ellipsePath = UIBezierPath(ovalIn: rect)
        
        // Clip the context to the ellipse path
        ellipsePath.addClip()
        
        // Draw the image in the context
        self.draw(at: .zero)
        
        // Get the new image from the context
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        
        // End the image context
        UIGraphicsEndImageContext()
        
        return newImage
    }
    
    func croppedToAspectRatio(size: CGSize) -> UIImage? {
        let originalAspectRatio = self.size.width / self.size.height
        let targetAspectRatio = size.width / size.height
        
        var newSize: CGSize
        if originalAspectRatio > targetAspectRatio {
            // Image is too wide, adjust width
            newSize = CGSize(width: self.size.height * targetAspectRatio, height: self.size.height)
        } else {
            // Image is too tall, adjust height
            newSize = CGSize(width: self.size.width, height: self.size.width / targetAspectRatio)
        }
        
        let cropRect = CGRect(
            x: (self.size.width - newSize.width) / 2,
            y: (self.size.height - newSize.height) / 2,
            width: newSize.width,
            height: newSize.height
        )
        
        guard let cgImage = self.cgImage?.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cgImage, scale: self.scale, orientation: self.imageOrientation)
    }
    
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, self.scale)
        self.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage
    }
    
    func downscale(to maxDimension: CGFloat) -> UIImage? {
        let originalSize = self.size
        
        // Check if the image is already smaller than the maxDimension
        if originalSize.width <= maxDimension && originalSize.height <= maxDimension {
            // Return the original image if no downscaling is needed
            return self
        }
        
        let aspectRatio = originalSize.width / originalSize.height
        var newSize: CGSize
        
        if originalSize.width > originalSize.height {
            // Width is the longer dimension
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            // Height is the longer dimension
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        // Create a new UIGraphicsImageRenderer for drawing the downscaled image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let downscaledImage = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return downscaledImage
    }
    
    /// Returns a new image centered and padded with transparent space to the specified target size.
    func paddedToSize(_ targetSize: CGSize) -> UIImage? {
        let originX = (targetSize.width - self.size.width) / 2
        let originY = (targetSize.height - self.size.height) / 2

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let paddedImage = renderer.image { _ in
            UIColor.clear.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            self.draw(at: CGPoint(x: originX, y: originY))
        }

        return paddedImage
    }
}
