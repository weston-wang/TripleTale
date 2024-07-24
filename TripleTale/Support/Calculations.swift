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
