//
//  MainFlow.swift
//  tripletalear
//
//  Created by Wes Wang on 8/19/24.
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

func findEllipseVertices(from image: UIImage, for portion: CGFloat, debug: Bool = false) -> [CGPoint]? {
    // get foreground mask
    guard let maskImage = generateMaskImage(from: image, for: portion) else { return nil }
    
    // turn into gray scale pixel data
    let context = CIContext()
    guard let cgImage = context.createCGImage(maskImage, from: maskImage.extent) else { return nil }
    guard let pixelData = convertCGImageToGrayscalePixelData(cgImage) else { return nil }

    // find all contours
    let width = cgImage.width
    let height = cgImage.height
    let contours = extractContours(from: pixelData, width: width, height: height)
    
    // find center contour
    guard let closestContour = findContourClosestToCenter(contours: contours, imageWidth: width, imageHeight: height) else { return nil }
    
    // fit ellipse
    guard let ellipse = fitEllipseMinimax(to: closestContour) else { return nil }
    
    // find ellipse tips to use for measurements
    let size = CGSize(width: ellipse.size.width, height: ellipse.size.height)
    let tips = calculateEllipseTips(center: ellipse.center, size: size, rotation: ellipse.rotationInDegrees)
    
    // for debug display only
    if debug {
        let maskUiImage = maskImage.toUIImage()!
        let resultImage = drawContoursEllipseAndTips(on: maskUiImage, contours: contours, closestContour: closestContour, ellipse: (center: ellipse.center, size: size, rotation: ellipse.rotationInDegrees), tips: tips)
        
        saveImageToGallery(resultImage!)
    }
    
    let tipsNormalized = tips.map { point in
        CGPoint(x: point.x / CGFloat(width), y: (CGFloat(height) - point.y) / CGFloat(height))
    }
    
    return tipsNormalized

}

func buildRealWorldVerticesAnchors(_ currentView: ARSCNView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> ([ARAnchor], ARAnchor, ARAnchor, [ARAnchor]) {
    var verticesAnchors = getVertices(currentView, normalizedVertices, capturedImageSize)
    
    let centroidAboveAnchor = getVerticesCenter(currentView, normalizedVertices, capturedImageSize)

    let corners = calculateRectangleCorners(normalizedVertices, 0.0, 0.7) // first one is tall, second is wide
    let cornerAnchors = getAngledCorners(currentView, corners, capturedImageSize)
    let centroidBelowAnchor = createCentroidAnchor(from: cornerAnchors)

    let distanceToFish = calculateDistanceToObject(centroidAboveAnchor!)
    let distanceToGround = calculateDistanceToObject(centroidBelowAnchor!)
    let scalingFactor = distanceToFish / distanceToGround * 1.1
    
    verticesAnchors = stretchVertices(verticesAnchors, verticalScaleFactor: scalingFactor, horizontalScaleFactor: scalingFactor)
    
    
    return (verticesAnchors, centroidAboveAnchor!, centroidBelowAnchor!, cornerAnchors)
}
