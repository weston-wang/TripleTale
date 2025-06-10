//
//  AnchorUtils.swift
//  TripleTale
//
//  Created by Wes Wang on 6/4/25.
//
import ARKit

struct AnchorUtils {
    
    static func getScreenPosition(_ currentView: ARSCNView, _ normalizedX: CGFloat, _ normalizedY: CGFloat, _ capturedImageSize: CGSize) -> CGPoint {
        let imageWidth = capturedImageSize.width
        let imageHeight = capturedImageSize.height
        
        let viewWidth = currentView.bounds.width
        let viewHeight = currentView.bounds.height
        
        let imageAspectRatio = imageWidth / imageHeight
        let viewAspectRatio = viewWidth / viewHeight
        
        var adjustedX = normalizedX
        var adjustedY = normalizedY
        
        if imageAspectRatio > viewAspectRatio {
            // Image is wider than the view
            let scaleFactor = viewHeight / imageHeight
            let scaledImageWidth = imageWidth * scaleFactor
            let croppedWidth = (scaledImageWidth - viewWidth) / 2 / scaledImageWidth
            
            adjustedX = (normalizedX - croppedWidth) / (1 - 2 * croppedWidth)
        } else {
            // View is wider than the image
            let scaleFactor = viewWidth / imageWidth
            let scaledImageHeight = imageHeight * scaleFactor
            let croppedHeight = (scaledImageHeight - viewHeight) / 2 / scaledImageHeight
            
            adjustedY = (normalizedY - croppedHeight) / (1 - 2 * croppedHeight)
        }
        
        // Map the adjusted normalized coordinates to the current view bounds
        let actualPosition = CGPoint(
            x: adjustedX * viewWidth,
            y: (1 - adjustedY) * viewHeight  // Adjusting for UIKit's coordinate system
        )
        
        return actualPosition
    }

    
    static func getVertices(_ currentView: ARSCNView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> [ARAnchor] {
        var verticesAnchors: [ARAnchor] = []
    //    var verticesQueries: [ARRaycastQuery] = []

        for vertex in normalizedVertices {
            // Convert the normalized vertex to a screen position
            let vertexOnScreen = getScreenPosition(currentView, vertex.x, vertex.y, capturedImageSize)
                    
            // Use raycasting to add an anchor at the screen position
            if let vertexAnchor = addAnchorUsingSceneDepth(currentView, at: vertexOnScreen, capturedImageSize) {
                verticesAnchors.append(vertexAnchor)
            }
        }
        
    //    return (verticesAnchors, verticesQueries)
        return verticesAnchors
    }
    
    static func getVerticesCenter(
        _ currentView: ARSCNView,
        _ normalizedVertices: [CGPoint],
        _ capturedImageSize: CGSize,
        _ planeAnchor: ARPlaneAnchor) -> ARAnchor? {
        let centroid = CGPoint(
            x: (normalizedVertices[0].x + normalizedVertices[1].x + normalizedVertices[2].x + normalizedVertices[3].x) / 4,
            y: (normalizedVertices[0].y + normalizedVertices[1].y + normalizedVertices[2].y + normalizedVertices[3].y) / 4
        )
        
        let centroidOnScreen = getScreenPosition(currentView, centroid.x, centroid.y, capturedImageSize)

        // TODO: add sanity check against ground plane
        let centroidAnchor = addAnchor(currentView, centroidOnScreen, projectToGround: false)

        return centroidAnchor
    }

    static func getAngledCorners(_ currentView: ARSCNView, _ corners: [CGPoint], _ capturedImageSize: CGSize) -> [ARAnchor] {
        var cornerAnchors: [ARAnchor] = []
        
        let leftTop = getScreenPosition(currentView, corners[0].x, corners[0].y, capturedImageSize)
        let rightTop = getScreenPosition(currentView, corners[1].x, corners[1].y, capturedImageSize)
        let leftBottom = getScreenPosition(currentView, corners[2].x, corners[2].y, capturedImageSize)
        let rightBottom = getScreenPosition(currentView, corners[3].x, corners[3].y, capturedImageSize)
        
        // Attempt to add anchors, return an empty array if any fail
        guard let anchorLT = addAnchor(currentView, leftTop),
              let anchorRT = addAnchor(currentView, rightTop),
              let anchorLB = addAnchor(currentView, leftBottom),
              let anchorRB = addAnchor(currentView, rightBottom) else {
            print("❌ Failed to add one or more anchors in getAngledCorners")
            return []
        }

        cornerAnchors.append(anchorLT)
        cornerAnchors.append(anchorRT)
        cornerAnchors.append(anchorLB)
        cornerAnchors.append(anchorRB)

        return cornerAnchors
    }
    
    static func createCentroidAnchor(from cornerAnchors: [ARAnchor]) -> ARAnchor? {
        // Ensure there are at least 4 anchors
        guard cornerAnchors.count >= 4 else {
            return nil
        }

        // Get the positions of the anchors
        var lTPos = AnchorUtils.position(from: cornerAnchors[0])
        var rTPos = AnchorUtils.position(from: cornerAnchors[1])
        var lBPos = AnchorUtils.position(from: cornerAnchors[2])
        var rBPos = AnchorUtils.position(from: cornerAnchors[3])
        
        // Calculate the center of the rectangle
        let center = (lTPos + rTPos + lBPos + rBPos) / 4.0
        
        // Calculate vectors from the center to each corner
        let lTVec = lTPos - center
        let rTVec = rTPos - center
        let lBVec = lBPos - center
        let rBVec = rBPos - center
        
        // Recalculate positions based on the nudged vectors
        lTPos = center + lTVec
        rTPos = center + rTVec
        lBPos = center + lBVec
        rBPos = center + rBVec
        
        // Calculate the centroid of the nudged positions
        let centroid = (lTPos + rTPos + lBPos + rBPos) / 4.0
        
        // Create a new transform with the centroid position
        var centroidTransform = matrix_identity_float4x4
        centroidTransform.columns.3 = SIMD4<Float>(centroid.x, centroid.y, centroid.z, 1.0)
        
        // Create and return a new ARAnchor at the centroid position
        return ARAnchor(transform: centroidTransform)
    }

    func stretchVertices(_ anchors: [ARAnchor], verticalScaleFactor: Float, horizontalScaleFactor: Float) -> [ARAnchor] {
        var updatedVerticesAnchors: [ARAnchor] = []

        // Calculate the center of the quadrilateral
        let centerX = (anchors[0].transform.columns.3.x + anchors[2].transform.columns.3.x) / 2.0
        let centerY = (anchors[0].transform.columns.3.y + anchors[2].transform.columns.3.y) / 2.0
        let centerZ = (anchors[0].transform.columns.3.z + anchors[2].transform.columns.3.z) / 2.0

        let center = simd_float3(x: centerX, y: centerY, z: centerZ)

        // Update the anchors
        for i in 0..<anchors.count {
            var position = anchors[i].transform.columns.3
            let scaledPosition = PointUtils.scalePoint(point: simd_float3(position.x, position.y, position.z), center: center, verticalScaleFactor: verticalScaleFactor, horizontalScaleFactor: horizontalScaleFactor)
            position = simd_float4(scaledPosition.x, scaledPosition.y, scaledPosition.z, 1.0)
            
            // Create a new transform with the updated position
            var newTransform = anchors[i].transform
            newTransform.columns.3 = position
            
            // Update the anchor with the new transform
            let updatedAnchor = ARAnchor(transform: newTransform)
            
            updatedVerticesAnchors.append(updatedAnchor)
        }
        
        return updatedVerticesAnchors
    }

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
    
    static func createNode(at position: SCNVector3) -> SCNNode {
        let sphere = SCNSphere(radius: 0.01)
        let node = SCNNode(geometry: sphere)
        node.position = position
        node.geometry?.firstMaterial?.diffuse.contents = UIColor.red
        return node
    }
    
    // MARK: Private Functions
    private static func addAnchor(_ currentView: ARSCNView, _ point: CGPoint, projectToGround: Bool = false) -> ARAnchor? {
    //    let raycastMethod:ARRaycastQuery.Target = .existingPlaneInfinite
        let raycastMethod:ARRaycastQuery.Target = .estimatedPlane
        
        // use estimatedPlane for dots on fish, existingPlaneInfinite for projection on ground
        if let raycastQuery = currentView.raycastQuery(from: point, allowing: raycastMethod, alignment: .any) {
            let raycastResults = currentView.session.raycast(raycastQuery)
            
            if let result = raycastResults.first {
                let anchor = ARAnchor(transform: result.worldTransform)
                currentView.session.add(anchor: anchor)
                return anchor
            }
        }
        
        print("Raycast failed: falling back to hitTest")
        // Fallback: Use feature point hit-test if raycasting fails
        // Confirmed: fallback uses .featurePoint as desired
        let hitTestResults = currentView.hitTest(point, types: [.featurePoint, .estimatedHorizontalPlane, .estimatedVerticalPlane])
        
        if let result = hitTestResults.first {
            let anchor = ARAnchor(transform: result.worldTransform)
            currentView.session.add(anchor: anchor)
            return anchor
        }
        
        return nil
    }
    
    // Adds an anchor using scene depth information at the given screen point.
    private static func addAnchorUsingSceneDepth(_ sceneView: ARSCNView, at screenPoint: CGPoint, _ capturedImageSize: CGSize) -> ARAnchor? {
        guard let frame = sceneView.session.currentFrame else {
            return nil
        }

        guard let depthMap = frame.sceneDepth?.depthMap ?? frame.smoothedSceneDepth?.depthMap else {
            return nil
        }

        let depthWidth = CVPixelBufferGetWidth(depthMap)  // e.g., 256
        let depthHeight = CVPixelBufferGetHeight(depthMap) // e.g., 192

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        
        print("📱 sceneView size: \(sceneView.bounds.size)")
        print("getting depth for \(screenPoint)")
        

        
        guard let (x, y) = imagePointToDepthMapIndex(screenPoint: screenPoint,
            capturedImageSize: sceneView.bounds.size,
            depthMapSize: CGSize(width: depthWidth, height: depthHeight)
        ) else {
            return nil
        }

        print("depth map size: \(depthWidth) x \(depthHeight)")
        let depthIndex = y * depthWidth + x
        let depthValue = floatBuffer[depthIndex]  // in meters
        
        print("depth at (x,y): (\(x), \(y)): \(depthValue)")

        
        // Perform a basic hitTest to get a 3D direction
        let hitResults = sceneView.hitTest(screenPoint, types: [.featurePoint])
        guard let result = hitResults.first else {
            return nil
        }

        let origin = frame.camera.transform.columns.3
        let direction = result.worldTransform.columns.3 - origin

        let unitDir = simd_normalize(simd_float3(direction.x, direction.y, direction.z))
        let worldPos = simd_float3(origin.x, origin.y, origin.z) + unitDir * depthValue

        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(worldPos.x, worldPos.y, worldPos.z, 1.0)

        let anchor = ARAnchor(transform: transform)
        sceneView.session.add(anchor: anchor)
        return anchor
    }

    private static func addAnchorClustered(_ currentView: ARSCNView, _ point: CGPoint, rayCount: Int = 100) -> ARAnchor? {
        // Perform 100 jittered ray/hit tests, keep only the closest result
        let raycastMethod: ARRaycastQuery.Target = .estimatedPlane
        let maxJitter: CGFloat = 2.0  // jitter in pixels

        var closestTransform: simd_float4x4?
        var closestDistance = Float.infinity

        for _ in 0..<rayCount {
            let jitteredPoint = CGPoint(
                x: point.x + CGFloat.random(in: -maxJitter...maxJitter),
                y: point.y + CGFloat.random(in: -maxJitter...maxJitter)
            )

            var transform: simd_float4x4?

            if let query = currentView.raycastQuery(from: jitteredPoint, allowing: raycastMethod, alignment: .any),
               let rayResult = currentView.session.raycast(query).first {
                transform = rayResult.worldTransform
            } else {
                // Fallback: Use feature point hit-test with the jittered point
                let hitTestResults = currentView.hitTest(jitteredPoint, types: [.featurePoint])
                if let featureResult = hitTestResults.first {
                    transform = featureResult.worldTransform
                }
            }

            if let transform = transform {
                let distance = simd_length(transform.columns.3)
                if distance < closestDistance {
                    closestDistance = distance
                    closestTransform = transform
                }
            }
        }

        if let transform = closestTransform {
            let anchor = ARAnchor(transform: transform)
            currentView.session.add(anchor: anchor)
            return anchor
        }

        return nil
    }

    private static func addAnchorWithQuery(
        _ currentView: ARSCNView,
        _ point: CGPoint,
        projectToGround: Bool = false
    ) -> (anchor: ARAnchor, query: ARRaycastQuery)? {
        let raycastMethod: ARRaycastQuery.Target = .estimatedPlane

        if let raycastQuery = currentView.raycastQuery(from: point, allowing: raycastMethod, alignment: .any) {
            let raycastResults = currentView.session.raycast(raycastQuery)
            if let result = raycastResults.first {
                let anchor = ARAnchor(transform: result.worldTransform)
                currentView.session.add(anchor: anchor)
                return (anchor, raycastQuery)
            }
            // Fallback: Use feature point hit-test if raycasting fails
            let hitTestResults = currentView.hitTest(point, types: [.featurePoint])
            if let result = hitTestResults.first {
                let fallbackAnchor = ARAnchor(transform: result.worldTransform)
                currentView.session.add(anchor: fallbackAnchor)
                return (fallbackAnchor, raycastQuery)
            }
        }
        return nil
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
    // Maps normalized (x, y) coordinates from captured image space to depth map pixel coordinates,
    // matching getScreenPosition's aspect correction and applying portrait-to-landscape rotation.
    private static func imagePointToDepthMapIndex(screenPoint: CGPoint, capturedImageSize: CGSize, depthMapSize: CGSize) -> (x: Int, y: Int)? {
        let translated = DepthUtils.convertImageAPointToImageB(xScreen: screenPoint.x, yScreen: screenPoint.y, screenSize: capturedImageSize)
        
        // Rotate portrait → landscape
        let rotatedX = Int(translated.y)
        let rotatedY = 192 - 1 - Int(translated.x)

        print("points before rotation: (\(translated))")
        return (rotatedX, rotatedY)
    }

}
