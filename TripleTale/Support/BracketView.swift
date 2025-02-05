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
    }

    func updateBracket(rect: CGRect) {
        let path = UIBezierPath()
        let bracketLength: CGFloat = 20.0

        // Top-left bracket
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bracketLength, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bracketLength))

        // Top-right bracket
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - bracketLength, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bracketLength))

        // Bottom-left bracket
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + bracketLength, y: rect.minY))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bracketLength))

        // Bottom-right bracket
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - bracketLength, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + bracketLength))

        shapeLayer.path = path.cgPath

        // Position the image at the center-top between the two brackets
        let imageSize = CGSize(width: 100, height: 100) // Adjust as needed
        let imageX = (rect.minX + rect.maxX) / 2 - imageSize.width / 2
        let imageY = rect.minY + bracketLength // Just below the top brackets

        imageView.frame = CGRect(x: imageX, y: imageY, width: imageSize.width, height: imageSize.height)
        imageView.isHidden = false
    }
}
