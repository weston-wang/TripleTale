//
//  BracketView.swift
//  tripletalear
//
//  Created by Wes Wang on 8/18/24.
//

import Foundation
import UIKit

class BracketView: UIView {
    private let shapeLayer = CAShapeLayer()
    private let imageView = UIImageView(image: UIImage(named: "bass_head"))

    private let topTextLayer = CATextLayer()
    private let bottomTextLayer = CATextLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        shapeLayer.strokeColor = UIColor.white.cgColor
        shapeLayer.lineWidth = 3.0
        shapeLayer.fillColor = UIColor.clear.cgColor
        layer.addSublayer(shapeLayer)

        // Configure image view
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true  // Initially hidden until positioned
        addSubview(imageView)

        // Configure top text layer
        configureTextLayer(topTextLayer)
        layer.addSublayer(topTextLayer)

        // Configure bottom text layer
        configureTextLayer(bottomTextLayer)
        layer.addSublayer(bottomTextLayer)
    }

    private func configureTextLayer(_ textLayer: CATextLayer) {
        textLayer.string = "T"
        textLayer.fontSize = 18
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.contentsScale = UIScreen.main.scale
    }
    
    func addCircleMarker() {
        let circleRadius: CGFloat = 8.0
        let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)

        // Black border circle
        let borderPath = UIBezierPath(arcCenter: centerPoint, radius: circleRadius + 1, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        let borderLayer = CAShapeLayer()
        borderLayer.path = borderPath.cgPath
        borderLayer.strokeColor = UIColor.black.withAlphaComponent(0.2).cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 2.5
        borderLayer.lineDashPattern = [4, 2]
        layer.addSublayer(borderLayer)

        // Dashed white circle
        let circlePath = UIBezierPath(arcCenter: centerPoint, radius: circleRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        let circleLayer = CAShapeLayer()
        circleLayer.path = circlePath.cgPath
        circleLayer.strokeColor = UIColor.white.withAlphaComponent(1.0).cgColor
        circleLayer.fillColor = UIColor.clear.cgColor
        circleLayer.lineWidth = 2.0
        circleLayer.lineDashPattern = [4, 2]
        layer.addSublayer(circleLayer)
    }

    func updateBracket(rect: CGRect) {
        let path = UIBezierPath()
        let bracketLength: CGFloat = 20.0
        let tHeight: CGFloat = 15.0  // Height of the vertical part of the "T"
        let tWidth: CGFloat = (rect.maxX - rect.minX) / 2  // Half the width

        let centerX = (rect.minX + rect.maxX) / 2
        let tStartX = centerX - tWidth / 2
        let tEndX = centerX + tWidth / 2
        
        let verticalOffset = 50.0

//        // Bottom-left bracket
//        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - verticalOffset))
//        path.addLine(to: CGPoint(x: rect.minX + bracketLength, y: rect.maxY - verticalOffset))
//        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - verticalOffset))
//        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bracketLength - verticalOffset))
//
//        // Bottom-right bracket
//        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - verticalOffset))
//        path.addLine(to: CGPoint(x: rect.maxX - bracketLength, y: rect.maxY - verticalOffset))
//        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - verticalOffset))
//        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bracketLength - verticalOffset))
//
//        // Top-left bracket
//        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
//        path.addLine(to: CGPoint(x: rect.minX + bracketLength, y: rect.minY))
//        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
//        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bracketLength))
//
//        // Top-right bracket
//        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
//        path.addLine(to: CGPoint(x: rect.maxX - bracketLength, y: rect.minY))
//        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
//        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + bracketLength))
        
        // Position the image at the center-top between the two brackets
        let imageSize = CGSize(width: 100, height: 100) // Adjust as needed
        let imageX = (rect.minX + rect.maxX) / 2 - imageSize.width / 2
        let imageY = rect.minY + bracketLength // Just below the top brackets

        imageView.frame = CGRect(x: imageX, y: imageY, width: imageSize.width, height: imageSize.height)
//        imageView.isHidden = false
        
        // Bottom upside-down "T" shape (shorter horizontal + vertical)
        path.move(to: CGPoint(x: tStartX, y: rect.maxY - verticalOffset)) // Horizontal part
        path.addLine(to: CGPoint(x: tEndX, y: rect.maxY  - verticalOffset))
        path.move(to: CGPoint(x: centerX, y: rect.maxY  - verticalOffset)) // Vertical part
        path.addLine(to: CGPoint(x: centerX, y: rect.maxY - tHeight  - verticalOffset))

        // Top "T" shape (shorter horizontal + vertical)
        path.move(to: CGPoint(x: tStartX, y: rect.minY)) // Horizontal part
        path.addLine(to: CGPoint(x: tEndX, y: rect.minY))
        path.move(to: CGPoint(x: centerX, y: rect.minY)) // Vertical part
        path.addLine(to: CGPoint(x: centerX, y: rect.minY + tHeight))

        shapeLayer.path = path.cgPath
    }
}
