//
//  Visualizations.swift
//  TripleTale
//
//  Created by Wes Wang on 8/5/24.
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

func generateResultImage(_ inputImage: UIImage, _ inputBoundingBox: CGRect? = nil, _ widthInInches: Measurement<UnitLength>, _ lengthInInches: Measurement<UnitLength>, _ heightInInches: Measurement<UnitLength>, _ circumferenceInInches: Measurement<UnitLength>, _ weightInLb: Measurement<UnitMass>, _ fishName: String) -> UIImage? {
    let boundingBox = inputBoundingBox ?? CGRect(origin: .zero, size: inputImage.size)

    let formattedLength = String(format: "%.2f", lengthInInches.value)
    let formattedWeight = String(format: "%.2f", weightInLb.value)
    let formattedWidth = String(format: "%.2f", widthInInches.value)
    let formattedHeight = String(format: "%.2f", heightInInches.value)
    let formattedCircumference = String(format: "%.2f", circumferenceInInches.value)

//        self.anchorLabels[midpointAnchors[4].identifier] = "\(formattedWeight) lb, \(formattedLength) in "
    let imageWithBox = drawBracketsOnImage(image: inputImage, boundingBoxes: [boundingBox])

    let weightTextImage = imageWithBox.imageWithCenteredText("\(fishName) \n \(formattedWeight) lb", fontSize: 180, textColor: UIColor.white)
    
    let point = CGPoint(x: 10, y: weightTextImage!.size.height - 80)

    let measurementTextImage = weightTextImage?.imageWithText("L \(formattedLength) in x W \(formattedWidth) in x H \(formattedHeight) in, C \(formattedCircumference) in", atPoint: point, fontSize: 40, textColor: UIColor.white)
    

    let overlayImage = UIImage(named: "shimano_logo")!
    let combinedImage = measurementTextImage!.addImageToBottomRightCorner(overlayImage: overlayImage)
    
    saveImageToGallery(combinedImage!)
    saveImageToGallery(inputImage)

    return combinedImage!
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

func drawBracketsOnImage(image: UIImage, boundingBoxes: [CGRect], bracketLength: CGFloat = 50.0, bracketThickness: CGFloat = 10.0) -> UIImage {
    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    image.draw(at: CGPoint.zero)
    
    let context = UIGraphicsGetCurrentContext()!
    context.setStrokeColor(UIColor.white.cgColor)
    context.setLineWidth(bracketThickness)
    
    for rect in boundingBoxes {
        let transformedRect = CGRect(x: rect.origin.x * image.size.width,
                                     y: (1 - rect.origin.y - rect.size.height) * image.size.height,
                                     width: rect.size.width * image.size.width,
                                     height: rect.size.height * image.size.height)
        
        // Top-left bracket
        context.move(to: CGPoint(x: transformedRect.minX, y: transformedRect.minY + bracketLength))
        context.addLine(to: CGPoint(x: transformedRect.minX, y: transformedRect.minY))
        context.addLine(to: CGPoint(x: transformedRect.minX + bracketLength, y: transformedRect.minY))
        
        // Top-right bracket
        context.move(to: CGPoint(x: transformedRect.maxX - bracketLength, y: transformedRect.minY))
        context.addLine(to: CGPoint(x: transformedRect.maxX, y: transformedRect.minY))
        context.addLine(to: CGPoint(x: transformedRect.maxX, y: transformedRect.minY + bracketLength))
        
        // Bottom-left bracket
        context.move(to: CGPoint(x: transformedRect.minX, y: transformedRect.maxY - bracketLength))
        context.addLine(to: CGPoint(x: transformedRect.minX, y: transformedRect.maxY))
        context.addLine(to: CGPoint(x: transformedRect.minX + bracketLength, y: transformedRect.maxY))
        
        // Bottom-right bracket
        context.move(to: CGPoint(x: transformedRect.maxX - bracketLength, y: transformedRect.maxY))
        context.addLine(to: CGPoint(x: transformedRect.maxX, y: transformedRect.maxY))
        context.addLine(to: CGPoint(x: transformedRect.maxX, y: transformedRect.maxY - bracketLength))
        
        context.strokePath()
    }
    
    let newImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    
    return newImage
}

func drawContoursEllipseAndTips(on image: UIImage, contours: [[CGPoint]], closestContour: [CGPoint], ellipse: (center: CGPoint, size: CGSize, rotation: CGFloat), tips: [CGPoint]) -> UIImage? {
    // Create a renderer format with the appropriate scale
    let format = UIGraphicsImageRendererFormat()
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    
    // Print the scale of the renderer format
    print("UIGraphicsImageRenderer scale: \(format.scale)")
    
    
    let renderedImage = renderer.image { context in
        // Print the scale of the context
        let contextScale = context.currentImage.scale
        print("Context scale: \(contextScale)")
        
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

func drawEllipseAndPoints(on image: UIImage, points: [CGPoint], ellipse: (center: CGPoint, size: CGSize, rotation: CGFloat)) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: image.size)
    let renderedImage = renderer.image { context in
        // Draw the original image
        image.draw(at: .zero)
        
        // Set the points drawing properties
        context.cgContext.setStrokeColor(UIColor.blue.cgColor)
        context.cgContext.setFillColor(UIColor.blue.cgColor)
        context.cgContext.setLineWidth(2.0)
        
        // Draw the points
        for point in points {
            let rect = CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
            context.cgContext.fillEllipse(in: rect)
        }
        
        // Set the ellipse drawing properties
        context.cgContext.setStrokeColor(UIColor.red.cgColor)
        context.cgContext.setLineWidth(2.0)
        
        // Draw the ellipse
        context.cgContext.saveGState()
        context.cgContext.translateBy(x: ellipse.center.x, y: ellipse.center.y)
        context.cgContext.rotate(by: ellipse.rotation)
        let ellipseRect = CGRect(x: -ellipse.size.width, y: -ellipse.size.height, width: 2 * ellipse.size.width, height: 2 * ellipse.size.height)
        context.cgContext.strokeEllipse(in: ellipseRect)
        context.cgContext.restoreGState()
    }
    
    return renderedImage
}
