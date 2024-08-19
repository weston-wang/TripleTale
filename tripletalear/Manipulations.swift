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
