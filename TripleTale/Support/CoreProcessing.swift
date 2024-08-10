//
//  CoreProcessing.swift
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
import Accelerate

func findEllipseVertices(from image: UIImage, for portion: CGFloat) -> [CGPoint]? {
    guard let ciImage = CIImage(image: image) else { return nil }
    if let maskImage = generateMaskImage(from: ciImage, for: portion) {
//        let outputImage = applyMask(maskImage, to: ciImage)
        
        // Create a CIContext
        let context = CIContext()

        // Create a CGImage from the CIImage
        if let cgImage = context.createCGImage(maskImage, from: maskImage.extent) {
            // Convert the CGImage to a UIImage
            let maskUiImage = UIImage(cgImage: cgImage)
            
            if let pixelData = convertCGImageToGrayscalePixelData(cgImage) {
                    let width = cgImage.width
                    let height = cgImage.height
                    let contours = extractContours(from: pixelData, width: width, height: height)
                    if let closestContour = findContourClosestToCenter(contours: contours, imageWidth: width, imageHeight: height) {
//                        if let ellipse = fitEllipse(to: closestContour) {
                        if let ellipse = fitEllipseMinimax(to: closestContour) {
                            let size = CGSize(width: ellipse.size.width, height: ellipse.size.height)

//                            let ellipseTest = fitEllipseMinimax(to: closestContour)
//                            
//                            // Printing the values
//                            print("Center: (\(ellipse.center.x), \(ellipse.center.y))")
//                            print("Semi-major axis length (scaled width): \(ellipse.size.width)")
//                            print("Semi-minor axis length (scaled height): \(ellipse.size.height)")
//                            print("Rotation Angle (degrees): \(ellipse.rotationInDegrees)")
//                            
//                            // Printing the values
//                            print("Center: (\(ellipseTest!.center.x), \(ellipseTest!.center.y))")
//                            print("Semi-major axis length (scaled width): \(ellipseTest!.size.width)")
//                            print("Semi-minor axis length (scaled height): \(ellipseTest!.size.height)")
//                            print("Rotation Angle (degrees): \(ellipseTest!.rotationInDegrees)")
                            
                            
                            let tips = calculateEllipseTips(center: ellipse.center, size: size, rotation: ellipse.rotationInDegrees)
                            
                            let tipsNormalized = tips.map { point in
                                CGPoint(x: point.x / CGFloat(width), y: (CGFloat(height) - point.y) / CGFloat(height))
                            }

                            
                            if let resultImage = drawContoursEllipseAndTips(on: maskUiImage, contours: contours, closestContour: closestContour, ellipse: (center: ellipse.center, size: size, rotation: ellipse.rotationInDegrees), tips: tips) {
                                // Use the resultImage, e.g., display it in an UIImageView or save it
                                saveImageToGallery(resultImage)
                            }
                            
                            
                            return tipsNormalized

                        }
                    }
                }
        }
        
    }
    return nil
}

func processImage(_ inputImage: UIImage, _ currentView: ARSKView, _ isForward: Bool, _ fishName: String, _ portion: CGFloat ) -> UIImage? {
    // isolate fish through foreground vs background separation
    if let fishBoundingBox = isolateFish(from: inputImage, for: portion) {
        // define anchors for calculations
        let (centroidAnchor,midpointAnchors,nudgeRate) =  findAnchors(fishBoundingBox, inputImage.size, currentView, isForward)
        
        if centroidAnchor != nil {
            // measure in real world units
            let (width, length, height, circumference) = measureDimensions(midpointAnchors, centroidAnchor!, fishBoundingBox, inputImage.size, currentView, isForward, scale: (1.0 + nudgeRate))
            
            // calculate weight
            let (weightInLb, widthInInches, lengthInInches, heightInInches, circumferenceInInches) = calculateWeight(width, length, height, circumference)
            
            // add text/logo and save result to gallery
            let combinedImage = generateResultImage(inputImage, fishBoundingBox, widthInInches, lengthInInches, heightInInches, circumferenceInInches, weightInLb, fishName)
            
            // show popup to user
            return combinedImage
        }
    }
    return nil
}
