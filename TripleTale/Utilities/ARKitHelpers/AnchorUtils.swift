//
//  AnchorUtils.swift
//  TripleTale
//
//  Created by Wes Wang on 6/4/25.
//
import ARKit

struct AnchorUtils {
    static func position(from anchor: ARAnchor) -> SIMD3<Float> {
        return SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
    }
    
    static func areAnchorHeightsWithinTolerance(_ anchors: [ARAnchor], tolerance: Float = 0.1) -> Bool {
        guard anchors.count > 1 else { return true }
        
        // Extract all Y positions
        let yValues = anchors.map { $0.transform.columns.3.y }
        
        // Get min and max
        guard let minY = yValues.min(), let maxY = yValues.max() else {
            return true
        }
        
        return (maxY - minY) <= tolerance
    }
    
    /// Back-projects all but the closest anchor to the Z-plane of the closest one
    /// - Parameters:
    ///   - anchors: array of 4 anchors placed from raycasts
    ///   - raycastOrigins: same order as anchors; origin of each ray
    ///   - raycastDirections: same order; original ray direction used to place each anchor
    /// - Returns: a dictionary mapping each original anchor to its back-projected position
    static func backProjectAnchorsToSameDepth(
        anchors: [ARAnchor],
        queries: [ARRaycastQuery]
    ) -> [ARAnchor] {
        guard anchors.count == queries.count else {
            print("❌ Mismatch: anchors and queries count must match.")
            return []
        }

        // Step 1: Calculate distance (t) along each ray (for anchors at indices 0 and 2 only)
        var tValues: [Float] = []
        for i in [0, 2] {
            let anchorPos = anchors[i].transform.columns.3.xyz
            let rayOrigin = queries[i].origin
            let rayDir = simd_normalize(queries[i].direction)
            let displacement = anchorPos - rayOrigin
            let t = simd_dot(displacement, rayDir)
            tValues.append(t)
        }

        // Step 2: Get the minimum t (closest to camera)
        guard let tMin = tValues.min() else {
            print("❌ Failed to compute minimum t")
            return []
        }

        // Step 3: Backproject all rays to that t and create new anchors
        var newAnchors: [ARAnchor] = []

        for i in 0..<anchors.count {
            let rayOrigin = queries[i].origin
            let rayDir = simd_normalize(queries[i].direction)
            let newPos = rayOrigin + tMin * rayDir

            // Construct transform with newPos
            var newTransform = matrix_identity_float4x4
            newTransform.columns.3 = simd_float4(newPos.x, newPos.y, newPos.z, 1.0)

            let newAnchor = ARAnchor(transform: newTransform)
            newAnchors.append(newAnchor)
        }

        return newAnchors
    }
}
