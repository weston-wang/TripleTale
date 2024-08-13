//
//  SceneManipulations.swift
//  TripleTale
//
//  Created by Wes Wang on 7/29/24.
//  Copyright © 2024 Apple. All rights reserved.
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

func getScreenPosition(_ currentView: ARSKView, _ normalizedX: CGFloat, _ normalizedY: CGFloat, _ capturedImageSize: CGSize) -> CGPoint {
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

func addAnchor(_ currentView: ARSKView, _ point: CGPoint) -> ARAnchor {
   let newAnchor: ARAnchor
   
   let hitTestResults = currentView.hitTest(point, types: [.featurePoint, .estimatedHorizontalPlane])
   let result = hitTestResults.first
   newAnchor = ARAnchor(transform: result!.worldTransform)
   
   return newAnchor
}

func getVertices(_ currentView: ARSKView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> [ARAnchor] {
    var verticesAnchors: [ARAnchor] = []
    
    
    for vertex in normalizedVertices {
        let vertexOnScreen = getScreenPosition(currentView, vertex.x, vertex.y, capturedImageSize)
        let vertexAnchor = addAnchor(currentView, vertexOnScreen)
        
        verticesAnchors.append(vertexAnchor)
    }
    
    return verticesAnchors
}

func getVerticesCenter(_ currentView: ARSKView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> ARAnchor {
    let centroid = CGPoint(
        x: (normalizedVertices[0].x + normalizedVertices[1].x + normalizedVertices[2].x + normalizedVertices[3].x) / 4,
        y: (normalizedVertices[0].y + normalizedVertices[1].y + normalizedVertices[2].y + normalizedVertices[3].y) / 4
    )
    
    let centroidOnScreen = getScreenPosition(currentView, centroid.x, centroid.y, capturedImageSize)

    let centroidAnchor = addAnchor(currentView, centroidOnScreen)

    return centroidAnchor
}

func getMidpoints(_ currentView: ARSKView, _ boundingBox: CGRect, _ capturedImageSize: CGSize) -> [ARAnchor] {
    var cornerAnchors: [ARAnchor] = []
    
    let leftMiddle = getScreenPosition(currentView, boundingBox.origin.x, boundingBox.origin.y + boundingBox.size.height / 2, capturedImageSize)
    let anchorLeft = addAnchor(currentView, leftMiddle)

    let rightMiddle = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width, boundingBox.origin.y + boundingBox.size.height / 2, capturedImageSize)
    let anchorRight = addAnchor(currentView, rightMiddle)
    
    let topMiddle = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width / 2, boundingBox.origin.y, capturedImageSize)
    let anchorTop = addAnchor(currentView, topMiddle)
    
    let bottomMiddle = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width / 2, boundingBox.origin.y + boundingBox.size.height, capturedImageSize)
    let anchorBottom = addAnchor(currentView, bottomMiddle)
    
    let center = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width / 2, boundingBox.origin.y + boundingBox.size.height / 2, capturedImageSize)
    let anchorCenter = addAnchor(currentView, center)
    
    let reference = getScreenPosition(currentView, boundingBox.origin.x, boundingBox.origin.y, capturedImageSize)
    let anchorReference = addAnchor(currentView, reference)
    
    cornerAnchors.append(anchorLeft)
    cornerAnchors.append(anchorRight)
    cornerAnchors.append(anchorTop)
    cornerAnchors.append(anchorBottom)
    cornerAnchors.append(anchorCenter)
    cornerAnchors.append(anchorReference)

    return cornerAnchors
}

