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

func addAnchor(_ currentView: ARSCNView, _ point: CGPoint) -> ARAnchor? {
    let hitTestResults = currentView.hitTest(point, types: [.featurePoint, .estimatedHorizontalPlane])
    
    guard let result = hitTestResults.first else { return nil }
   
    // Create and add an anchor at the raycast result's position
    let anchor = ARAnchor(transform: result.worldTransform)
    currentView.session.add(anchor: anchor)
    
    return anchor
}

func addAnchorWithRaycast(_ currentView: ARSCNView, _ point: CGPoint) -> ARAnchor? {
    // Create a raycast query from the screen point
    guard let raycastQuery = currentView.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any) else { return nil }
    
    // Perform the raycast
    let raycastResults = currentView.session.raycast(raycastQuery)
    
    // Check if we have a valid result
    guard let result = raycastResults.first else { return nil }
    
    // Create and add an anchor at the raycast result's position
    let anchor = ARAnchor(transform: result.worldTransform)
    currentView.session.add(anchor: anchor)
    
    return anchor
}

func getVertices(_ currentView: ARSCNView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> [ARAnchor] {
    var verticesAnchors: [ARAnchor] = []
    
    for vertex in normalizedVertices {
        // Convert the normalized vertex to a screen position
        let vertexOnScreen = getScreenPosition(currentView, vertex.x, vertex.y, capturedImageSize)
                
        // Use raycasting to add an anchor at the screen position
        if let vertexAnchor = addAnchor(currentView, vertexOnScreen) {
            verticesAnchors.append(vertexAnchor)
        }
    }
    
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

func getVerticesCenter(_ currentView: ARSCNView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> ARAnchor? {
    let centroid = CGPoint(
        x: (normalizedVertices[0].x + normalizedVertices[1].x + normalizedVertices[2].x + normalizedVertices[3].x) / 4,
        y: (normalizedVertices[0].y + normalizedVertices[1].y + normalizedVertices[2].y + normalizedVertices[3].y) / 4
    )
    
    let centroidOnScreen = getScreenPosition(currentView, centroid.x, centroid.y, capturedImageSize)

    let centroidAnchor = addAnchor(currentView, centroidOnScreen)

    return centroidAnchor
}

func getAngledCorners(_ currentView: ARSCNView, _ corners: [CGPoint], _ capturedImageSize: CGSize) -> [ARAnchor] {
    var cornerAnchors: [ARAnchor] = []
    
    let leftTop = getScreenPosition(currentView, corners[0].x, corners[0].y, capturedImageSize)
    let anchorLT = addAnchor(currentView, leftTop)!

    let rightTop = getScreenPosition(currentView, corners[1].x, corners[1].y, capturedImageSize)
    let anchorRT = addAnchor(currentView, rightTop)!
    
    let leftBottom = getScreenPosition(currentView, corners[2].x, corners[2].y, capturedImageSize)
    let anchorLB = addAnchor(currentView, leftBottom)!
    
    let rightBottom = getScreenPosition(currentView, corners[3].x, corners[3].y, capturedImageSize)
    let anchorRB = addAnchor(currentView, rightBottom)!
    
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
