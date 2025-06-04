//
//  simd_float4+Helpers.swift
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

extension simd_float4 {
    var xyz: simd_float3 {
        return simd_float3(x, y, z)
    }
}
