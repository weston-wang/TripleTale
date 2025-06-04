//
//  UIImage+Drawing.swift
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

extension UIImage {
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
    
    func imageWithHorizontalCenteredText(_ text: String, fontSize: CGFloat, textColor: UIColor, font: UIFont? = nil, yPosition: CGFloat) -> UIImage? {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let textFont = font ?? UIFont.boldSystemFont(ofSize: fontSize)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
            .strokeColor: UIColor.black,
            .strokeWidth: -3
        ]
        
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        defer { UIGraphicsEndImageContext() }
        
        self.draw(in: CGRect(origin: CGPoint.zero, size: self.size))
        
        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: self.size.width, height: self.size.height),
            options: .usesLineFragmentOrigin,
            attributes: textAttributes,
            context: nil
        ).size
        
        let textPoint = CGPoint(
            x: (self.size.width - textSize.width) / 2,
            y: yPosition
        )
        
        let rect = CGRect(origin: textPoint, size: textSize)
        (text as NSString).draw(in: rect, withAttributes: textAttributes)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    func imageWithCenteredText(_ text: String, fontSize: CGFloat, textColor: UIColor, font: UIFont? = nil, verticalOffset: CGFloat? = nil) -> UIImage? {
        // Create a paragraph style with center alignment
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        // Create a shadow for the text (optional)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black
        shadow.shadowOffset = CGSize(width: 2, height: 2)
        shadow.shadowBlurRadius = 1
        
        let textFont = font ?? UIFont.boldSystemFont(ofSize: fontSize)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
            .strokeColor: UIColor.black, // Border color
            .strokeWidth: -3 // Negative value keeps text visible inside the border
            //            .shadow: shadow,
            
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
            y: ((self.size.height - textSize.height) / 2) + (verticalOffset ?? 0)
        )
        
        // Define text rectangle
        let rect = CGRect(origin: textPoint, size: textSize)
        
        // Draw text in the rect
        (text as NSString).draw(in: rect, withAttributes: textAttributes)
        
        // Get the new image
        return UIGraphicsGetImageFromCurrentImageContext()
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
    
    /// Draws the points represented by VNPoints on the image.
    /// - Parameters:
    ///   - points: A dictionary of joint names and their VNPoint positions.
    /// - Returns: A new UIImage with the points drawn.
    func drawVNPoints(_ points: [String: VNPoint]) -> UIImage? {
        
        // Begin a new image context
        UIGraphicsBeginImageContext(self.size)
        
        // Draw the original image in the background
        self.draw(at: CGPoint.zero)
        
        // Set up the drawing context
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.setLineWidth(2.0)
        context.setStrokeColor(UIColor.red.cgColor)
        context.setFillColor(UIColor.green.cgColor)
        
        // Loop through each VNPoint and draw it
        for (_, vnPoint) in points {
            // Convert the normalized VNPoint.location to CGPoint in image coordinates
            let pointInImage = convertNormalizedPointToCGPoint(vnPoint.location, imageSize: self.size)
            
            // Draw a small circle at the point
            let circleRadius: CGFloat = 16.0
            context.fillEllipse(in: CGRect(x: pointInImage.x - circleRadius / 2, y: pointInImage.y - circleRadius / 2, width: circleRadius, height: circleRadius))
        }
        
        // Generate a new image with the drawing
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
    
    func drawVNPoint(_ vnPoint: VNPoint) -> UIImage? {
        
        // Begin a new image context
        UIGraphicsBeginImageContext(self.size)
        
        // Draw the original image in the background
        self.draw(at: CGPoint.zero)
        
        // Set up the drawing context
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.setLineWidth(2.0)
        context.setStrokeColor(UIColor.red.cgColor)
        context.setFillColor(UIColor.green.cgColor)
        
        // Convert the normalized VNPoint.location to CGPoint in image coordinates
        let pointInImage = convertNormalizedPointToCGPoint(vnPoint.location, imageSize: self.size)
        
        // Draw a small circle at the point
        let circleRadius: CGFloat = 16.0
        context.fillEllipse(in: CGRect(x: pointInImage.x - circleRadius / 2, y: pointInImage.y - circleRadius / 2, width: circleRadius, height: circleRadius))
        
        
        // Generate a new image with the drawing
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
