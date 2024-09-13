//
//  Visualizations.swift
//  tripletalear
//
//  Created by Wes Wang on 8/20/24.
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

func drawContoursEllipseAndTips(on image: UIImage, contours: [[CGPoint]], closestContour: [CGPoint], ellipse: (center: CGPoint, size: CGSize, rotation: CGFloat), tips: [CGPoint]) -> UIImage? {
    // Create a renderer format with the appropriate scale
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale // Match the input image scale

    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

    let renderedImage = renderer.image { context in
        // Draw the original image
        image.draw(at: .zero)
        
        // Set the contour drawing properties
        context.cgContext.setStrokeColor(UIColor.blue.cgColor)
        context.cgContext.setLineWidth(1.0)
        
        // Draw all contours
        for contour in contours {
            context.cgContext.beginPath()
            for point in contour {
                if point == contour.first {
                    context.cgContext.move(to: point)
                } else {
                    context.cgContext.addLine(to: point)
                }
            }
            context.cgContext.strokePath()
        }
        
        // Set the ellipse drawing properties
        context.cgContext.setStrokeColor(UIColor.red.cgColor)
        context.cgContext.setLineWidth(2.0)
        
        // Save the context state
        context.cgContext.saveGState()
        
        // Move to the ellipse center
        context.cgContext.translateBy(x: ellipse.center.x, y: ellipse.center.y)
        
        // Rotate the context
        context.cgContext.rotate(by: ellipse.rotation * CGFloat.pi / 180)
        
        // Draw the ellipse
        let rect = CGRect(x: -ellipse.size.width, y: -ellipse.size.height, width: 2 * ellipse.size.width, height: 2 * ellipse.size.height)
        context.cgContext.strokeEllipse(in: rect)
        
        // Restore the context state
        context.cgContext.restoreGState()
        
        // Set the tips drawing properties
        context.cgContext.setFillColor(UIColor.green.cgColor)
        
        // Draw the tips
        for tip in tips {
            context.cgContext.fillEllipse(in: CGRect(x: tip.x - 2, y: tip.y - 2, width: 10, height: 10))
        }
    }

    return renderedImage
}

func drawRectanglesOnImage(image: UIImage, boundingBoxes: [CGRect]) -> UIImage {
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    image.draw(at: CGPoint.zero)
    
    let context = UIGraphicsGetCurrentContext()!
    context.setStrokeColor(UIColor.green.cgColor)
    context.setLineWidth(5.0)
    
    for rect in boundingBoxes {
        let transformedRect = CGRect(x: rect.origin.x * image.size.width,
                                     y: (1 - rect.origin.y - rect.size.height) * image.size.height,
                                     width: rect.size.width * image.size.width,
                                     height: rect.size.height * image.size.height)
        context.stroke(transformedRect)
    }
    
    let newImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    
    return newImage
}

func drawBracketsOnImage(image: UIImage, boundingBox: CGRect, bracketLength: CGFloat = 30.0, bracketThickness: CGFloat = 8.0) -> UIImage {
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    image.draw(at: CGPoint.zero)
    
    let context = UIGraphicsGetCurrentContext()!
    context.setStrokeColor(UIColor.green.cgColor)
    context.setLineWidth(bracketThickness)
               
        // Top-left bracket
        context.move(to: CGPoint(x: boundingBox.minX, y: boundingBox.minY + bracketLength))
        context.addLine(to: CGPoint(x: boundingBox.minX, y: boundingBox.minY))
        context.addLine(to: CGPoint(x: boundingBox.minX + bracketLength, y: boundingBox.minY))
        
        // Top-right bracket
        context.move(to: CGPoint(x: boundingBox.maxX - bracketLength, y: boundingBox.minY))
        context.addLine(to: CGPoint(x: boundingBox.maxX, y: boundingBox.minY))
        context.addLine(to: CGPoint(x: boundingBox.maxX, y: boundingBox.minY + bracketLength))
        
        // Bottom-left bracket
        context.move(to: CGPoint(x: boundingBox.minX, y: boundingBox.maxY - bracketLength))
        context.addLine(to: CGPoint(x: boundingBox.minX, y: boundingBox.maxY))
        context.addLine(to: CGPoint(x: boundingBox.minX + bracketLength, y: boundingBox.maxY))
        
        // Bottom-right bracket
        context.move(to: CGPoint(x: boundingBox.maxX - bracketLength, y: boundingBox.maxY))
        context.addLine(to: CGPoint(x: boundingBox.maxX, y: boundingBox.maxY))
        context.addLine(to: CGPoint(x: boundingBox.maxX, y: boundingBox.maxY - bracketLength))
        
        context.strokePath()
    
    
    let newImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    
    return newImage
}

