//
//  MeasurementUtil.swift
//  TripleTale
//
//  Created by Wes Wang on 6/4/25.
//
import Foundation
import ARKit

struct MeasurementUtils {
    
    // Define a type alias for the constants tuple
    typealias LengthWeightConstants = (a: Double, b: Double)

    // Create the lookup table as a dictionary
    private static let lengthWeightLookupTable: [String: LengthWeightConstants] = [
        "CalicoBass": (a: 0.0004, b: 3.218),
        "BluefinTuna": (a: 0.000153, b: 3.124),
        "Yellowtail": (a: 0.0000127, b: 3.089 )
        // Add more species as needed
    ]


    /// Calculates the circumference of an oval, adjusting for a 'roundness' factor.
    /// - Parameters:
    ///   - a: Semi-major axis of the oval.
    ///   - b: Semi-minor axis of the oval.
    ///   - roundness: A factor from 0 (least round) to 1 (perfect circle) adjusting the calculation.
    /// - Returns: The approximate circumference of the oval.
    static func calculateCircumference(majorAxis: Float, minorAxis: Float) -> Float {
        let a = majorAxis / 2
        let b = minorAxis / 2
        // Ramanujan's first approximation for the circumference of an ellipse
        let term1 = 3 * (a + b)
        let term2 = sqrt((3 * a + b) * (a + 3 * b))
        return Float(Double.pi) * (term1 - term2)
    }

    static func calculateWeight(_ width: Float, _ length: Float, _ height: Float, _ girth: Float, _ scale: Double) -> (Measurement<UnitMass>, Measurement<UnitLength>, Measurement<UnitLength>, Measurement<UnitLength>, Measurement<UnitLength>){
        
        let widthInMeters = Measurement(value: Double(width), unit: UnitLength.meters)
        let lengthInMeters = Measurement(value: Double(length), unit: UnitLength.meters)
        let heightInMeters = Measurement(value: Double(height), unit: UnitLength.meters)
        let girthInMeters = Measurement(value: Double(girth), unit: UnitLength.meters)
        
        let widthInInches = widthInMeters.converted(to: .inches)
        let lengthInInches = lengthInMeters.converted(to: .inches)
        let heightInInches = heightInMeters.converted(to: .inches)
        let girthInInches = girthInMeters.converted(to: .inches)
        
        let weight = lengthInInches.value * girthInInches.value * girthInInches.value / scale
        let weightInLb = Measurement(value: weight, unit: UnitMass.pounds)
        
        return (weightInLb, widthInInches, lengthInInches, heightInInches, girthInInches)
    }

    static func calculateWeightFromFork(_ forkIn: CGFloat, _ species: String) -> (Measurement<UnitMass>, Measurement<UnitLength>) {
    //    let a = 0.000153    // for bft
    //    let b = 3.124       // for bft
        
        let constants = lengthWeightLookupTable[species]

        let forkInInches =  Measurement(value: Double(forkIn), unit: UnitLength.inches)
        
        let interim = pow(forkInInches.value, Double(constants!.b))
        let weight = Double(constants!.a) * interim
        
        print("species: \(species), a: \(constants!.a), b: \(constants!.b)")
        print("intermedia var: \(interim)")
        print("Fork length \(forkInInches) in")
        print("Found weight \(weight)")

        let weightInLb = Measurement(value: weight, unit: UnitMass.pounds)
        
        return (weightInLb, forkInInches)
    }

    static func measureVertices( _ verticesAnchors: [ARAnchor] ) ->  (Float, Float) {
        let width = AnchorUtils.calculateDistanceBetweenAnchors(anchor1: verticesAnchors[0], anchor2: verticesAnchors[2])
        let length = AnchorUtils.calculateDistanceBetweenAnchors(anchor1: verticesAnchors[1], anchor2: verticesAnchors[3])
        
        return (width, length)
    }

}