func getCorners(_ currentView: ARSKView, _ boundingBox: CGRect, _ capturedImageSize: CGSize) -> [ARAnchor] {
    var cornerAnchors: [ARAnchor] = []
    
    let leftTop = getScreenPosition(currentView, boundingBox.origin.x, boundingBox.origin.y + boundingBox.size.height, capturedImageSize)
    let anchorLT = addAnchor(currentView, leftTop)

    let rightTop = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width, boundingBox.origin.y + boundingBox.size.height, capturedImageSize)
    let anchorRT = addAnchor(currentView, rightTop)
    
    let leftBottom = getScreenPosition(currentView, boundingBox.origin.x, boundingBox.origin.y, capturedImageSize)
    let anchorLB = addAnchor(currentView, leftBottom)
    
    let rightBottom = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width, boundingBox.origin.y, capturedImageSize)
    let anchorRB = addAnchor(currentView, rightBottom)
    
    cornerAnchors.append(anchorLT)
    cornerAnchors.append(anchorRT)
    cornerAnchors.append(anchorLB)
    cornerAnchors.append(anchorRB)

    return cornerAnchors
}

func getAngledCorners(_ currentView: ARSKView, _ corners: [CGPoint], _ capturedImageSize: CGSize) -> [ARAnchor] {
    var cornerAnchors: [ARAnchor] = []
    
    let leftTop = getScreenPosition(currentView, corners[0].x, corners[0].y, capturedImageSize)
    let anchorLT = addAnchor(currentView, leftTop)

    let rightTop = getScreenPosition(currentView, corners[1].x, corners[1].y, capturedImageSize)
    let anchorRT = addAnchor(currentView, rightTop)
    
    let leftBottom = getScreenPosition(currentView, corners[2].x, corners[2].y, capturedImageSize)
    let anchorLB = addAnchor(currentView, leftBottom)
    
    let rightBottom = getScreenPosition(currentView, corners[3].x, corners[3].y, capturedImageSize)
    let anchorRB = addAnchor(currentView, rightBottom)
    
    cornerAnchors.append(anchorLT)
    cornerAnchors.append(anchorRT)
    cornerAnchors.append(anchorLB)
    cornerAnchors.append(anchorRB)

    return cornerAnchors
}

func getTailAnchor(_ currentView: ARSKView, _ boundingBox: CGRect, _ capturedImageSize: CGSize) -> ARAnchor {
    
    let bottomMiddle = getScreenPosition(currentView, boundingBox.origin.x + boundingBox.size.width / 2, boundingBox.origin.y + boundingBox.size.height * CGFloat(0.1), capturedImageSize)
    let anchorBottomShifted = addAnchor(currentView, bottomMiddle)
    
    return anchorBottomShifted
}

func transformHeightAnchor(ref refAnchor: ARAnchor, cen centerAnchor: ARAnchor) -> ARAnchor {
    let anchor1Transform = refAnchor.transform
    let anchor1Position = SIMD3<Float>(anchor1Transform.columns.3.x, anchor1Transform.columns.3.y, anchor1Transform.columns.3.z)

    let anchor2Transform = centerAnchor.transform
    let anchor2Position = SIMD3<Float>(anchor2Transform.columns.3.x, anchor2Transform.columns.3.y, anchor2Transform.columns.3.z)

    var newTransform = anchor2Transform  // Start with the current transform
    newTransform.columns.3.x = anchor1Position.x
    newTransform.columns.3.y = anchor2Position.y
    newTransform.columns.3.z = anchor1Position.z  // If you want to match Z as well
    
    return ARAnchor(transform: newTransform)
}

