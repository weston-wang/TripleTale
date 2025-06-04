//
//  VNPoint+Math.swift
//  TripleTale
//
//  Created by Wes Wang on 6/3/25.
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

extension VNPoint {

    /// Adds two VNPoints and returns the result as a new VNPoint.
    /// - Parameter other: The other VNPoint to add.
    /// - Returns: A new VNPoint with the added coordinates.
    func adding(_ other: VNPoint) -> VNPoint {
        let xSum = self.x + other.x
        let ySum = self.y + other.y
        return VNPoint(x: xSum, y: ySum)
    }

    /// Adds two VNPoints with clamping to the range [0, 1].
    /// - Parameter other: The other VNPoint to add.
    /// - Returns: A new VNPoint with the added coordinates clamped to [0, 1].
    func addingClamped(_ other: VNPoint) -> VNPoint {
        let xSum = clamp(self.x + other.x)
        let ySum = clamp(self.y + other.y)
        return VNPoint(x: xSum, y: ySum)
    }

    /// Helper function to clamp a value between 0 and 1.
    private func clamp(_ value: CGFloat) -> CGFloat {
        return min(max(value, 0), 1)
    }
}
