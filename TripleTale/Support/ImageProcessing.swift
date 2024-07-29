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

func removeBackground(from image: UIImage) -> CGRect? {
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
