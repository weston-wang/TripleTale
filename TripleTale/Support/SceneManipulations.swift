//
//  Manipulations.swift
//  tripletalear
//
//  Created by Wes Wang on 8/18/24.
//

import SceneKit
import ARKit



//func getVertices(_ currentView: ARSCNView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> ([ARAnchor], [ARRaycastQuery]) {
func getVertices(_ currentView: ARSCNView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> [ARAnchor] {
    var verticesAnchors: [ARAnchor] = []
//    var verticesQueries: [ARRaycastQuery] = []

    for vertex in normalizedVertices {
        // Convert the normalized vertex to a screen position
        let vertexOnScreen = getScreenPosition(currentView, vertex.x, vertex.y, capturedImageSize)
                
        // Use raycasting to add an anchor at the screen position
//        if let vertexAnchor = AnchorUtils.addAnchor(currentView, vertexOnScreen) {
        if let vertexAnchor = AnchorUtils.addAnchorUsingSceneDepth(currentView, at: vertexOnScreen, capturedImageSize) {
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
    let centroidAnchor = AnchorUtils.addAnchor(currentView, centroidOnScreen, projectToGround: false)

    return centroidAnchor
}

func getAngledCorners(_ currentView: ARSCNView, _ corners: [CGPoint], _ capturedImageSize: CGSize) -> [ARAnchor] {
    var cornerAnchors: [ARAnchor] = []
    
    let leftTop = getScreenPosition(currentView, corners[0].x, corners[0].y, capturedImageSize)
    let rightTop = getScreenPosition(currentView, corners[1].x, corners[1].y, capturedImageSize)
    let leftBottom = getScreenPosition(currentView, corners[2].x, corners[2].y, capturedImageSize)
    let rightBottom = getScreenPosition(currentView, corners[3].x, corners[3].y, capturedImageSize)
    
    // Attempt to add anchors, return an empty array if any fail
    guard let anchorLT = AnchorUtils.addAnchor(currentView, leftTop),
          let anchorRT = AnchorUtils.addAnchor(currentView, rightTop),
          let anchorLB = AnchorUtils.addAnchor(currentView, leftBottom),
          let anchorRB = AnchorUtils.addAnchor(currentView, rightBottom) else {
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


