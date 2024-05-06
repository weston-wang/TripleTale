//
//  CameraOverlayView.swift
//  JPForensics
//
//  Created by Wes Wang on 8/2/23.
//

import UIKit

class CameraOverlayView: UIView {
    func guideForCameraOverlay() -> UIView {
        let guide = UIView(frame: UIScreen.main.fullScreenThreeTwoRectangle())
        guide.backgroundColor = UIColor.clear

        guide.isUserInteractionEnabled = false
        return guide
    }

}

extension UIScreen {
    func fullScreenThreeTwoRectangle() -> CGRect {
        let screenWidth = UIScreen.main.bounds.size.width
        let screenHeight = UIScreen.main.bounds.size.height
        
        let isLandscape = screenWidth > screenHeight
//        let shorterSide = min(screenWidth, screenHeight)
        let longerSide = max(screenWidth, screenHeight)

        let aspectRatio: CGFloat = 3.0 / 2.0
//        let rectangleWidth = shorterSide * 0.8
//        let rectangleHeight = rectangleWidth / aspectRatio
        
        let rectangleHeight = longerSide * 0.5
        let rectangleWidth = rectangleHeight / aspectRatio
        
        var x: CGFloat = 0
        var y: CGFloat = 0
        
        if isLandscape {
            x = (screenWidth / 2) - (rectangleWidth / 2)
            y = (screenHeight / 2) - (rectangleHeight / 2)
        } else {
            y = (screenHeight / 2) - (rectangleHeight / 2)
            x = (screenWidth / 2) - (rectangleWidth / 2)
        }
        
        return CGRect(x: x, y: y-screenHeight/20, width: rectangleWidth, height: rectangleHeight)
    }
    
    func fullScreenMiniSquare() -> CGRect {
        let screenWidth = UIScreen.main.bounds.size.width
        let screenHeight = UIScreen.main.bounds.size.height
        
        let isLandscape = screenWidth > screenHeight

        let longerSide = max(screenWidth, screenHeight)
        let squareLength = longerSide * 0.125

        var x: CGFloat = 0
        var y: CGFloat = 0
        
        if isLandscape {
            x = (screenWidth / 2) - (squareLength / 2)
            y = (screenHeight / 2) - (squareLength / 2)
        } else {
            y = (screenHeight / 2) - (squareLength / 2)
            x = (screenWidth / 2) - (squareLength / 2)
        }
        
        return CGRect(x: x, y: y-screenHeight/20, width: squareLength, height: squareLength)
    }
}
