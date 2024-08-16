//
//  Extensions.swift
//  TripleTale
//
//  Created by Wes Wang on 7/29/24.
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

/// - Tag: UIView
extension UIView {
    func showToast(message: String, duration: TimeInterval = 10.0) {
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

/// - Tag: CGImagePropertyOrientation
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

/// - Tag: UIImage
extension UIImage {
    func cropCenter(to percent: CGFloat) -> UIImage? {
        // Ensure the percentage is between 0 and 100
        let percentage = max(0, min(100, percent))
        
        let width = self.size.width
        let height = self.size.height
        let newWidth = width * (percentage / 100.0)
        let newHeight = height * (percentage / 100.0)
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
    
    func imageWithText(_ text: String, atPoint point: CGPoint, fontSize: CGFloat, textColor: UIColor) -> UIImage? {
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor,
            .backgroundColor: UIColor.black
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
    
    func imageWithCenteredText(_ text: String, fontSize: CGFloat, textColor: UIColor) -> UIImage? {
        // Create a paragraph style with center alignment
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        // Create a shadow for the text (optional)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.gray
        shadow.shadowOffset = CGSize(width: 2, height: 2)
        shadow.shadowBlurRadius = 1
        
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]
        
        // Start drawing image context
        UIGraphicsBeginImageContextWithOptions(self.size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        // Draw the original image
        self.draw(in: CGRect(origin: CGPoint.zero, size: self.size))
        
        // Define text size
        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: self.size.width, height: self.size.height),
            options: .usesLineFragmentOrigin,
            attributes: textAttributes,
            context: nil
        ).size
        
        // Calculate the position to center the text
        let textPoint = CGPoint(
            x: (self.size.width - textSize.width) / 2,
            y: (self.size.height - textSize.height) / 2
        )
        
        // Define text rectangle
        let rect = CGRect(origin: textPoint, size: textSize)
        
        // Draw text in the rect
        (text as NSString).draw(in: rect, withAttributes: textAttributes)
        
        // Get the new image
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    func addImageToBottomRightCorner(overlayImage: UIImage) -> UIImage? {
        let mainImageSize = self.size
        let overlayImageSize = overlayImage.size
        
        UIGraphicsBeginImageContextWithOptions(mainImageSize, false, 0.0)
        
        // Draw the main image
        self.draw(in: CGRect(origin: .zero, size: mainImageSize))
        
        // Calculate the position to place the overlay image (bottom right corner)
        let overlayOrigin = CGPoint(
            x: mainImageSize.width - overlayImageSize.width,
            y: mainImageSize.height - overlayImageSize.height
        )
        
        // Draw the overlay image
        overlayImage.draw(in: CGRect(origin: overlayOrigin, size: overlayImageSize))
        
        // Get the resulting image
        let combinedImage = UIGraphicsGetImageFromCurrentImageContext()
        
        UIGraphicsEndImageContext()
        
        return combinedImage
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

/// - Tag: UIViewController
extension UIViewController {
    func showImagePopup(combinedImage: UIImage) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        
        // Create an image view with the image
        let imageView = UIImageView(image: combinedImage)
        imageView.contentMode = .scaleAspectFit
        
        // Set the desired width and height for the image view with padding
        let maxWidth: CGFloat = 270
        let maxHeight: CGFloat = 480
        
        // Calculate the aspect ratio
        let aspectRatio = combinedImage.size.width / combinedImage.size.height
        
        // Determine the width and height based on the aspect ratio
        var imageViewWidth = maxWidth
        var imageViewHeight = maxWidth / aspectRatio
        
        if imageViewHeight > maxHeight {
            imageViewHeight = maxHeight
            imageViewWidth = maxHeight * aspectRatio
        }
        
        // Create a container view for the image view to add constraints
        let containerView = UIView()
        containerView.addSubview(imageView)
        
        // Set up auto layout constraints
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: imageViewWidth),
            imageView.heightAnchor.constraint(equalToConstant: imageViewHeight),
            imageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: imageViewWidth + 20),  // Adding padding
            containerView.heightAnchor.constraint(equalToConstant: imageViewHeight + 20) // Adding padding
        ])
        
        // Add the container view to the alert controller
        alert.view.addSubview(containerView)
        
        // Set up the container view's constraints within the alert view
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            containerView.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 20),
            containerView.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -45)
        ])
        
        // Add an action to dismiss the alert
        alert.addAction(UIAlertAction(title: "Fish on!", style: .default, handler: nil))
        
        // Present the alert controller
        present(alert, animated: true, completion: nil)
    }
    
    func showInputPopup(title: String?, message: String?, placeholders: [String], completion: @escaping ([Double?]) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        // Add text fields to the alert based on the provided placeholders
        for placeholder in placeholders {
            alert.addTextField { textField in
                textField.placeholder = placeholder
                textField.keyboardType = .decimalPad // Set keyboard type to decimal pad for double values
            }
        }
        
        // Add an action to submit the input
        let submitAction = UIAlertAction(title: "Submit", style: .default) { _ in
            let inputs = alert.textFields?.map { textField -> Double? in
                guard let text = textField.text, !text.isEmpty else {
                    return nil
                }
                return Double(text)
            }
            completion(inputs ?? [])
        }
        alert.addAction(submitAction)
        
        // Add a cancel action
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alert.addAction(cancelAction)
        
        // Present the alert controller
        present(alert, animated: true, completion: nil)
    }
}
