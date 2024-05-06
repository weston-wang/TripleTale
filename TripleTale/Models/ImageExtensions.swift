//
//  ImageExtensions.swift
//  JPForensics
//
//  Created by Wes Wang on 10/31/23.
//

import UIKit
import Vision
import CoreImage

extension UIImage {
    func centerSquare() -> UIImage? {
        let shortestSide = min(self.size.width, self.size.height)
        let squareSideLength = shortestSide / 2.0 * 1.0
        
        // Compute the starting coordinates
        let startX = (self.size.width - squareSideLength) / 2.0
        let startY = (self.size.height - squareSideLength) / 2.0
        
        let squareFrame = CGRect(x: startX, y: startY, width: squareSideLength, height: squareSideLength)
        
        guard let cgImage = self.cgImage?.cropping(to: squareFrame) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    func resized(toWidth width: CGFloat) -> UIImage? {
        let aspectRatio = size.height / size.width
        let newHeight = width * aspectRatio
        
        UIGraphicsBeginImageContext(CGSize(width: width, height: newHeight))
        draw(in: CGRect(x: 0, y: 0, width: width, height: newHeight))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
    
    func resized(to size: CGSize, interpolationQuality: CGInterpolationQuality) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0) // 0.0 for the scale makes the image use the scale factor of the device’s main screen.
        let context = UIGraphicsGetCurrentContext()
        context?.interpolationQuality = interpolationQuality
        
        draw(in: CGRect(origin: .zero, size: size))
        
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage
    }
    
    func croppedToTopSquare() -> UIImage? {
        // The side length of the square will be the width of the original image
        let sideLength = min(size.width, size.height)
        
        // Create a CGRect representing the area to be cropped
        let cropArea = CGRect(
            x: 0,
            y: 0,
            width: sideLength,
            height: sideLength
        )
        
        // Perform cropping in the Core Graphics context
        guard let cgImage = self.cgImage,
              let croppedCgImage = cgImage.cropping(to: cropArea) else {
            return nil
        }
        
        return UIImage(cgImage: croppedCgImage, scale: scale, orientation: imageOrientation)
    }

    func extractRectangle(widthPercentage: CGFloat = 0.5, aspectRatio: CGFloat = 3.0/2.0) -> UIImage? {
        let originalWidth = self.size.width
        let originalHeight = self.size.height
        
        // New width is a percentage of the original width
        let newWidth = originalWidth * widthPercentage
        
        // Calculate new height based on the aspect ratio
        let newHeight = newWidth * aspectRatio
        
        // Ensure that the new height does not exceed original height
        let finalHeight = min(newHeight, originalHeight)
        
        // Calculate the x position to center the rectangle
        let xPos = (originalWidth - newWidth) / 2.0
        
        // Create rectangle for cropping
        let rect = CGRect(x: xPos, y: 0, width: newWidth, height: finalHeight)
        
        // Perform cropping
        guard let cgImage = self.cgImage?.cropping(to: rect) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    func isQRCodeInCenterSquare() -> Bool {
       guard let ciImage = CIImage(image: self) else {
           return false
       }

       let request = VNDetectBarcodesRequest()
       let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up, options: [:])
       
       do {
           try handler.perform([request])
           
           guard let qrObservation = request.results?.first as? VNBarcodeObservation else {
               print("No QR Code detected.")
               return false
           }
           
           let imageSize = ciImage.extent.size
           let scale = self.scale // The scale factor of the image
           
           // Convert the normalized bounding box to image pixel coordinates
           let qrBoundingBox = qrObservation.boundingBox
           let qrRect = CGRect(
               x: qrBoundingBox.minX * imageSize.width / scale,
               y: (1 - qrBoundingBox.maxY) * imageSize.height / scale,
               width: qrBoundingBox.width * imageSize.width / scale,
               height: qrBoundingBox.height * imageSize.height / scale
           )
           
           // Calculate the center square frame in pixel coordinates
           let shortestSide = min(self.size.width, self.size.height)
           let squareSideLength = shortestSide / 2.0 * 1.5 // 50% wiggle room
           let startX = (self.size.width - squareSideLength) / 2.0
           let startY = (self.size.height - squareSideLength) / 2.0
           let centerSquareFrame = CGRect(x: startX, y: startY, width: squareSideLength, height: squareSideLength)
           
           // Check if the QR code bounding box is inside the center square frame
           return centerSquareFrame.intersects(qrRect)
           
       } catch {
           print("Error performing QR code detection: \(error)")
           return false
       }
   }
}


extension CIImage {
    func averageBrightness() -> Double? {
        let extentVector = CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height)
        guard let averageFilter = CIFilter(name: "CIAreaAverage", parameters: ["inputImage": self, "inputExtent": extentVector]) else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(averageFilter.outputImage!, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        return Double(bitmap[0]) / 255.0
    }
}
