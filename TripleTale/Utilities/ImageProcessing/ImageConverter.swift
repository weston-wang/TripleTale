//
//  ImageConverter.swift
//  TripleTale
//
//  Created by Wes Wang on 6/3/25.
//

import UIKit
import CoreImage
import CoreVideo

struct ImageConverter {
    static func pixelBufferToUIImage(pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        let rotation = CGAffineTransform(rotationAngle: -.pi / 2)
        let rotatedCIImage = ciImage.transformed(by: rotation)

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(rotatedCIImage, from: rotatedCIImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

}
