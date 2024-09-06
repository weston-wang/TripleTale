//
//  Extensions.swift
//  tripletalear
//
//  Created by Wes Wang on 8/18/24.
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
    
    func imageWithText(_ text: String, atPoint point: CGPoint, fontSize: CGFloat, textColor: UIColor) -> UIImage? {
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor,
            .backgroundColor: UIColor.black
        ]
        
        // Start drawing image context
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
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
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
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
        
        UIGraphicsBeginImageContextWithOptions(mainImageSize, false, self.scale)
        
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
    
    func drawBoundingBox(_ boundingBox: CGRect, color: UIColor = .green, lineWidth: CGFloat = 2.0) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        // Draw the original image
        self.draw(at: .zero)
        
        // Set the properties for the bounding box
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        
        // Draw the bounding box
        context.stroke(boundingBox)
        
        // Get the new image with the bounding box drawn on it
        let imageWithBoundingBox = UIGraphicsGetImageFromCurrentImageContext()
        
        // Clean up
        UIGraphicsEndImageContext()
        
        return imageWithBoundingBox
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
    
    // Function to draw a dot at the given (x, y) coordinate
    func drawDot(at point: CGPoint, color: UIColor = .red, radius: CGFloat = 5.0) -> UIImage? {
        // Create a renderer at the size of the existing image
        let renderer = UIGraphicsImageRenderer(size: self.size)
        
        // Render a new image with the dot
        let newImage = renderer.image { context in
            // Draw the original image first
            self.draw(at: .zero)
            
            // Set the color for the dot
            context.cgContext.setFillColor(color.cgColor)
            
            // Draw a filled circle (dot) at the given point
            let dotRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.cgContext.fillEllipse(in: dotRect)
        }
        
        return newImage
    }

    /// Draws the arm points and 3D angles (pitch, yaw, roll) on the image.
    /// - Parameters:
    ///   - leftShoulder: The position of the left shoulder.
    ///   - leftElbow: The position of the left elbow.
    ///   - leftWrist: The position of the left wrist.
    ///   - rightShoulder: The position of the right shoulder.
    ///   - rightElbow: The position of the right elbow.
    ///   - rightWrist: The position of the right wrist.
    ///   - leftElbowAngle: The simd_float3 for the left elbow (pitch, yaw, roll).
    ///   - rightElbowAngle: The simd_float3 for the right elbow (pitch, yaw, roll).
    /// - Returns: A new UIImage with the points, connections, and angles drawn.
    func drawArmPose(leftShoulder: simd_float3, leftElbow: simd_float3, leftWrist: simd_float3,
                     rightShoulder: simd_float3, rightElbow: simd_float3, rightWrist: simd_float3,
                     leftElbowAngle: simd_float3, rightElbowAngle: simd_float3) -> UIImage? {

        // Begin a new image context
        UIGraphicsBeginImageContext(self.size)

        // Draw the original image in the background
        self.draw(at: CGPoint.zero)

        // Set up the drawing context
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.setLineWidth(4.0)
        context.setStrokeColor(UIColor.red.cgColor)
        context.setFillColor(UIColor.blue.cgColor)

        // Helper to convert 3D points to 2D points (for this example, we only use x and y)
        func convertToCGPoint(_ point: simd_float3) -> CGPoint {
            // Assuming x and y are normalized between -1 and 1
            let x = (CGFloat(point.x) + 1.0) * self.size.width / 2.0
            let y = (1.0 - CGFloat(point.y)) * self.size.height / 2.0
            return CGPoint(x: x, y: y)
        }

        // Convert 3D points to 2D points
        let leftShoulder2D = convertToCGPoint(leftShoulder)
        let leftElbow2D = convertToCGPoint(leftElbow)
        let leftWrist2D = convertToCGPoint(leftWrist)

        let rightShoulder2D = convertToCGPoint(rightShoulder)
        let rightElbow2D = convertToCGPoint(rightElbow)
        let rightWrist2D = convertToCGPoint(rightWrist)

        // Draw lines for the left arm
        context.move(to: leftShoulder2D)
        context.addLine(to: leftElbow2D)
        context.addLine(to: leftWrist2D)
        context.strokePath()

        // Draw lines for the right arm
        context.move(to: rightShoulder2D)
        context.addLine(to: rightElbow2D)
        context.addLine(to: rightWrist2D)
        context.strokePath()

        // Draw circles at the points
        let circleRadius: CGFloat = 8.0
        [leftShoulder2D, leftElbow2D, leftWrist2D, rightShoulder2D, rightElbow2D, rightWrist2D].forEach { point in
            context.fillEllipse(in: CGRect(x: point.x - circleRadius / 2, y: point.y - circleRadius / 2, width: circleRadius, height: circleRadius))
        }

        // Draw the 3D angles (pitch, yaw, roll) near the elbows
        drawText("Pitch: \(Int(leftElbowAngle.x))°, Yaw: \(Int(leftElbowAngle.y))°, Roll: \(Int(leftElbowAngle.z))°", at: leftElbow2D, in: context)
        drawText("Pitch: \(Int(rightElbowAngle.x))°, Yaw: \(Int(rightElbowAngle.y))°, Roll: \(Int(rightElbowAngle.z))°", at: rightElbow2D, in: context)

        // Generate a new image with the drawing
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }
    
    /// Draws all detected body parts on the image.
    /// - Parameter bodyPoints: A dictionary of body parts and their 2D positions.
    /// - Returns: A new UIImage with the body parts drawn.
    func drawBodyPoints(_ bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> UIImage? {
        
        // Begin a new image context
        UIGraphicsBeginImageContext(self.size)
        
        // Draw the original image in the background
        self.draw(at: CGPoint.zero)
        
        // Set up the drawing context
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.setLineWidth(2.0)
        context.setStrokeColor(UIColor.red.cgColor)
        context.setFillColor(UIColor.blue.cgColor)
        
        // Loop through each body point and draw it on the image
        for (_, point) in bodyPoints {
            let circleRadius: CGFloat = 5.0
            let circleRect = CGRect(x: point.x - circleRadius, y: point.y - circleRadius, width: circleRadius * 2, height: circleRadius * 2)
            context.fillEllipse(in: circleRect)
        }
        
        // Generate the new image with the drawn points
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
    
   func drawArmsWithElbowAngles(leftShoulder: CGPoint, leftElbow: CGPoint, leftWrist: CGPoint, leftAngle: CGFloat,
                                rightShoulder: CGPoint, rightElbow: CGPoint, rightWrist: CGPoint, rightAngle: CGFloat) -> UIImage? {
       
       // Begin a graphics context with the image
       UIGraphicsBeginImageContext(self.size)
       self.draw(at: CGPoint.zero)
       
       guard let context = UIGraphicsGetCurrentContext() else {
           return nil
       }
       
       context.setLineWidth(5.0)
       context.setStrokeColor(UIColor.red.cgColor)
       
       // Draw the left arm
       context.move(to: leftShoulder)
       context.addLine(to: leftElbow)
       context.addLine(to: leftWrist)
       context.strokePath()
       
       // Draw the right arm
       context.move(to: rightShoulder)
       context.addLine(to: rightElbow)
       context.addLine(to: rightWrist)
       context.strokePath()
       
       // Draw the elbow angles as text
       drawText("Left Elbow: \(Int(leftAngle))°", at: leftElbow, in: context)
       drawText("Right Elbow: \(Int(rightAngle))°", at: rightElbow, in: context)
       
       // Generate a new image with the drawings
       let newImage = UIGraphicsGetImageFromCurrentImageContext()
       UIGraphicsEndImageContext()
       
       return newImage
   }
   
   private func drawText(_ text: String, at point: CGPoint, in context: CGContext) {
       let attributes: [NSAttributedString.Key: Any] = [
           .font: UIFont.systemFont(ofSize: 16),
           .foregroundColor: UIColor.blue
       ]
       
       let textRect = CGRect(x: point.x + 10, y: point.y - 10, width: 100, height: 20)
       text.draw(in: textRect, withAttributes: attributes)
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

extension CIImage {
    func toUIImage() -> UIImage? {
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(self, from: self.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}
