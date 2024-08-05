//
//  Calculations.swift
//  TripleTale
//
//  Created by Wes Wang on 5/9/24.
//  Copyright © 2024 Apple. All rights reserved.
//

import Foundation
import ARKit

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
    
    let weight = lengthInInches.value * circumferenceInInches.value * circumferenceInInches.value / 800
    let weightInLb = Measurement(value: weight, unit: UnitMass.pounds)
    
    return (weightInLb, widthInInches, lengthInInches, heightInInches, circumferenceInInches)
}

func calculateDistanceToObject(_ inputAnchor: ARAnchor) -> Float {
    let distance = sqrt(inputAnchor.transform.columns.3.x*inputAnchor.transform.columns.3.x + inputAnchor.transform.columns.3.y*inputAnchor.transform.columns.3.y + inputAnchor.transform.columns.3.z*inputAnchor.transform.columns.3.z)
    
    return distance
}

func measureDimensions(_ midpointAnchors: [ARAnchor], _ centroidAnchor: ARAnchor, _ originalBoundingBox:CGRect, _ imageSize: CGSize, _ currentView: ARSKView, _ isForward: Bool, scale: Float = 1.0) -> (Float, Float, Float, Float){
    var length: Float
    var width: Float
    var height: Float
    var circumference: Float
            
    var updatedMidpointAnchors: [ARAnchor]
    
    if !isForward {
        height = calculateHeightBetweenAnchors(anchor1: centroidAnchor, anchor2: midpointAnchors[4])

        let distanceToPhone = calculateDistanceToObject(midpointAnchors[4])
        let distanceToGround = calculateDistanceToObject(centroidAnchor)
                    
        // update boundingbox for calculations
        let updatedBoundingBox = reversePerspectiveEffectOnBoundingBox(boundingBox: originalBoundingBox, distanceToPhone: distanceToPhone, totalDistance: distanceToGround)
        
        updatedMidpointAnchors = getMidpoints(currentView, updatedBoundingBox, imageSize)
    } else {
        let heightL = calculateDepthBetweenAnchors(anchor1: midpointAnchors[4], anchor2: midpointAnchors[0])
        let heightR = calculateDepthBetweenAnchors(anchor1: midpointAnchors[4], anchor2: midpointAnchors[1])

        height = max(heightL, heightR) * 2.0 * scale
        
        updatedMidpointAnchors = midpointAnchors
    }
    
    width = calculateDistanceBetweenAnchors(anchor1: updatedMidpointAnchors[0], anchor2: updatedMidpointAnchors[1]) * scale
    length = calculateDistanceBetweenAnchors(anchor1: updatedMidpointAnchors[2], anchor2: updatedMidpointAnchors[3]) * scale
            
    circumference = calculateCircumference(majorAxis: width, minorAxis: height)
    
    return (width, length, height, circumference)
}

func measureVertices(_ verticesAnchors: [ARAnchor], _ aboveAnchor: ARAnchor, _ belowAnchor: ARAnchor) ->  (Float, Float, Float, Float) {
    let height = calculateDistanceBetweenAnchors(anchor1: aboveAnchor, anchor2: belowAnchor)
    let width = calculateDistanceBetweenAnchors2D(anchor1: verticesAnchors[0], anchor2: verticesAnchors[2])
    let length = calculateDistanceBetweenAnchors2D(anchor1: verticesAnchors[1], anchor2: verticesAnchors[3])
    
    let circumference = calculateCircumference(majorAxis: width, minorAxis: height)

    return (width, length, height, circumference)
}