func drawROI(on ciImage: CIImage, portion: CGFloat) -> UIImage? {
    let imageWidth = ciImage.extent.width
    let imageHeight = ciImage.extent.height
    
    // Calculate the dimensions of the ROI
    let roiWidth = imageWidth * portion
    let roiHeight = imageHeight * portion
    
    // Calculate the position to center the ROI
    let roiX = (imageWidth - roiWidth) / 2
    let roiY = (imageHeight - roiHeight) / 2
    
    // Create the CGRect for the ROI
    let roiRect = CGRect(x: roiX, y: roiY, width: roiWidth, height: roiHeight)
    
    // Convert CIImage to UIImage
    let context = CIContext(options: nil)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
        return nil
    }
    let uiImage = UIImage(cgImage: cgImage)
    
    // Begin drawing on the UIImage
    UIGraphicsBeginImageContextWithOptions(uiImage.size, false, uiImage.scale)
    uiImage.draw(at: .zero)
    
    // Draw the ROI rectangle
    let path = UIBezierPath(rect: roiRect)
    UIColor.red.setStroke()  // You can change the color as needed
    path.lineWidth = 2  // You can adjust the line width as needed
    path.stroke()
    
    // Get the resulting image
    let resultImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return resultImage
}

func drawClosestContourAndEllipse(on image: UIImage, closestContour: [CGPoint], ellipse: (center: CGPoint, size: CGSize, rotationInDegrees: CGFloat), tips: [CGPoint]) -> UIImage? {
    // Create a renderer format with the appropriate scale
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale // Match the input image scale

    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

    let renderedImage = renderer.image { context in
        // Draw the original image
        image.draw(at: .zero)
        
        // Set the contour drawing properties for closestContour
        context.cgContext.setStrokeColor(UIColor.blue.cgColor)
        context.cgContext.setLineWidth(1.0)
        
        // Draw only the closestContour border without filling
        context.cgContext.beginPath()
        for (index, point) in closestContour.enumerated() {
            if index == 0 {
                context.cgContext.move(to: point)
            } else {
                context.cgContext.addLine(to: point)
            }
        }
        context.cgContext.addLine(to: closestContour.first!) // Close the path
        
        // Ensure fill mode is disabled
        context.cgContext.drawPath(using: .stroke)  // Explicitly only stroke the path

        // Set the ellipse drawing properties
        context.cgContext.setStrokeColor(UIColor.red.cgColor)
        context.cgContext.setLineWidth(2.0)
        
        // Save the context state
        context.cgContext.saveGState()
        
        // Move to the ellipse center
        context.cgContext.translateBy(x: ellipse.center.x, y: ellipse.center.y)
        
        // Rotate the context for the ellipse
        context.cgContext.rotate(by: ellipse.rotationInDegrees * CGFloat.pi / 180)
        
        // Draw the ellipse
        let rect = CGRect(x: -ellipse.size.width, y: -ellipse.size.height, width: 2 * ellipse.size.width, height: 2 * ellipse.size.height)
        context.cgContext.strokeEllipse(in: rect)
        
        // Restore the context state
        context.cgContext.restoreGState()
        
        // Set the tips drawing properties
        context.cgContext.setFillColor(UIColor.green.cgColor)
        
        // Draw the tips
        for tip in tips {
            context.cgContext.fillEllipse(in: CGRect(x: tip.x - 2, y: tip.y - 2, width: 10, height: 10))
        }
    }

    return renderedImage
}
