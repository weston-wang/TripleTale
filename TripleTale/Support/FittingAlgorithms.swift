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

func fitEllipseLeastSquares(to points: [CGPoint], on image: UIImage) -> (circumference: Double?, resultImage: UIImage?) {
    guard points.count >= 5 else { return (nil, nil) }

    // Formulate the design matrix
    var designMatrix = [[Double]]()
    for point in points {
        let x = Double(point.x)
        let y = Double(point.y)
        designMatrix.append([x * x, x * y, y * y, x, y, 1.0])
    }

    // Calculate scatter matrix S
    let designMatrixTransposed = transpose(designMatrix)
    let scatterMatrix = multiply(designMatrixTransposed, designMatrix)
    
    // Check if scatterMatrix is invertible
    guard let scatterMatrixInverse = inverse(scatterMatrix) else {
        print("Scatter matrix is not invertible")
        return (nil, nil)
    }
    
    // Solve the generalized eigenvalue problem
    let A = scatterMatrixInverse[0][0]
    let B = scatterMatrixInverse[1][0] / 2
    let C = scatterMatrixInverse[2][0]
    let D = scatterMatrixInverse[3][0] / 2
    let E = scatterMatrixInverse[4][0] / 2
    let F = scatterMatrixInverse[5][0]
    
    // Calculate the center, axes, and orientation of the ellipse
    let denom = B * B - A * C
    guard denom != 0 else {
        print("Denominator is zero")
        return (nil, nil)
    }
    
    let x0 = (C * D - B * E) / denom
    let y0 = (A * E - B * D) / denom
    
    // Calculate semi-major and semi-minor axes
    let term1 = 2 * (A * E * E + C * D * D + F * B * B - 2 * B * D * E - A * C * F)
    let term2 = sqrt(pow(A - C, 2) + 4 * B * B)
    
    guard term1 > 0, term2 > 0 else {
        print("Invalid values for term1 or term2")
        return (nil, nil)
    }
    
    let a = sqrt(term1 / (denom * (term2 - (A + C))))
    let b = sqrt(term1 / (denom * (-term2 - (A + C))))
    
    // Calculate the rotation angle
    let rotation = atan2(2 * B, A - C) / 2
    
    // Ramanujan's approximation for the circumference of an ellipse
    let circumference = Double.pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)))
    
    // Draw the points and ellipse on the image
    let renderer = UIGraphicsImageRenderer(size: image.size)
    let resultImage = renderer.image { context in
        // Draw the original image
        image.draw(at: .zero)
        
        // Set the points drawing properties
        context.cgContext.setStrokeColor(UIColor.blue.cgColor)
        context.cgContext.setFillColor(UIColor.blue.cgColor)
        context.cgContext.setLineWidth(2.0)
        
        // Draw the points
        for point in points {
            let rect = CGRect(x: point.x * CGFloat(image.size.width) + CGFloat(image.size.width) / 2 - 2, y: -point.y * CGFloat(image.size.height) + CGFloat(image.size.height) / 2 - 2, width: 4, height: 4)
            context.cgContext.fillEllipse(in: rect)
        }
        
        // Set the ellipse drawing properties
        context.cgContext.setStrokeColor(UIColor.red.cgColor)
        context.cgContext.setLineWidth(2.0)
        
        // Draw the ellipse
        context.cgContext.saveGState()
        context.cgContext.translateBy(x: CGFloat(x0) * CGFloat(image.size.width) + CGFloat(image.size.width) / 2, y: -CGFloat(y0) * CGFloat(image.size.height) + CGFloat(image.size.height) / 2)
        context.cgContext.rotate(by: rotation)
        let ellipseRect = CGRect(x: -a * CGFloat(image.size.width), y: -b * CGFloat(image.size.height), width: 2 * a * CGFloat(image.size.width), height: 2 * b * CGFloat(image.size.height))
        context.cgContext.strokeEllipse(in: ellipseRect)
        context.cgContext.restoreGState()
    }
    
    return (circumference, resultImage)
}
