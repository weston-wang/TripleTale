//
//  ComputerVision.swift
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

func centerROI(for image: CIImage, portion: CGFloat) -> CGRect {
    // Calculate the dimensions of the ROI
    let roiWidth = portion
    let roiHeight = portion
    
    // Calculate the position to center the ROI
    let roiX = (1.0 - roiWidth) / 2.0
    let roiY = (1.0 - roiHeight) / 2.0
    
    // Create and return the CGRect for the ROI
    return CGRect(x: roiX, y: roiY, width: roiWidth, height: roiHeight)
}

func generateMaskImage(from image: UIImage, for portion: CGFloat) -> CIImage? {
    guard let ciImage = CIImage(image: image) else { return nil }

    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    
    let roiRect = centerROI(for: ciImage, portion: portion)
    request.regionOfInterest = roiRect

    do {
        try handler.perform([request])
        if let result = request.results?.first {
            let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            
            // Create a blank image of the original size
            let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)
            let blankImage = CIImage(color: .black).cropped(to: ciImage.extent)

            // Calculate the translation for the mask
            let translateX = roiRect.origin.x * ciImage.extent.width
            let translateY = roiRect.origin.y * ciImage.extent.height

            // Apply translation to the mask
            let transformedMaskCIImage = maskCIImage.transformed(by: CGAffineTransform(translationX: translateX, y: translateY))

            // Composite the mask onto the blank image
            let finalImage = transformedMaskCIImage.composited(over: blankImage)

            return finalImage
        }
    } catch {
        print(error.localizedDescription)
    }
    return nil
}

func extractContours(from pixelData: [UInt8], width: Int, height: Int) -> ([[CGPoint]], [[CGPoint]]) {
    var contours = [[CGPoint]]()
    var perimeters = [[CGPoint]]()
    var visited = Array(repeating: Array(repeating: false, count: width), count: height)
    let directions = [(-1, 0), (1, 0), (0, -1), (0, 1)] // 4-connected directions
    let diagonalDirections = [(-1, -1), (-1, 1), (1, -1), (1, 1)] // Diagonal neighbors for smooth traversal

    func isEdge(x: Int, y: Int) -> Bool {
        // Check if the pixel is part of the perimeter
        for (dx, dy) in directions + diagonalDirections {
            let newX = x + dx
            let newY = y + dy
            if newX < 0 || newX >= width || newY < 0 || newY >= height || pixelData[newY * width + newX] == 0 {
                return true
            }
        }
        return false
    }

    func bfsWithOrderedPerimeter(startX: Int, startY: Int) -> ([CGPoint], [CGPoint]) {
        var queue = [(x: Int, y: Int)]()
        queue.append((startX, startY))
        visited[startY][startX] = true
        var contour = [CGPoint]()
        var perimeter = [CGPoint]()
        
        while !queue.isEmpty {
            let (x, y) = queue.removeFirst()
            contour.append(CGPoint(x: x, y: y))
            
            if isEdge(x: x, y: y) {
                perimeter.append(CGPoint(x: x, y: y))
            }
            
            for (dx, dy) in directions {
                let newX = x + dx
                let newY = y + dy
                if newX >= 0, newX < width, newY >= 0, newY < height, !visited[newY][newX], pixelData[newY * width + newX] == 255 {
                    queue.append((newX, newY))
                    visited[newY][newX] = true
                }
            }
        }
        
        // Sort the perimeter to ensure smooth connection
        perimeter = sortPerimeter(perimeter)
        
        return (contour, perimeter)
    }

    func sortPerimeter(_ perimeter: [CGPoint]) -> [CGPoint] {
        // Sort perimeter points to follow the boundary in a clockwise or counterclockwise order
        guard perimeter.count > 1 else { return perimeter }
        
        let centerX = perimeter.map { $0.x }.reduce(0, +) / CGFloat(perimeter.count)
        let centerY = perimeter.map { $0.y }.reduce(0, +) / CGFloat(perimeter.count)
        let center = CGPoint(x: centerX, y: centerY)
        
        return perimeter.sorted {
            let angle1 = atan2($0.y - center.y, $0.x - center.x)
            let angle2 = atan2($1.y - center.y, $1.x - center.x)
            return angle1 < angle2
        }
    }

    for y in 0..<height {
        for x in 0..<width {
            if pixelData[y * width + x] == 255 && !visited[y][x] {
                let (contour, perimeter) = bfsWithOrderedPerimeter(startX: x, startY: y)
                if !contour.isEmpty {
                    contours.append(contour)
                    perimeters.append(perimeter)
                }
            }
        }
    }

    return (contours, perimeters)
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

func detectTopFaceBoundingBox(in image: UIImage) -> CGRect? {
    guard let ciImage = CIImage(image: image) else {
        fatalError("Unable to create CIImage from UIImage")
    }
    
    var topFaceRect: CGRect?
    
    let faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
        if let error = error {
            print("Face detection error: \(error)")
            return
        }
        guard let observations = request.results as? [VNFaceObservation] else {
            return
        }
        
        var minY: CGFloat = CGFloat.greatestFiniteMagnitude
        
        for face in observations {
            let boundingBox = face.boundingBox
            let size = image.size
            let x = boundingBox.origin.x * size.width
            let y = (1 - boundingBox.origin.y - boundingBox.height) * size.height
            let width = boundingBox.width * size.width
            let height = boundingBox.height * size.height
            let faceRect = CGRect(x: x, y: y, width: width, height: height)
            
            // Update the topFaceRect if this face is closer to the top
            if y < minY {
                minY = y
                topFaceRect = faceRect
            }
        }
    }
    
    let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    
    do {
        try requestHandler.perform([faceDetectionRequest])
    } catch {
        print("Failed to perform face detection: \(error)")
        return nil
    }
    
    return topFaceRect
}
