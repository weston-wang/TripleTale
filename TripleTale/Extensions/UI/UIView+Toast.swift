//
//  UIView+Toast.swift
//  TripleTale
//
//  Created by Wes Wang on 6/3/25.
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

extension UIView {
    func showToast(message: String, duration: TimeInterval = 10.0) {
        let toastLabel = UILabel(frame: CGRect(x: self.frame.size.width / 2 - 150, y: 40, width: 300, height: 35)) // Adjusted y coordinate
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toastLabel.textColor = UIColor.white
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.boldSystemFont(ofSize: 12.0) // Changed to bold system font
        toastLabel.text = message
        toastLabel.alpha = 1.0
        toastLabel.layer.cornerRadius = 10
        toastLabel.clipsToBounds = true
        self.addSubview(toastLabel)
        UIView.animate(withDuration: duration, delay: 0.1, options: .curveEaseOut, animations: {
            toastLabel.alpha = 0.0
        }, completion: {(isCompleted) in
            toastLabel.removeFromSuperview()
        })
    }
}
