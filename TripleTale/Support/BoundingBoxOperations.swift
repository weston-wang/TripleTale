//
//  BoundingBoxOperations.swift
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

// MARK: - Bounding box manipulations
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

