//
//  ARSessionManager.swift
//  TripleTale
//
//  Created by Wes Wang on 3/4/25.
//

import Foundation
import ARKit

class ARSessionManager {
    static let shared = ARSessionManager()
    
    var savedWorldMap: ARWorldMap?
    var accumulatedFeaturePoints: [simd_float3] = []
}
