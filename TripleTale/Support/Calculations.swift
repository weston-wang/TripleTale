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

func calculateWeight(_ width: Float, _ length: Float, _ height: Float, _ circumference: Float) -> (Measurement<UnitMass>, Measurement<UnitLength>, Measurement<UnitLength>, Measurement<UnitLength>, Measurement<UnitLength>){
    
    let widthInMeters = Measurement(value: Double(width), unit: UnitLength.meters)
    let lengthInMeters = Measurement(value: Double(length), unit: UnitLength.meters)
    let heightInMeters = Measurement(value: Double(height), unit: UnitLength.meters)
    let circumferenceInMeters = Measurement(value: Double(circumference), unit: UnitLength.meters)
    
    let widthInInches = widthInMeters.converted(to: .inches)
    let lengthInInches = lengthInMeters.converted(to: .inches)
    let heightInInches = heightInMeters.converted(to: .inches)
    let circumferenceInInches = circumferenceInMeters.converted(to: .inches)
    
    let weight = lengthInInches.value * circumferenceInInches.value * circumferenceInInches.value / 500
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

func calculateRectangleCorners(fromMidpoints midpoints: [CGPoint]) -> [CGPoint] {
    guard midpoints.count == 4 else {
        fatalError("Midpoints array must contain exactly 4 points.")
    }

    let A = midpoints[0] // Midpoint between corners 1 and 2
    let B = midpoints[1] // Midpoint between corners 2 and 3
    let C = midpoints[2] // Midpoint between corners 3 and 4
    let D = midpoints[3] // Midpoint between corners 4 and 1

    // Calculate vectors representing half-diagonals
    let vectorAC = CGPoint(x: C.x - A.x, y: C.y - A.y)
    let vectorBD = CGPoint(x: D.x - B.x, y: D.y - B.y)

    // Calculate the correct corners using vector addition/subtraction
    let corner1 = CGPoint(x: A.x - vectorBD.x / 2, y: A.y - vectorBD.y / 2)
    let corner2 = CGPoint(x: B.x + vectorAC.x / 2, y: B.y + vectorAC.y / 2)
    let corner3 = CGPoint(x: C.x + vectorBD.x / 2, y: C.y + vectorBD.y / 2)
    let corner4 = CGPoint(x: D.x - vectorAC.x / 2, y: D.y - vectorAC.y / 2)

    return [corner1, corner2, corner3, corner4]
}
