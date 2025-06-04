//
//  OrientationUtils.swift
//  TripleTale
//
//  Created by Wes Wang on 6/4/25.
//
import UIKit

struct OrientationUtils {
    
    static func uiImageOrientation(from radians: CGFloat) -> UIImage.Orientation {
        switch radians {
        case CGFloat.pi / 2:
            return .left
        case -CGFloat.pi / 2:
            return .right
        case CGFloat.pi, -CGFloat.pi:
            return .down
        default:
            return .up
        }
    }

    static func popUpImageOrientation(from radians: CGFloat) -> UIImage.Orientation {
        switch radians {
        case CGFloat.pi / 2:
            return .right
        case -CGFloat.pi / 2:
            return .left
        case CGFloat.pi, -CGFloat.pi:
            return .down
        default:
            return .up
        }
    }

}
