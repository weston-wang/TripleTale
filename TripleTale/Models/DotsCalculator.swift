//
//  DotsCalculator.swift
//  TripleTale
//
//  Created by Wes Wang on 8/6/23.
//

import UIKit


struct DotsCalculator {
    let userDots: [UIView]
    
    var length: Float?
    var width: Float?
    
    mutating func calculateLengthsBetweenOpposingVertices() {
        // find top and bottom
        let dotsTopBottom = findTopmostAndBottommostDots()
        let dotsLeftRight = findLeftmostAndRightmostDots()

        let topmostDot = dotsTopBottom.topmost
        let bottommostDot = dotsTopBottom.bottommost
        let leftmostDot = dotsLeftRight.leftmost
        let rightmostDot = dotsLeftRight.rightmost
        
        // Calculate the lengths between opposing vertices (diagonals)
        let topToBottomPixels = distanceBetweenPoints(topmostDot!.center, bottommostDot!.center)
        let rightToLeftPixels = distanceBetweenPoints(rightmostDot!.center, leftmostDot!.center)
        
        length = max(Float(topToBottomPixels), Float(rightToLeftPixels))
        width = min(Float(topToBottomPixels), Float(rightToLeftPixels))
    }
    
    func distanceBetweenPoints(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return hypot(dx, dy)
    }
    
    func findTopmostAndBottommostDots() -> (topmost: UIView?, bottommost: UIView?) {
        var topmostDot: UIView?
        var bottommostDot: UIView?
        var minY: CGFloat = CGFloat.greatestFiniteMagnitude
        var maxY: CGFloat = -CGFloat.greatestFiniteMagnitude

        for dot in userDots {
            let dotCenter = dot.center
            if dotCenter.y < minY {
                minY = dotCenter.y
                topmostDot = dot
            }
            if dotCenter.y > maxY {
                maxY = dotCenter.y
                bottommostDot = dot
            }
        }

        return (topmostDot, bottommostDot)
    }
    
    func findLeftmostAndRightmostDots() -> (leftmost: UIView?, rightmost: UIView?) {
        var leftmostDot: UIView?
        var rightmostDot: UIView?
        var minX: CGFloat = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = -CGFloat.greatestFiniteMagnitude

        for dot in userDots {
            let dotCenter = dot.center
            if dotCenter.x < minX {
                minX = dotCenter.x
                leftmostDot = dot
            }
            if dotCenter.x > maxX {
                maxX = dotCenter.x
                rightmostDot = dot
            }
        }

        return (leftmostDot, rightmostDot)
    }
    
}
