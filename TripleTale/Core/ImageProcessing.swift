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

func calculateRectangleCorners(_ vertices: [CGPoint], _ ditherX: CGFloat, _ ditherY: CGFloat) -> [CGPoint] {
    guard vertices.count == 4 else {
        fatalError("There must be exactly 4 vertices.")
    }

    // Calculate the center
    let centerX = (vertices[0].x + vertices[1].x + vertices[2].x + vertices[3].x) / 4
    let centerY = (vertices[0].y + vertices[1].y + vertices[2].y + vertices[3].y) / 4
    let center = CGPoint(x: centerX, y: centerY)

    // Calculate the angle of rotation
    let angle = atan2(vertices[2].y - vertices[0].y, vertices[2].x - vertices[0].x)
    
    // Calculate the semi-major and semi-minor axes lengths
    let a = sqrt(pow(vertices[2].x - vertices[0].x, 2) + pow(vertices[2].y - vertices[0].y, 2)) / 2 * (1.0 + ditherY)
    let b = sqrt(pow(vertices[3].x - vertices[1].x, 2) + pow(vertices[3].y - vertices[1].y, 2)) / 2 * (1.0 + ditherX)
    
    // Calculate the corners
    let corner1 = CGPoint(x: center.x + a * cos(angle) - b * sin(angle),
                          y: center.y + a * sin(angle) + b * cos(angle))
    
    let corner2 = CGPoint(x: center.x - a * cos(angle) - b * sin(angle),
                          y: center.y - a * sin(angle) + b * cos(angle))
    
    let corner3 = CGPoint(x: center.x - a * cos(angle) + b * sin(angle),
                          y: center.y - a * sin(angle) - b * cos(angle))
    
    let corner4 = CGPoint(x: center.x + a * cos(angle) + b * sin(angle),
                          y: center.y + a * sin(angle) - b * cos(angle))

    return [corner1, corner2, corner3, corner4]
}

func thresholdImage(inputImage: UIImage, threshold: Float) -> UIImage? {
    // Convert UIImage to CIImage
    guard let ciImage = CIImage(image: inputImage) else { return nil }
    
    // Create a CIContext to process the image
    let ciContext = CIContext(options: nil)
    
    // Convert to grayscale using CIColorControls
    let grayscaleFilter = CIFilter(name: "CIColorControls")
    grayscaleFilter?.setValue(ciImage, forKey: kCIInputImageKey)
    grayscaleFilter?.setValue(0.0, forKey: kCIInputSaturationKey) // Set saturation to 0 for grayscale
    
    // Retrieve the grayscale image
    guard let grayscaleCIImage = grayscaleFilter?.outputImage else { return nil }
    
    // Apply a threshold using CIThresholdToAlpha (available in Core Image filters)
    let thresholdFilter = CIFilter(name: "CIThresholdToAlpha")!
    thresholdFilter.setValue(grayscaleCIImage, forKey: kCIInputImageKey)
    thresholdFilter.setValue(threshold, forKey: "inputThreshold")
    
    // Get the output CIImage from the filter
    guard let thresholdedCIImage = thresholdFilter.outputImage else { return nil }
    
    // Convert the CIImage to CGImage
    guard let cgImage = ciContext.createCGImage(thresholdedCIImage, from: thresholdedCIImage.extent) else { return nil }
    
    // Return the thresholded image as a UIImage
    return UIImage(cgImage: cgImage)
}
