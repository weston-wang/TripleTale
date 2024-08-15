//
//  Measurements.swift
//  TripleTale
//
//  Created by Wes Wang on 8/5/24.
//  Copyright © 2024 Apple. All rights reserved.
//

import Foundation
import ARKit

func measureDimensions(_ midpointAnchors: [ARAnchor], _ centroidAnchor: ARAnchor, _ originalBoundingBox:CGRect, _ imageSize: CGSize, _ currentView: ARSKView, _ isForward: Bool, scale: Float = 1.0) -> (Float, Float, Float, Float){
    var length: Float
    var width: Float
    var height: Float
    var circumference: Float
            
    var updatedMidpointAnchors: [ARAnchor]
    
    if !isForward {
        height = calculateHeightBetweenAnchors(anchor1: centroidAnchor, anchor2: midpointAnchors[4])

        let distanceToPhone = calculateDistanceToObject(midpointAnchors[4])
        let distanceToGround = calculateDistanceToObject(centroidAnchor)
                    
        // update boundingbox for calculations
        let updatedBoundingBox = reversePerspectiveEffectOnBoundingBox(boundingBox: originalBoundingBox, distanceToPhone: distanceToPhone, totalDistance: distanceToGround)
        
        updatedMidpointAnchors = getMidpoints(currentView, updatedBoundingBox, imageSize)
    } else {
        let heightL = calculateDepthBetweenAnchors(anchor1: midpointAnchors[4], anchor2: midpointAnchors[0])
        let heightR = calculateDepthBetweenAnchors(anchor1: midpointAnchors[4], anchor2: midpointAnchors[1])

        height = max(heightL, heightR) * 2.0 * scale
        
        updatedMidpointAnchors = midpointAnchors
    }
    
    width = calculateDistanceBetweenAnchors(anchor1: updatedMidpointAnchors[0], anchor2: updatedMidpointAnchors[1]) * scale
    length = calculateDistanceBetweenAnchors(anchor1: updatedMidpointAnchors[2], anchor2: updatedMidpointAnchors[3]) * scale
            
    circumference = calculateCircumference(majorAxis: width, minorAxis: height)
    
    return (width, length, height, circumference)
}

func measureVertices(_ verticesAnchors: [ARAnchor], _ cornersAnchors: [ARAnchor], _ aboveAnchor: ARAnchor, _ belowAnchor: ARAnchor) ->  (Float, Float, Float) {
    let width = calculateDistanceBetweenAnchors2D(anchor1: verticesAnchors[0], anchor2: verticesAnchors[2])
    let length = calculateDistanceBetweenAnchors2D(anchor1: verticesAnchors[1], anchor2: verticesAnchors[3])
    
    let normVector = normalVector(from: cornersAnchors)
    let height = distanceToPlane(from: aboveAnchor, planeAnchor: belowAnchor, normal: normVector!)
    
    return (width, length, height)
}
