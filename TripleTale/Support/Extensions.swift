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
}
