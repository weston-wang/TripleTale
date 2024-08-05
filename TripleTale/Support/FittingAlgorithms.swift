//
//  FittingAlgorithms.swift
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

func fitEllipseMinimax(to points: [CGPoint], imageWidth: Int, imageHeight: Int) -> (center: CGPoint, size: CGSize, rotationInDegrees: CGFloat)? {
    guard points.count >= 5 else { return nil }

    var minX = CGFloat.greatestFiniteMagnitude
    var minY = CGFloat.greatestFiniteMagnitude
    var maxX = CGFloat.leastNormalMagnitude
    var maxY = CGFloat.leastNormalMagnitude

    for point in points {
        if point.x < minX { minX = point.x }
        if point.y < minY { minY = point.y }
        if point.x > maxX { maxX = point.x }
        if point.y > maxY { maxY = point.y }
    }
    
    
    let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
//    let size = CGSize(width: (maxX - minX) / 2 * 4 / imageWidth, height: (maxY - minY) / 2 * 4 / imageHeight)
    let size = CGSize(width: (maxX - minX) * 2.0 / CGFloat(imageWidth), height: (maxY - minY) * 2.0 / CGFloat(imageHeight))
    let rotationInDegrees: CGFloat = 0 // No rotation for a bounding box approach

    return (center, size, rotationInDegrees)
}
