//
//  Measurements.swift
//  tripletalear
//
//  Created by Wes Wang on 8/20/24.
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

func calculateDistanceToObject(_ inputAnchor: ARAnchor) -> Float {
    let distance = sqrt(inputAnchor.transform.columns.3.x*inputAnchor.transform.columns.3.x + inputAnchor.transform.columns.3.y*inputAnchor.transform.columns.3.y + inputAnchor.transform.columns.3.z*inputAnchor.transform.columns.3.z)
    
    return distance
}

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

func measureVertices(_ verticesAnchors: [ARAnchor], _ cornersAnchors: [ARAnchor], _ aboveAnchor: ARAnchor, _ belowAnchor: ARAnchor) ->  (Float, Float, Float) {
    let width = calculateDistanceBetweenAnchors2D(anchor1: verticesAnchors[0], anchor2: verticesAnchors[2])
    let length = calculateDistanceBetweenAnchors2D(anchor1: verticesAnchors[1], anchor2: verticesAnchors[3])
    
    let normVector = normalVector(from: cornersAnchors)
    let height = distanceToPlane(from: aboveAnchor, planeAnchor: belowAnchor, normal: normVector!)
    
    return (width, length, height)
}
