//
//  PointUtils.swift
//  TripleTale
//
//  Created by Wes Wang on 6/4/25.
//
import CoreGraphics
import SceneKit

struct PointUtils {
    static func distanceBetween(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Converts a normalized VNPoint.location to a CGPoint in the image coordinate system.
    /// - Parameters:
    ///   - point: The VNPoint to convert (assumed to be normalized between 0 and 1, with a lower-left origin).
    ///   - imageSize: The size of the image for conversion.
    /// - Returns: The CGPoint in the image's coordinate space.
    static func convertNormalizedPointToCGPoint(_ point: CGPoint, imageSize: CGSize) -> CGPoint {
        // Convert normalized coordinates with a lower-left origin to UIKit's top-left origin
        let x = point.x * imageSize.width
        let y = (1.0 - point.y) * imageSize.height // Flip y-axis for UIKit
        return CGPoint(x: x, y: y)
    }

    static func scalePoint(point: simd_float3, center: simd_float3, verticalScaleFactor: Float, horizontalScaleFactor: Float) -> simd_float3 {
        let vector = point - center
        let scaledVector = simd_float3(x: vector.x * horizontalScaleFactor, y: vector.y * verticalScaleFactor, z: vector.z)
        return center + scaledVector
    }

    // Function to calculate the center of an array of CGPoint
    static func calculateCenter(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }  // Return nil if the array is empty
        
        var totalX: CGFloat = 0
        var totalY: CGFloat = 0
        
        // Sum all x and y values
        for point in points {
            totalX += point.x
            totalY += point.y
        }
        
        // Calculate the average x and y values
        let centerX = totalX / CGFloat(points.count)
        let centerY = totalY / CGFloat(points.count)
        
        return CGPoint(x: centerX, y: centerY)
    }
    
    static func applySmallDither(to vertices: [CGPoint]) -> [CGPoint] {
        let ditherAmount: CGFloat = 0.005 // Small dither in normalized coordinates
        return vertices.map { point in
            let dx = (CGFloat.random(in: -ditherAmount...ditherAmount))
            let dy = (CGFloat.random(in: -ditherAmount...ditherAmount))
            return CGPoint(x: min(1.0, max(0.0, point.x + dx)),
                           y: min(1.0, max(0.0, point.y + dy))) // Keep within [0,1] range
        }
    }
    
    /// Projects a point along a ray direction from origin to a target Z-depth
    static func backProjectToZPlane(
        origin: simd_float3,
        direction: simd_float3,
        targetZ: Float
    ) -> simd_float3 {
        let t = (targetZ - origin.z) / direction.z
        return origin + direction * t
    }
    
    // Function to scale the object as if it were in the same plane as the face
    static func scaleObjectToFacePlane(measuredLength: CGFloat, faceDistanceToCamera: CGFloat, objectDistanceToCamera: CGFloat) -> CGFloat {
        
        // Calculate the distance ratio (how much closer the object is compared to the face)
        let scalingRatio = objectDistanceToCamera / faceDistanceToCamera
        
        // Scale the measured length of the object
        let scaledLength = measuredLength * scalingRatio
        
        return scaledLength
    }
}
