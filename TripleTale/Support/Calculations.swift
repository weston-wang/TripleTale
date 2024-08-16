//
//  Calculations.swift
//  TripleTale
//
//  Created by Wes Wang on 5/9/24.
//  Copyright © 2024 Apple. All rights reserved.
//

import Foundation
import ARKit

// Define a type alias for the constants tuple
typealias LengthWeightConstants = (a: Double, b: Double)

// Create the lookup table as a dictionary
let lengthWeightLookupTable: [String: LengthWeightConstants] = [
    "CalicoBass": (a: 0.000012, b: 3.1),
    "BluefinTuna": (a: 0.000153, b: 3.124),
    "Yellowtail": (a: 0.0000127, b: 3.089 )
    // Add more species as needed
]

func calculateDistanceBetweenAnchors(anchor1: ARAnchor, anchor2: ARAnchor) -> Float {
    let position1 = SIMD3<Float>(anchor1.transform.columns.3.x, anchor1.transform.columns.3.y, anchor1.transform.columns.3.z)
    let position2 = SIMD3<Float>(anchor2.transform.columns.3.x, anchor2.transform.columns.3.y, anchor2.transform.columns.3.z)
    
    return simd_distance(position1, position2)
}

func calculateHeightBetweenAnchors(anchor1: ARAnchor, anchor2: ARAnchor) -> Float {
    let position1 = anchor1.transform.columns.3
    let position2 = anchor2.transform.columns.3
    return abs(position1.y - position2.y)
}

func calculateDepthBetweenAnchors(anchor1: ARAnchor, anchor2: ARAnchor) -> Float {
    let position1 = anchor1.transform.columns.3
    let position2 = anchor2.transform.columns.3
    return abs(position1.z - position2.z)
}

func calculateLengthBetweenAnchors(anchor1: ARAnchor, anchor2: ARAnchor) -> Float {
    let position1 = anchor1.transform.columns.3
    let position2 = anchor2.transform.columns.3
    return abs(position1.x - position2.x)
}

func calculateDistanceBetweenAnchors2D(anchor1: ARAnchor, anchor2: ARAnchor) -> Float {
        // Retrieve the positions
    let position1 = anchor1.transform.columns.3
    let position2 = anchor2.transform.columns.3
    
    // Calculate the differences in x and z directions
    let deltaX = position2.x - position1.x
    let deltaZ = position2.z - position1.z
    
    // Compute the distance in the x and z directions
    let distance = sqrt(deltaX * deltaX + deltaZ * deltaZ)
    
    return distance
}

func calculateDistanceBetweenAnchors2DVert(anchor1: ARAnchor, anchor2: ARAnchor) -> Float {
        // Retrieve the positions
    let position1 = anchor1.transform.columns.3
    let position2 = anchor2.transform.columns.3
    
    // Calculate the differences in x and z directions
    let deltaX = position2.x - position1.x
    let deltaZ = position2.y - position1.y
    
    // Compute the distance in the x and z directions
    let distance = sqrt(deltaX * deltaX + deltaZ * deltaZ)
    
    return distance
}

/// Calculates the circumference of an oval, adjusting for a 'roundness' factor.
/// - Parameters:
///   - a: Semi-major axis of the oval.
///   - b: Semi-minor axis of the oval.
///   - roundness: A factor from 0 (least round) to 1 (perfect circle) adjusting the calculation.
/// - Returns: The approximate circumference of the oval.
func calculateCircumference(majorAxis: Float, minorAxis: Float) -> Float {
    let a = majorAxis / 2
    let b = minorAxis / 2
    // Ramanujan's first approximation for the circumference of an ellipse
    let term1 = 3 * (a + b)
    let term2 = sqrt((3 * a + b) * (a + 3 * b))
    return Float(Double.pi) * (term1 - term2)
}

