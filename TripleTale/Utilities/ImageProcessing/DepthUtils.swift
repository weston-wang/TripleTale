//
//  DepthUtils.swift
//  TripleTale
//
//  Created by Wes Wang on 6/3/25.
//
import ARKit

struct DepthUtils {
    static func convertImageAPointToImageB(xScreen: CGFloat, yScreen: CGFloat, screenSize: CGSize = CGSize(width: 1179, height: 2556), depthSize: CGSize = CGSize(width: 192, height: 256)
    ) -> CGPoint {
        let normX = xScreen / screenSize.width
        let normY = yScreen / screenSize.height

        var adjustedX = normX
        let adjustedY = normY

        // A is wider, so B is vertically cropped
        let scale = screenSize.height / depthSize.height
        let scaledWidth = depthSize.width * scale
        
        let crop = (scaledWidth - screenSize.width) / 2
        adjustedX = xScreen + crop

        let xB = adjustedX / scale
        let yB = yScreen / scale

        return CGPoint(x: xB, y: yB)
    }

    static func getDepthMap(from currentFrame: ARFrame) -> UIImage? {
        // First, try to get sceneDepth from LiDAR-equipped devices
        if let sceneDepth = currentFrame.sceneDepth {
            return ImageConverter.pixelBufferToUIImage(pixelBuffer: sceneDepth.depthMap)
        }
        
        // If sceneDepth is not available, check for smoothedSceneDepth (better quality for non-LiDAR devices)
        if let smoothedSceneDepth = currentFrame.smoothedSceneDepth {
            return ImageConverter.pixelBufferToUIImage(pixelBuffer: smoothedSceneDepth.depthMap)
        }
        
        // Fallback to estimatedDepthData if smoothedSceneDepth is not available
        if let estimatedDepthData = currentFrame.estimatedDepthData {
            return ImageConverter.pixelBufferToUIImage(pixelBuffer: estimatedDepthData)
        }
        
        // If no depth data is available, return nil
        print("Depth data not available on this device.")
        return nil
    }
    
    /// Resize depth map back to the original input image size
    static func resizeDepthMap(_ depthImage: UIImage, to originalSize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(originalSize, false, 1.0)
        depthImage.draw(in: CGRect(origin: .zero, size: originalSize))
        let resizedDepthImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedDepthImage
    }
    
    // Function to get the depth value at specific coordinates (centerX, centerY) from a UIImage
    static func getDepthValue(atX centerX: CGFloat, atY centerY: CGFloat, depthMap: UIImage) -> CGFloat? {
        // Ensure the coordinates are within bounds of the image
        guard let cgImage = depthMap.cgImage else {
            print("Error: Unable to access CGImage from UIImage")
            return nil
        }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        // Ensure the coordinates are within the bounds of the image
        guard centerX >= 0 && centerX < imageWidth && centerY >= 0 && centerY < imageHeight else {
            print("Error: Coordinates are outside the image bounds")
            return nil
        }
        
        // Create a bitmap context to extract the pixel data
        guard let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data else {
            print("Error: Unable to get pixel data from CGImage")
            return nil
        }
        
        let data = CFDataGetBytePtr(pixelData)
        
        // Calculate the byte index for the specified coordinates
        let bytesPerPixel = 1  // Assuming it's an 8-bit grayscale image (1 byte per pixel)
        let byteIndex = Int(centerY) * cgImage.bytesPerRow + Int(centerX) * bytesPerPixel
        
        // Extract the grayscale pixel value (depth) at the specified coordinates
        let pixelValue = data?[byteIndex]
        
        // Convert the pixel value to a CGFloat
        if let pixelValue = pixelValue {
            return CGFloat(pixelValue) / 255.0  // Normalize to [0, 1]
        } else {
            print("Error: Failed to extract pixel value")
            return nil
        }
    }
    
    static func depthPixelBufferToUIImage(pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    static func refineMaskWithDepth(fishMask: UIImage, depthMap: UIImage, depthThreshold: CGFloat = 0.2) -> UIImage? {
        guard let maskCI = CIImage(image: fishMask),
              let depthCI = CIImage(image: depthMap) else {
            print("❌ Failed to create CIImage from inputs")
            return nil
        }

        let width = Int(maskCI.extent.width)
        let height = Int(maskCI.extent.height)
        let bytesPerRow = width

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CIContext()

        guard let maskCG = context.createCGImage(maskCI, from: maskCI.extent),
              let depthCG = context.createCGImage(depthCI, from: depthCI.extent),
              let maskBitmapContext = CGContext(data: nil,
                                                width: width,
                                                height: height,
                                                bitsPerComponent: 8,
                                                bytesPerRow: bytesPerRow,
                                                space: colorSpace,
                                                bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let depthBitmapContext = CGContext(data: nil,
                                                 width: width,
                                                 height: height,
                                                 bitsPerComponent: 8,
                                                 bytesPerRow: bytesPerRow,
                                                 space: colorSpace,
                                                 bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            print("❌ Failed to create bitmap contexts")
            return nil
        }

        maskBitmapContext.draw(maskCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        depthBitmapContext.draw(depthCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let maskBuffer = maskBitmapContext.data,
              let depthBuffer = depthBitmapContext.data else {
            print("❌ Failed to get bitmap buffer data")
            return nil
        }

        var foregroundDepths: [UInt8] = []

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x
                let maskValue = maskBuffer.load(fromByteOffset: offset, as: UInt8.self)
                if maskValue > 128 {
                    let depth = depthBuffer.load(fromByteOffset: offset, as: UInt8.self)
                    foregroundDepths.append(depth)
                }
            }
        }

        guard !foregroundDepths.isEmpty else {
            print("❌ No foreground pixels found in mask")
            return nil
        }

        foregroundDepths.sort()
        let medianDepth = foregroundDepths[foregroundDepths.count / 2]

        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x
                let maskValue = maskBuffer.load(fromByteOffset: offset, as: UInt8.self)
                let depth = depthBuffer.load(fromByteOffset: offset, as: UInt8.self)
                let depthDiff = abs(Int(depth) - Int(medianDepth))
                let keep = maskValue > 128 && depthDiff < Int(depthThreshold * 255)
                outputBuffer[offset] = keep ? 255 : 0
            }
        }

        if let outputContext = CGContext(data: outputBuffer,
                                         width: width,
                                         height: height,
                                         bitsPerComponent: 8,
                                         bytesPerRow: bytesPerRow,
                                         space: colorSpace,
                                         bitmapInfo: CGImageAlphaInfo.none.rawValue),
           let outputCGImage = outputContext.makeImage() {
            let output = UIImage(cgImage: outputCGImage)
            outputBuffer.deallocate()
            return output
        } else {
            outputBuffer.deallocate()
            print("❌ Failed to create refined output image")
            return nil
        }
    }
}