func createNudgedCentroidAnchor(from cornerAnchors: [ARAnchor], nudgePercentage: Float) -> ARAnchor? {
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
    var lTVec = lTPos - center
    var rTVec = rTPos - center
    var lBVec = lBPos - center
    var rBVec = rBPos - center
    
    // Nudge each vector by the specified percentage
    lTVec *= (1.0 + nudgePercentage)
    rTVec *= (1.0 + nudgePercentage)
    lBVec *= (1.0 + nudgePercentage)
    rBVec *= (1.0 + nudgePercentage)
    
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

func findAnchors(_ fishBoundingBox: CGRect, _ imageSize: CGSize, _ currentView: ARSKView, _ isForward: Bool) -> (ARAnchor?, [ARAnchor], Float) {
    var centroidAnchor: ARAnchor?
    var midpointAnchors: [ARAnchor]
    
    var useBoundingBox: CGRect
    
    var nudgeRate: Float = 0.0
    
    if !isForward {
        useBoundingBox = fishBoundingBox
        
        // calculate centroid beneath fish, will fail if not all corners available
        let cornerAnchors = getCorners(currentView, fishBoundingBox, imageSize)
        centroidAnchor = createNudgedCentroidAnchor(from: cornerAnchors, nudgePercentage: 0.1)

    } else {
        nudgeRate = 0.1
        
        let tightFishBoundingBox = nudgeBoundingBox(fishBoundingBox,nudgeRate)
        useBoundingBox = tightFishBoundingBox

        centroidAnchor = getTailAnchor(currentView, tightFishBoundingBox, imageSize)
    }
    
    if centroidAnchor != nil {
        // interact with AR world and define anchor points
        midpointAnchors = getMidpoints(currentView, useBoundingBox, imageSize)
        
        return(centroidAnchor, midpointAnchors, nudgeRate)
    } else {
        return(nil, [], nudgeRate)
    }
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

func createUnderneathCentroidAnchor(from verticesAnchors: [ARAnchor]) -> ARAnchor {
    let stretchedAnchors = stretchVertices(verticesAnchors, verticalScaleFactor: 1.35, horizontalScaleFactor: 1.35)
    
    // Get the positions of the anchors
    let leftPos = position(from: stretchedAnchors[0])
    let topPos = position(from: stretchedAnchors[1])
    let rightPos = position(from: stretchedAnchors[2])
    let bottomPos = position(from: stretchedAnchors[3])

    // Calculate the centroid
    let meanCoord = (topPos + rightPos + bottomPos + leftPos) / 4.0
    let minY =  [leftPos.y, topPos.y, rightPos.y, bottomPos.y].min()
    
    // Create a new transform with the centroid position
    var centroidTransform = matrix_identity_float4x4
    centroidTransform.columns.3 = SIMD4<Float>(meanCoord.x, minY!, meanCoord.z, 1.0)

    // Create and return a new ARAnchor at the centroid position
    return ARAnchor(transform: centroidTransform)
}

func buildCurvatureAnchors(_ startPos: CGPoint, _ endPos: CGPoint, _ currentView:ARSKView, _ capturedImageSize: CGSize) -> [ARAnchor] {
    var curvatureAnchors: [ARAnchor] = []
    
    let heightPoints = generateEvenlySpacedPoints(from: startPos, to: endPos, count: 30)
    
    for point in heightPoints {
        let pointOnScreen = getScreenPosition(currentView, point.x, point.y, capturedImageSize)
        let placedAnchor = addAnchor(currentView, pointOnScreen)
        
        curvatureAnchors.append(placedAnchor)
    }
        
    return curvatureAnchors
}

func buildRealWorldVerticesAnchors(_ currentView: ARSKView, _ normalizedVertices: [CGPoint], _ capturedImageSize: CGSize) -> ([ARAnchor], ARAnchor, ARAnchor, [ARAnchor]) {
    var verticesAnchors = getVertices(currentView, normalizedVertices, capturedImageSize)
    
    let centroidAboveAnchor = getVerticesCenter(currentView, normalizedVertices, capturedImageSize)
    
//    let centroidBelowAnchor = createUnderneathCentroidAnchor(from: verticesAnchors)

    let corners = calculateRectangleCorners(normalizedVertices, 0.0, 0.7) // first one is tall, second is wide
    let cornerAnchors = getAngledCorners(currentView, corners, capturedImageSize)
    let centroidBelowAnchor = createNudgedCentroidAnchor(from: cornerAnchors, nudgePercentage: 0.0)

    print("vertices: \(normalizedVertices)")
    print("corners: \(corners)")

    
    let distanceToFish = calculateDistanceToObject(centroidAboveAnchor)
    let distanceToGround = calculateDistanceToObject(centroidBelowAnchor!)
    let scalingFactor = distanceToFish / distanceToGround
    
    verticesAnchors = stretchVertices(verticesAnchors, verticalScaleFactor: scalingFactor*1.1, horizontalScaleFactor: scalingFactor*1.1)
    
    return (verticesAnchors, centroidAboveAnchor, centroidBelowAnchor!, cornerAnchors)
}
