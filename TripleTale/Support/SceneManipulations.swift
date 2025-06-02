//
//  Manipulations.swift
//  tripletalear
//
//  Created by Wes Wang on 8/18/24.
//

import SceneKit
import ARKit

func createNode(at position: SCNVector3) -> SCNNode {
    let sphere = SCNSphere(radius: 0.01)
    let node = SCNNode(geometry: sphere)
    node.position = position
    node.geometry?.firstMaterial?.diffuse.contents = UIColor.red
    return node
}

func measureDistance(from start: SCNVector3, to end: SCNVector3) -> Float {
    let distance = sqrt(
        pow(end.x - start.x, 2) +
        pow(end.y - start.y, 2) +
        pow(end.z - start.z, 2)
    )
    return distance
}

func addAnchor(_ currentView: ARSCNView, _ point: CGPoint, projectToGround: Bool = false) -> ARAnchor? {
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

func addAnchorClustered(_ currentView: ARSCNView, _ point: CGPoint, rayCount: Int = 100) -> ARAnchor? {
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

func addAnchorWithQuery(
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

//func addAnchor(_ currentView: ARSCNView, _ point: CGPoint) -> ARAnchor? {
//    let hitTestResults = currentView.hitTest(point, types: [.featurePoint, .estimatedHorizontalPlane])
//
//    guard let result = hitTestResults.first else { return nil }
//
//    // Create and add an anchor at the raycast result's position
//    let anchor = ARAnchor(transform: result.worldTransform)
//    currentView.session.add(anchor: anchor)
//
//    return anchor
//}
//
//func addAnchorWithRaycast(_ currentView: ARSCNView, _ point: CGPoint) -> ARAnchor? {
//    // Create a raycast query from the screen point
//    guard let raycastQuery = currentView.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any) else { return nil }
//
//    // Perform the raycast
//    let raycastResults = currentView.session.raycast(raycastQuery)
//
//    // Check if we have a valid result
//    guard let result = raycastResults.first else { return nil }
//
//    // Create and add an anchor at the raycast result's position
//    let anchor = ARAnchor(transform: result.worldTransform)
//    currentView.session.add(anchor: anchor)
//
//    return anchor
//}

//func getVertices(_ currentView: ARSCNView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> ([ARAnchor], [ARRaycastQuery]) {
func getVertices(_ currentView: ARSCNView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> [ARAnchor] {
    var verticesAnchors: [ARAnchor] = []
//    var verticesQueries: [ARRaycastQuery] = []

    for vertex in normalizedVertices {
        // Convert the normalized vertex to a screen position
        let vertexOnScreen = getScreenPosition(currentView, vertex.x, vertex.y, capturedImageSize)
                
        // Use raycasting to add an anchor at the screen position
//        if let vertexAnchor = addAnchor(currentView, vertexOnScreen) {
        if let vertexAnchor = addAnchorUsingSceneDepth(currentView, at: vertexOnScreen, capturedImageSize) {
            verticesAnchors.append(vertexAnchor)
        }
    }
    
//    return (verticesAnchors, verticesQueries)
    return verticesAnchors
}

func getScreenPosition(_ currentView: ARSCNView, _ normalizedX: CGFloat, _ normalizedY: CGFloat, _ capturedImageSize: CGSize) -> CGPoint {
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

func getVerticesCenter(
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

func getAngledCorners(_ currentView: ARSCNView, _ corners: [CGPoint], _ capturedImageSize: CGSize) -> [ARAnchor] {
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

func createCentroidAnchor(from cornerAnchors: [ARAnchor]) -> ARAnchor? {
    // Ensure there are at least 4 anchors
    guard cornerAnchors.count >= 4 else {
        return nil
    }

    // Get the positions of the anchors
    var lTPos = position(from: cornerAnchors[0])
    var rTPos = position(from: cornerAnchors[1])
    var lBPos = position(from: cornerAnchors[2])
    var rBPos = position(from: cornerAnchors[3])
    
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
        let scaledPosition = scalePoint(point: simd_float3(position.x, position.y, position.z), center: center, verticalScaleFactor: verticalScaleFactor, horizontalScaleFactor: horizontalScaleFactor)
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


// Adds an anchor using scene depth information at the given screen point.
func addAnchorUsingSceneDepth(_ sceneView: ARSCNView, at screenPoint: CGPoint, _ capturedImageSize: CGSize) -> ARAnchor? {
    guard let frame = sceneView.session.currentFrame,
          let depthMap = frame.sceneDepth?.depthMap else {
        return nil
    }

    let viewSize = sceneView.bounds.size
    let depthWidth = CVPixelBufferGetWidth(depthMap)  // e.g., 256
    let depthHeight = CVPixelBufferGetHeight(depthMap) // e.g., 192

    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    let baseAddress = CVPixelBufferGetBaseAddress(depthMap)!
    let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
    
    print("about to get x,y")

    guard let (x, y) = normalizedImagePointToDepthMapIndex(normalizedPoint: screenPoint,
        capturedImageSize: capturedImageSize,
        depthMapSize: CGSize(width: depthWidth, height: depthHeight)
    ) else {
        return nil
    }

    print("depth (x,y): (\(x), \(y))")
    
    let depthIndex = y * depthWidth + x
    let depthValue = floatBuffer[depthIndex]  // in meters
    
    // Normalize screen coordinates and combine with depth to form a 3D point in view space
    let normalizedX = Float(screenPoint.x / viewSize.width)
    let normalizedY = Float(screenPoint.y / viewSize.height)
    let viewSpacePoint = vector_float3(normalizedX, normalizedY, depthValue)

    let worldPosition = sceneView.unprojectPoint(
        SCNVector3(
            x: Float(viewSpacePoint.x),
            y: Float(viewSpacePoint.y),
            z: Float(viewSpacePoint.z)
        )
    )
    
    var transform = matrix_identity_float4x4
    transform.columns.3 = SIMD4<Float>(Float(worldPosition.x), Float(worldPosition.y), Float(worldPosition.z), 1.0)

    let anchor = ARAnchor(transform: transform)
    sceneView.session.add(anchor: anchor)
    return anchor
}

// Maps normalized (x, y) coordinates from captured image space to depth map pixel coordinates,
// matching getScreenPosition's aspect correction and applying portrait-to-landscape rotation.
func normalizedImagePointToDepthMapIndex(
    normalizedPoint: CGPoint,
    capturedImageSize: CGSize,
    depthMapSize: CGSize
) -> (x: Int, y: Int)? {
    let imageWidth = capturedImageSize.width
    let imageHeight = capturedImageSize.height
    let depthWidth = depthMapSize.width
    let depthHeight = depthMapSize.height

    let imageAspectRatio = imageWidth / imageHeight
    let depthAspectRatio = depthWidth / depthHeight

    var adjustedX = normalizedPoint.x
    var adjustedY = normalizedPoint.y

    print("🔍 imageAspectRatio: \(imageAspectRatio), depthAspectRatio: \(depthAspectRatio)")

    if imageAspectRatio > depthAspectRatio {
        // Captured image is wider — horizontal cropping in depth map
        let scaleFactor = depthHeight / imageHeight
        let scaledImageWidth = imageWidth * scaleFactor
        let croppedWidth = (scaledImageWidth - depthWidth) / 2 / scaledImageWidth
        print("📐 scaleFactor (wider): \(scaleFactor), scaledImageWidth: \(scaledImageWidth), croppedWidth: \(croppedWidth)")
        adjustedX = (normalizedPoint.x - croppedWidth) / (1 - 2 * croppedWidth)
    } else {
        // Captured image is taller — vertical cropping in depth map
        let scaleFactor = depthWidth / imageWidth
        let scaledImageHeight = imageHeight * scaleFactor
        let croppedHeight = (scaledImageHeight - depthHeight) / 2 / scaledImageHeight
        print("📐 scaleFactor (taller): \(scaleFactor), scaledImageHeight: \(scaledImageHeight), croppedHeight: \(croppedHeight)")
        adjustedY = (normalizedPoint.y - croppedHeight) / (1 - 2 * croppedHeight)
    }

    print("🎯 Adjusted normalizedX: \(adjustedX), normalizedY: \(adjustedY)")

    // Rotate portrait → landscape
    let rotatedX = adjustedY
    let rotatedY = 1.0 - adjustedX

    print("🔁 Rotated to landscape: x: \(rotatedX), y: \(rotatedY)")

    let x = Int(round(rotatedX * depthWidth))
    let y = Int(round(rotatedY * depthHeight))

    print("🧩 Depth map index: (\(x), \(y))")

    guard x >= 0, x < Int(depthWidth), y >= 0, y < Int(depthHeight) else {
        print("❌ Index out of bounds")
        return nil
    }

    return (x, y)
}
