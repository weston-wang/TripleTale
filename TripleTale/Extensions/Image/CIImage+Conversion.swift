//
//  CIImage+Conversion.swift
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

extension CIImage {
    func toUIImage() -> UIImage? {
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(self, from: self.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}
