//
//  ContourExtractor.swift
//  TripleTale
//
//  Created by Wes Wang on 6/9/25.
//
import CoreImage
import UIKit
import Vision

struct ContourExtractor {
    
    static func extractContours(from pixelData: [UInt8], width: Int, height: Int) -> ([[CGPoint]], [[CGPoint]]) {
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

    static func findContourClosestToCenter(contours: [[CGPoint]], imageWidth: Int, imageHeight: Int) -> [CGPoint]? {
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
}
