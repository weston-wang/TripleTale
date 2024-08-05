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
