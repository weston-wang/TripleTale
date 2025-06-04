//
//  AnchorUtils.swift
//  TripleTale
//
//  Created by Wes Wang on 6/4/25.
//
import ARKit

struct AnchorUtils {
    
    static func calculateDistanceBetweenAnchors(anchor1: ARAnchor, anchor2: ARAnchor) -> Float {
        let position1 = SIMD3<Float>(anchor1.transform.columns.3.x, anchor1.transform.columns.3.y, anchor1.transform.columns.3.z)
        let position2 = SIMD3<Float>(anchor2.transform.columns.3.x, anchor2.transform.columns.3.y, anchor2.transform.columns.3.z)
        
        return simd_distance(position1, position2)
    }
    
    static func calculateDistanceToObject(_ inputAnchor: ARAnchor) -> Float? {
        let distance = sqrt(inputAnchor.transform.columns.3.x*inputAnchor.transform.columns.3.x + inputAnchor.transform.columns.3.y*inputAnchor.transform.columns.3.y + inputAnchor.transform.columns.3.z*inputAnchor.transform.columns.3.z)
        
        return distance
    }
    
    static func calculateHeightBetweenAnchors(anchor1: ARAnchor, anchor2: ARAnchor) -> Float {
        let position1 = anchor1.transform.columns.3
        let position2 = anchor2.transform.columns.3
        return abs(position1.y - position2.y)
    }

    static func calculateDepthBetweenAnchors(anchor1: ARAnchor, anchor2: ARAnchor) -> Float {
        let position1 = anchor1.transform.columns.3
        let position2 = anchor2.transform.columns.3
        return abs(position1.z - position2.z)
    }

    static func calculateLengthBetweenAnchors(anchor1: ARAnchor, anchor2: ARAnchor) -> Float {
        let position1 = anchor1.transform.columns.3
        let position2 = anchor2.transform.columns.3
        return abs(position1.x - position2.x)
    }
    
    static func position(from anchor: ARAnchor) -> SIMD3<Float> {
        return SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
    }
    
    static func measureHeight( _ cornersAnchors: [ARAnchor],
                        _ aboveAnchor: ARAnchor,
                        _ belowAnchor: ARAnchor ) -> Float {
        let normVector = normalVector(from: cornersAnchors)
        let height = distanceToPlane(from: aboveAnchor, planeAnchor: belowAnchor, normal: normVector!)
        
        return height
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
    
    private static func normalVector(from anchors: [ARAnchor]) -> simd_float3? {
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

    private static func distanceToPlane(from newAnchor: ARAnchor, planeAnchor: ARAnchor, normal: simd_float3) -> Float {
        // Get the positions of the new anchor and one of the plane's anchors
        let pointP = simd_float3(newAnchor.transform.columns.3.x, newAnchor.transform.columns.3.y, newAnchor.transform.columns.3.z)
        let pointA = simd_float3(planeAnchor.transform.columns.3.x, planeAnchor.transform.columns.3.y, planeAnchor.transform.columns.3.z)
        
        // Create a vector from point A (on the plane) to point P (the new anchor)
        let vectorAP = pointP - pointA
        
        // Project vectorAP onto the normal vector to get the distance in the "up" direction
        let distance = simd_dot(vectorAP, normal)
        
        return distance
    }
    
    private static func distanceAlongNormalVector(from anchor: ARAnchor, normal: simd_float3) -> Float {
        // Get the position of the anchor
        let anchorPosition = simd_float3(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
        
        // Project the anchor's position onto the normal vector
        let distance = simd_dot(anchorPosition, normal)
        
        return distance
    }
}
