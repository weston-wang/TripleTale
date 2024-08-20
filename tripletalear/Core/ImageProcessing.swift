//
//  ImageProcessing.swift
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

func fitEllipse(to points: [CGPoint]) -> (center: CGPoint, size: CGSize, rotationInDegrees: CGFloat)? {
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
    
//    let a = sqrt(2 * (term1 + term2) / Double(x.count))
//    let b = sqrt(2 * (term1 - term2) / Double(x.count))
    
    let a = sqrt(2 * (term1 + term2))
    let b = sqrt(2 * (term1 - term2))
    
    return (center: CGPoint(x: meanX, y: meanY), size: CGSize(width: CGFloat(a), height: CGFloat(b)), rotationInDegrees: CGFloat(thetaInDegrees))
}

func fitEllipseMinimax(to points: [CGPoint]) -> (center: CGPoint, size: CGSize, rotationInDegrees: CGFloat)? {
    guard points.count >= 5 else { return nil }
    // Step 1: Calculate the centroid (mean values)
    var meanX: CGFloat = 0
    var meanY: CGFloat = 0
    for point in points {
        meanX += point.x
        meanY += point.y
    }
    meanX /= CGFloat(points.count)
    meanY /= CGFloat(points.count)
    
    // Step 2: Calculate the covariance matrix elements
    var covXX: CGFloat = 0
    var covYY: CGFloat = 0
    var covXY: CGFloat = 0
    for point in points {
        let dx = point.x - meanX
        let dy = point.y - meanY
        covXX += dx * dx
        covYY += dy * dy
        covXY += dx * dy
    }
    covXX /= CGFloat(points.count)
    covYY /= CGFloat(points.count)
    covXY /= CGFloat(points.count)
    
    // Step 3: Calculate the orientation angle using the Rayleigh quotient
    let theta = 0.5 * atan2(2 * covXY, covXX - covYY)
    
    // Step 4: Calculate eigenvalues (semi-major and semi-minor axis lengths)
    let term1 = covXX + covYY
    let term2 = sqrt(pow(covXX - covYY, 2) + 4 * covXY * covXY)
    
    // Compute the maximum eigenvalue for semi-major axis (a)
    let maxEigenvalue = (term1 + term2) / 2
    // Compute the minimum eigenvalue for semi-minor axis (b)
    let minEigenvalue = (term1 - term2) / 2
    
    let a = sqrt(2 * maxEigenvalue)
    let b = sqrt(2 * minEigenvalue)
    
    // No scaling applied here to match the raw values from the Least Squares method
    let size = CGSize(width: CGFloat(a), height: CGFloat(b))
    
    // Center of the ellipse
    let center = CGPoint(x: meanX, y: meanY)
    
    // Rotation in degrees
    let rotationInDegrees = theta * 180 / .pi
    
    return (center: center, size: size, rotationInDegrees: rotationInDegrees)
}

func calculateEllipseTips(center: CGPoint, size: CGSize, rotation: CGFloat) -> [CGPoint] {
    let rotationRadians = rotation * CGFloat.pi / 180
    let cosTheta = cos(rotationRadians)
    let sinTheta = sin(rotationRadians)

    let semiMajorAxis = [size.height, size.width].min()
    let semiMinorAxis = [size.height, size.width].max()

    // Define the tips in the ellipse's local coordinate system
    let top = CGPoint(x: 0, y: -semiMajorAxis!)
    let right = CGPoint(x: semiMinorAxis!, y: 0)
    let bottom = CGPoint(x: 0, y: semiMajorAxis!)
    let left = CGPoint(x: -semiMinorAxis!, y: 0)

    // Rotate and translate the points to the image coordinate system
    let topRotated = CGPoint(x: center.x + cosTheta * top.x - sinTheta * top.y, y: center.y + sinTheta * top.x + cosTheta * top.y)
    let rightRotated = CGPoint(x: center.x + cosTheta * right.x - sinTheta * right.y, y: center.y + sinTheta * right.x + cosTheta * right.y)
    let bottomRotated = CGPoint(x: center.x + cosTheta * bottom.x - sinTheta * bottom.y, y: center.y + sinTheta * bottom.x + cosTheta * bottom.y)
    let leftRotated = CGPoint(x: center.x + cosTheta * left.x - sinTheta * left.y, y: center.y + sinTheta * left.x + cosTheta * left.y)

    return [topRotated, rightRotated, bottomRotated, leftRotated]
}

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
