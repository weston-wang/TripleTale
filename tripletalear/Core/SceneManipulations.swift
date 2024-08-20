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

func addAnchorWithRaycast(_ currentView: ARSCNView, _ point: CGPoint) -> ARAnchor? {
    // Create a raycast query from the screen point
    guard let raycastQuery = currentView.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any) else {
        return nil
    }
    
    // Perform the raycast
    let raycastResults = currentView.session.raycast(raycastQuery)
    
    // Check if we have a valid result
    guard let result = raycastResults.first else {
        return nil
    }
    
    // Create and add an anchor at the raycast result's position
    let anchor = ARAnchor(transform: result.worldTransform)
    currentView.session.add(anchor: anchor)
    
    return anchor
}

func buildRealWorldVerticesAnchors(_ currentView: ARSCNView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> ([ARAnchor]) {
    var verticesAnchors = getVertices(currentView, normalizedVertices, capturedImageSize)
    
    return verticesAnchors
}

func getVertices(_ currentView: ARSCNView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> [ARAnchor] {
    var verticesAnchors: [ARAnchor] = []
    
    for vertex in normalizedVertices {
        // Convert the normalized vertex to a screen position
        let vertexOnScreen = getScreenPosition(currentView, vertex.x, vertex.y, capturedImageSize)
        
        print("on screen: \(vertexOnScreen)")
        
        // Use raycasting to add an anchor at the screen position
        if let vertexAnchor = addAnchorWithRaycast(currentView, vertexOnScreen) {
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
