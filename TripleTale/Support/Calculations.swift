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

/// Calculates the circumference of an oval, adjusting for a 'roundness' factor.
/// - Parameters:
///   - a: Semi-major axis of the oval.
///   - b: Semi-minor axis of the oval.
///   - roundness: A factor from 0 (least round) to 1 (perfect circle) adjusting the calculation.
/// - Returns: The approximate circumference of the oval.
func calculateCircumference(a: Float, b: Float, roundness: Float) -> Float {
    // Calculate the average of the axes as a base calculation
    let averageAxis = (a + b) / 2.0
    let baseCircumference = 2 * Float.pi * averageAxis

    // Adjust the circumference based on the roundness
    let adjustedCircumference = baseCircumference * (1 - roundness) + (2 * Float.pi * min(a, b) * roundness)
    return adjustedCircumference
}