func calculateWeight(_ width: Float, _ length: Float, _ height: Float, _ circumference: Float, _ scale: Double) -> (Measurement<UnitMass>, Measurement<UnitLength>, Measurement<UnitLength>, Measurement<UnitLength>, Measurement<UnitLength>){
    
    let widthInMeters = Measurement(value: Double(width), unit: UnitLength.meters)
    let lengthInMeters = Measurement(value: Double(length), unit: UnitLength.meters)
    let heightInMeters = Measurement(value: Double(height), unit: UnitLength.meters)
    let circumferenceInMeters = Measurement(value: Double(circumference), unit: UnitLength.meters)
    
    let widthInInches = widthInMeters.converted(to: .inches)
    let lengthInInches = lengthInMeters.converted(to: .inches)
    let heightInInches = heightInMeters.converted(to: .inches)
    let circumferenceInInches = circumferenceInMeters.converted(to: .inches)
    
    let weight = lengthInInches.value * circumferenceInInches.value * circumferenceInInches.value / scale
    let weightInLb = Measurement(value: weight, unit: UnitMass.pounds)
    
    return (weightInLb, widthInInches, lengthInInches, heightInInches, circumferenceInInches)
}

func calculateWeightFromFork(_ fork: Float, _ species: String) -> (Measurement<UnitMass>, Measurement<UnitLength>) {
//    let a = 0.000153    // for bft
//    let b = 3.124       // for bft
    
    let constants = lengthWeightLookupTable["Yellowtail"]

    let forkInMeters = Measurement(value: Double(fork), unit: UnitLength.meters)
    let forkInInches = forkInMeters.converted(to: .inches)
    
    let weight = constants!.a * pow(forkInInches.value, constants!.b)
    
    print("Found weight \(weight)")

    let weightInLb = Measurement(value: weight, unit: UnitMass.pounds)
    
    return (weightInLb, forkInInches)
}

func calculateDistanceToObject(_ inputAnchor: ARAnchor) -> Float {
    let distance = sqrt(inputAnchor.transform.columns.3.x*inputAnchor.transform.columns.3.x + inputAnchor.transform.columns.3.y*inputAnchor.transform.columns.3.y + inputAnchor.transform.columns.3.z*inputAnchor.transform.columns.3.z)
    
    return distance
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

func normalVector(from anchors: [ARAnchor]) -> simd_float3? {
    guard anchors.count >= 3 else {
        return nil // You need at least three points to define a plane
    }

    // Get the positions of three of the anchors
    let positionA = simd_float3(anchors[0].transform.columns.3.x, anchors[0].transform.columns.3.y, anchors[0].transform.columns.3.z)
    let positionB = simd_float3(anchors[1].transform.columns.3.x, anchors[1].transform.columns.3.y, anchors[1].transform.columns.3.z)
    let positionC = simd_float3(anchors[2].transform.columns.3.x, anchors[2].transform.columns.3.y, anchors[2].transform.columns.3.z)

    // Create two vectors lying on the plane
    let vectorAB = positionB - positionA
    let vectorAC = positionC - positionA

    // Calculate the cross product to get the normal vector
    let normal = simd_cross(vectorAB, vectorAC)

    // Normalize the normal vector to make it a unit vector
    let normalizedNormal = simd_normalize(normal)

    return normalizedNormal
}

func distanceToPlane(from newAnchor: ARAnchor, planeAnchor: ARAnchor, normal: simd_float3) -> Float {
    // Get the positions of the new anchor and one of the plane's anchors
    let pointP = simd_float3(newAnchor.transform.columns.3.x, newAnchor.transform.columns.3.y, newAnchor.transform.columns.3.z)
    let pointA = simd_float3(planeAnchor.transform.columns.3.x, planeAnchor.transform.columns.3.y, planeAnchor.transform.columns.3.z)
    
    // Create a vector from point A (on the plane) to point P (the new anchor)
    let vectorAP = pointP - pointA
    
    // Project vectorAP onto the normal vector to get the distance in the "up" direction
    let distance = simd_dot(vectorAP, normal)
    
    return distance
}

func distanceAlongNormalVector(from anchor: ARAnchor, normal: simd_float3) -> Float {
    // Get the position of the anchor
    let anchorPosition = simd_float3(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
    
    // Project the anchor's position onto the normal vector
    let distance = simd_dot(anchorPosition, normal)
    
    return distance
}
