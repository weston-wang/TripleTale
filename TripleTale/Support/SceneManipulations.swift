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

    // Helper function to get the position from an anchor
    func position(from anchor: ARAnchor) -> SIMD3<Float> {
        return SIMD3<Float>(anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
    }

    // Get the positions of the anchors
    var lTPos = position(from: cornerAnchors[0])
    var rTPos = position(from: cornerAnchors[1])
    var lBPos = position(from: cornerAnchors[2])
    var rBPos = position(from: cornerAnchors[3])

    // Calculate the width and height based on anchor positions
    let width = simd_length(rTPos - lTPos)
    let height = simd_length(rTPos - rBPos)

    // Nudge each position by the specified percentage
    lTPos.x -= width * nudgePercentage
    lTPos.y += height * nudgePercentage
    
    rTPos.x += width * nudgePercentage
    rTPos.y += height * nudgePercentage
    
    lBPos.x -= width * nudgePercentage
    lBPos.y -= height * nudgePercentage
    
    rBPos.x += width * nudgePercentage
    rBPos.y -= height * nudgePercentage

    // Calculate the centroid
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
