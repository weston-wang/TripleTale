//
//  UIImage+Transform.swift
//  TripleTale
//
//  Created by Wes Wang on 6/3/25.
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

/// - Tag: UIImage
extension UIImage {
    func rotate(radians: CGFloat) -> UIImage? {
        var newSize = CGRect(origin: .zero, size: self.size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size

        // Fix for images that are rotated 90 or 270 degrees
        if radians == .pi/2 || radians == -.pi/2 {
            newSize = CGSize(width: newSize.height, height: newSize.width)
        }

        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        context.translateBy(x: newSize.width/2, y: newSize.height/2)
        context.rotate(by: radians)
        self.draw(in: CGRect(x: -self.size.width/2, y: -self.size.height/2,
                             width: self.size.width, height: self.size.height))

        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return rotatedImage
    }
    
    func rotated(byDegrees degrees: CGFloat) -> UIImage? {
        let radians = degrees * (.pi / 180)
        
        var newSize = CGRect(origin: .zero, size: self.size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size
        newSize.width = round(newSize.width)
        newSize.height = round(newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        let context = UIGraphicsGetCurrentContext()!
        
        // Move the origin to the middle of the image so we can rotate around the center.
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        
        // Rotate the image context
        context.rotate(by: radians)
        
        // Now, draw the rotated/scaled image into the context.
        self.draw(in: CGRect(x: -self.size.width / 2, y: -self.size.height / 2, width: self.size.width, height: self.size.height))
        
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return rotatedImage
    }
}
