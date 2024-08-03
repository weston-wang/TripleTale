//
//  ImageProcessing.swift
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
import Accelerate

// MARK: - Image manipulations

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

func cropImage(_ image: UIImage, withNormalizedRect normalizedRect: CGRect) -> UIImage? {
    // Calculate the actual rect based on image size
    let rect = CGRect(x: normalizedRect.origin.x * image.size.width,
        y: (1 - normalizedRect.origin.y - normalizedRect.size.height) * image.size.height,
        width: normalizedRect.size.width * image.size.width,
        height: normalizedRect.size.height * image.size.height)
    
    // Convert UIImage to CGImage to work with Core Graphics
    guard let cgImage = image.cgImage else { return nil }
    
    // Cropping the image with rect
    guard let croppedCgImage = cgImage.cropping(to: rect) else { return nil }
    
    // Convert cropped CGImage back to UIImage
    return UIImage(cgImage: croppedCgImage, scale: image.scale, orientation: image.imageOrientation)
}

func findEllipseVertices(from image: UIImage) -> [CGPoint]? {
    guard let ciImage = CIImage(image: image) else { return nil }
    if let maskImage = generateMaskImage(from: ciImage) {
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
                        if let ellipse = fitEllipse(to: closestContour, imageWidth: width, imageHeight: height) {
                            let size = CGSize(width: ellipse.size.width*CGFloat(width)/4.0, height: ellipse.size.height*CGFloat(height)/4.0)
                            
                            let tips = calculateEllipseTips(center: ellipse.center, size: size, rotation: ellipse.rotationInDegrees)
                            
                            let tipsNormalized = tips.map { point in
                                CGPoint(x: point.x / CGFloat(width), y: point.y / CGFloat(height))
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

func isolateFish(from image: UIImage) -> CGRect? {
    guard let ciImage = CIImage(image: image) else { return nil }
    if let maskImage = generateMaskImage(from: ciImage) {
//        let outputImage = applyMask(maskImage, to: ciImage)
        
        // Create a CIContext
        let context = CIContext()

        // Create a CGImage from the CIImage
        if let cgImage = context.createCGImage(maskImage, from: maskImage.extent) {
            // Convert the CGImage to a UIImage
            let maskUiImage = UIImage(cgImage: cgImage)
            
//            let boundingBox = boundingBoxForWhiteArea(in: maskUiImage)
            let boundingBox = boundingBoxForCenteredObject(in: maskUiImage)
            return boundingBox

        }
        
    }
    return nil
}

func applyMask(_ mask: CIImage?, to image: CIImage) -> UIImage? {
    guard let mask = mask else { return nil }
    let filter = CIFilter(name: "CIBlendWithMask")
    filter?.setValue(image, forKey: kCIInputImageKey)
    filter?.setValue(mask, forKey: kCIInputMaskImageKey)
    filter?.setValue(CIImage(color: .clear).cropped(to: image.extent), forKey: kCIInputBackgroundImageKey)
    
    let context = CIContext()
    if let outputImage = filter?.outputImage, let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
        return UIImage(cgImage: cgImage)
    }
    return nil
}

func generateMaskImage(from ciImage: CIImage) -> CIImage? {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    
    do {
        try handler.perform([request])
        if let result = request.results?.first {
            let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)

            return CIImage(cvPixelBuffer: maskPixelBuffer)
        }
    } catch {
        print(error.localizedDescription)
    }
    return nil
}

// MARK: - Bounding box manipulations

func reversePerspectiveEffectOnBoundingBox(boundingBox: CGRect, distanceToPhone: Float, totalDistance: Float) -> CGRect {
    // Calculate the inverse scaling factor for dimensions
    let scalingFactor = distanceToPhone / totalDistance

    // Reverse the bounding box dimensions
    let correctedWidth = boundingBox.width * CGFloat(scalingFactor)
    let correctedHeight = boundingBox.height * CGFloat(scalingFactor)
    
    // scaling factor is less than 1, so this
    let shiftX = (correctedWidth - boundingBox.width) / 2
    let shiftY = (correctedHeight - boundingBox.height) / 2

    // Reverse the bounding box position
    let correctedX = boundingBox.origin.x - shiftX
    let correctedY = boundingBox.origin.y - shiftY
    
    // Return the original bounding box
    return CGRect(x: correctedX, y: correctedY, width: correctedWidth, height: correctedHeight)
}

func calculateBoundingBox(from maskImage: CIImage) -> CGRect? {
    let context = CIContext()
    guard let cgImage = context.createCGImage(maskImage, from: maskImage.extent) else { return nil }

    let width = cgImage.width
    let height = cgImage.height
    guard let data = cgImage.dataProvider?.data else { return nil }
    let pixelData = CFDataGetBytePtr(data)

    var minX = width
    var minY = height
    var maxX: Int = 0
    var maxY: Int = 0

    for y in 0..<height {
        for x in 0..<width {
            let pixelIndex = y * width + x
            let luma = pixelData![pixelIndex]
            if luma > 0 { // Check if the pixel is part of the foreground
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }

    if minX >= maxX || minY >= maxY { return nil }

    let normalizedBoundingBox = CGRect(
        x: CGFloat(minX) / CGFloat(width),
        y: CGFloat(minY) / CGFloat(height),
        width: CGFloat(maxX - minX) / CGFloat(width),
        height: CGFloat(maxY - minY) / CGFloat(height)
    )

    return normalizedBoundingBox
}

func boundingBoxForCenteredObject(in image: UIImage) -> CGRect? {
    guard let cgImage = image.cgImage else {
        return nil
    }
    
    let width = cgImage.width
    let height = cgImage.height

    // Create a bitmap context for the image
    let colorSpace = CGColorSpaceCreateDeviceGray()
    var pixelData = [UInt8](repeating: 0, count: width * height)
    let context = CGContext(data: &pixelData,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: width,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)

    context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var visited = Array(repeating: false, count: width * height)
    var components: [(minX: Int, minY: Int, maxX: Int, maxY: Int)] = []

    let directions = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    func bfs(startX: Int, startY: Int) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        var queue = [(x: Int, y: Int)]()
        queue.append((startX, startY))
        visited[startY * width + startX] = true

        var minX = startX
        var minY = startY
        var maxX = startX
        var maxY = startY

        var queueIndex = 0
        while queueIndex < queue.count {
            let (x, y) = queue[queueIndex]
            queueIndex += 1

            for (dx, dy) in directions {
                let nx = x + dx
                let ny = y + dy
                let index = ny * width + nx

                if nx >= 0 && nx < width && ny >= 0 && ny < height && !visited[index] && pixelData[index] == 255 {
                    visited[index] = true
                    queue.append((nx, ny))
                    if nx < minX { minX = nx }
                    if ny < minY { minY = ny }
                    if nx > maxX { maxX = nx }
                    if ny > maxY { maxY = ny }
                }
            }
        }

        return (minX, minY, maxX, maxY)
    }

    // Identify all white pixel groups and their bounding boxes
    for y in 0..<height {
        for x in 0..<width {
            let index = y * width + x
            if pixelData[index] == 255 && !visited[index] {
                let boundingBox = bfs(startX: x, startY: y)
                components.append(boundingBox)
            }
        }
    }

    // Find the component closest to the center
    let centerX = width / 2
    let centerY = height / 2
    var closestComponent: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
    var minDistance = Int.max

    for component in components {
        let componentCenterX = (component.minX + component.maxX) / 2
        let componentCenterY = (component.minY + component.maxY) / 2
        let distance = abs(componentCenterX - centerX) + abs(componentCenterY - centerY)

        if distance < minDistance {
            minDistance = distance
            closestComponent = component
        }
    }

    // Normalize the bounding box coordinates
    if let bounds = closestComponent {
        let normalizedBoundingBox = CGRect(x: CGFloat(bounds.minX) / CGFloat(width),
                                           y: CGFloat(bounds.minY) / CGFloat(height),
                                           width: CGFloat(bounds.maxX - bounds.minX + 1) / CGFloat(width),
                                           height: CGFloat(bounds.maxY - bounds.minY + 1) / CGFloat(height))
        return normalizedBoundingBox
    }

    return nil
}

func nudgeBoundingBox(_ boundingBox: CGRect, _ nudgePercent: Float) -> CGRect {
    var newBoundingBox: CGRect = boundingBox
    
    newBoundingBox.size.width = boundingBox.size.width * CGFloat((1.0 - nudgePercent))
    newBoundingBox.size.height = boundingBox.size.height * CGFloat((1.0 - nudgePercent))
    
    newBoundingBox.origin.x = boundingBox.origin.x + boundingBox.size.width * CGFloat(nudgePercent/2.0)
    newBoundingBox.origin.y = boundingBox.origin.y + boundingBox.size.height * CGFloat(nudgePercent/2.0)

    return newBoundingBox
}

func processImage(_ inputImage: UIImage, _ currentView: ARSKView, _ isForward: Bool, _ fishName: String ) -> UIImage? {
    let points = findEllipseVertices(from: inputImage)
    print(points)
    
    // isolate fish through foreground vs background separation
    if let fishBoundingBox = isolateFish(from: inputImage) {
        // define anchors for calculations
        let (centroidAnchor,midpointAnchors,nudgeRate) =  findAnchors(fishBoundingBox, inputImage.size, currentView, isForward)
        
        if centroidAnchor != nil {
            // measure in real world units
            let (width, length, height, circumference) = measureDimensions(midpointAnchors, centroidAnchor!, fishBoundingBox, inputImage.size, currentView, isForward, scale: (1.0 + nudgeRate))
            
            // calculate weight
            let (weightInLb, widthInInches, lengthInInches, heightInInches, circumferenceInInches) = calculateWeight(width, length, height, circumference)
            
            // add text/logo and save result to gallery
            let combinedImage = processResult(inputImage, fishBoundingBox, widthInInches, lengthInInches, heightInInches, circumferenceInInches, weightInLb, fishName)
            
            // show popup to user
            return combinedImage
        }
    }
    return nil
}


func convertCGImageToGrayscalePixelData(_ cgImage: CGImage) -> [UInt8]? {
    let width = cgImage.width
    let height = cgImage.height
    let bitsPerComponent = 8
    let bytesPerPixel = 1
    let bytesPerRow = width * bytesPerPixel

    var pixelData = [UInt8](repeating: 0, count: width * height)
    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard let context = CGContext(data: &pixelData,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: bitsPerComponent,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
        return nil
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixelData
}

func extractContours(from pixelData: [UInt8], width: Int, height: Int) -> [[CGPoint]] {
    var contours = [[CGPoint]]()
    var visited = Array(repeating: Array(repeating: false, count: width), count: height)
    let directions = [(-1, 0), (1, 0), (0, -1), (0, 1)] // 4-connected directions

    func bfs(startX: Int, startY: Int) -> [CGPoint] {
        var queue = [(x: Int, y: Int)]()
        queue.append((startX, startY))
        visited[startY][startX] = true
        var contour = [CGPoint]()
        
        while !queue.isEmpty {
            let (x, y) = queue.removeFirst()
            contour.append(CGPoint(x: x, y: y))
            
            for (dx, dy) in directions {
                let newX = x + dx
                let newY = y + dy
                if newX >= 0, newX < width, newY >= 0, newY < height, !visited[newY][newX], pixelData[newY * width + newX] == 255 {
                    queue.append((newX, newY))
                    visited[newY][newX] = true
                }
            }
        }
        
        return contour
    }

    for y in 0..<height {
        for x in 0..<width {
            if pixelData[y * width + x] == 255 && !visited[y][x] {
                let contour = bfs(startX: x, startY: y)
                if !contour.isEmpty {
                    contours.append(contour)
                }
            }
        }
    }

    return contours
}

func findContourClosestToCenter(contours: [[CGPoint]], imageWidth: Int, imageHeight: Int) -> [CGPoint]? {
    let center = CGPoint(x: imageWidth / 2, y: imageHeight / 2)
    var minDistance = CGFloat.greatestFiniteMagnitude
    var closestContour: [CGPoint]?

    for contour in contours {
        let contourCenter = contour.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let avgContourCenter = CGPoint(x: contourCenter.x / CGFloat(contour.count), y: contourCenter.y / CGFloat(contour.count))
        let distance = hypot(center.x - avgContourCenter.x, center.y - avgContourCenter.y)
        
        if distance < minDistance {
            minDistance = distance
            closestContour = contour
        }
    }

    return closestContour
}

func fitEllipse(to points: [CGPoint], imageWidth: Int, imageHeight: Int) -> (center: CGPoint, size: CGSize, rotationInDegrees: CGFloat)? {
    guard points.count >= 5 else { return nil }

    var x = [Double]()
    var y = [Double]()
    
    for point in points {
        x.append(Double(point.x))
        y.append(Double(point.y))
    }

    let meanX = x.reduce(0, +) / Double(x.count)
    let meanY = y.reduce(0, +) / Double(y.count)
    
    var covXX = 0.0, covYY = 0.0, covXY = 0.0
    
    for i in 0..<x.count {
        let dx = x[i] - meanX
        let dy = y[i] - meanY
        covXX += dx * dx
        covYY += dy * dy
        covXY += dx * dy
    }
    
    covXX /= Double(x.count)
    covYY /= Double(y.count)
    covXY /= Double(x.count)
    
    let theta = 0.5 * atan2(2 * covXY, covXX - covYY)
    let thetaInDegrees = theta * 180 / .pi
    
    let term1 = covXX + covYY
    let term2 = sqrt(pow(covXX - covYY, 2) + 4 * covXY * covXY)
    
    let a = sqrt(2 * (term1 + term2) / Double(x.count))
    let b = sqrt(2 * (term1 - term2) / Double(x.count))
    
    return (center: CGPoint(x: meanX, y: meanY), size: CGSize(width: CGFloat(a), height: CGFloat(b)), rotationInDegrees: CGFloat(thetaInDegrees))
}

func calculateEllipseTips(center: CGPoint, size: CGSize, rotation: CGFloat) -> [CGPoint] {
    let rotationRadians = rotation * CGFloat.pi / 180
    let cosTheta = cos(rotationRadians)
    let sinTheta = sin(rotationRadians)

    let semiMajorAxis = size.height
    let semiMinorAxis = size.width

    // Define the tips in the ellipse's local coordinate system
    let top = CGPoint(x: 0, y: -semiMajorAxis)
    let right = CGPoint(x: semiMinorAxis, y: 0)
    let bottom = CGPoint(x: 0, y: semiMajorAxis)
    let left = CGPoint(x: -semiMinorAxis, y: 0)

    // Rotate and translate the points to the image coordinate system
    let topRotated = CGPoint(x: center.x + cosTheta * top.x - sinTheta * top.y, y: center.y + sinTheta * top.x + cosTheta * top.y)
    let rightRotated = CGPoint(x: center.x + cosTheta * right.x - sinTheta * right.y, y: center.y + sinTheta * right.x + cosTheta * right.y)
    let bottomRotated = CGPoint(x: center.x + cosTheta * bottom.x - sinTheta * bottom.y, y: center.y + sinTheta * bottom.x + cosTheta * bottom.y)
    let leftRotated = CGPoint(x: center.x + cosTheta * left.x - sinTheta * left.y, y: center.y + sinTheta * left.x + cosTheta * left.y)

    return [topRotated, rightRotated, bottomRotated, leftRotated]
}

func drawContoursEllipseAndTips(on image: UIImage, contours: [[CGPoint]], closestContour: [CGPoint], ellipse: (center: CGPoint, size: CGSize, rotation: CGFloat), tips: [CGPoint]) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: image.size)
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
