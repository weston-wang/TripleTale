//
//  PostprocessingUtils.swift
//  TripleTale
//
//  Created by Wes Wang on 6/4/25.
//

import CoreGraphics
import Vision
import UIKit

struct MLUtils {
    static func resizeImageForModel(_ image: UIImage, width: Int = 320, height: Int = 320) -> UIImage? {
        let newSize = CGSize(width: width, height: height)

        // Resize the image to the new dimensions
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage
    }
    
    static func processObservations(for request: VNRequest, error: Error?) -> (identifierString: String, confidence: VNConfidence, boundingBox: CGRect?)? {
        guard let results = request.results else {
            print("Unable to process image.\n\(error?.localizedDescription ?? "Unknown error")")
            return nil
        }

        let threshold: Float = 0.0
        
        var identifierString = ""
        var confidence: VNConfidence = 0
        var boundingBox: CGRect? = nil

        if let detections = results as? [VNRecognizedObjectObservation] {
            // Handle object detections
            if let bestResult = detections.first(where: { result in result.confidence > threshold }),
               let label = bestResult.labels.first?.identifier.split(separator: ",").first {
                identifierString = String(label)
                confidence = bestResult.confidence
                boundingBox = bestResult.boundingBox
            }
        } else if let classifications = results as? [VNClassificationObservation] {
            // Handle classifications
            if let bestResult = classifications.first(where: { result in result.confidence > threshold }),
               let label = bestResult.identifier.split(separator: ",").first {
                identifierString = String(label)
                confidence = bestResult.confidence
            }
        } else {
            print("Unknown result type: \(type(of: results))")
            return nil
        }

        return (identifierString, confidence, boundingBox)
    }

    static func postprocessFishMask(from maskArray: MLMultiArray, originalSize: CGSize, maskThreshold: Double = 0.8) -> UIImage? {
        let width = maskArray.shape[3].intValue
        let height = maskArray.shape[2].intValue

        let count = maskArray.count
        let floatArray = (0..<count).map { i -> Float in
            let x = maskArray[i].floatValue
            return 1 / (1 + exp(-x))  // Apply sigmoid
        }

        // Convert to grayscale image
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { buffer.deallocate() }

        for i in 0..<count {
            buffer[i] = floatArray[i] > Float(maskThreshold) ? 255 : 0
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        guard let provider = CGDataProvider(dataInfo: nil, data: buffer, size: count, releaseData: { _,_,_ in }) else { return nil }
        guard let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    static func softmaxClassMaskToBinaryImage(_ multiArray: MLMultiArray, threshold: Float = 0.5) -> UIImage? {
        var shape = multiArray.shape.map { $0.intValue }
        if shape.count == 4 && shape[0] == 1 {
            shape.removeFirst() // remove batch dimension → shape becomes [2, 320, 320]
        }
        guard shape.count == 3 else {
            print("Expected shape [num_classes, height, width], got \(shape)")
            return nil
        }

        let numClasses = shape[0]
        let height = shape[1]
        let width = shape[2]

        let count = height * width
        let floatPointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: shape[0] * shape[1] * shape[2])
        let buffer = UnsafeBufferPointer(start: floatPointer, count: numClasses * count)

        var scores = [Float](repeating: 0, count: count)
        var classes = [UInt8](repeating: 0, count: count)

        // Normalize (optional, mirrors your Python code)
        let minVal = buffer.min() ?? 0
        let maxVal = buffer.max() ?? 1
        let range = maxVal - minVal

        for i in 0..<count {
            var maxScore: Float = -Float.infinity
            var bestClass: UInt8 = 0

            for c in 0..<numClasses {
                let index = c * count + i
                let raw = buffer[index]
                let normalized = range > 0 ? (raw - minVal) / range : 0

                if normalized > maxScore {
                    maxScore = normalized
                    bestClass = UInt8(c)
                }
            }

            scores[i] = maxScore
            classes[i] = bestClass
        }

        // Threshold to binary mask
        let pixelData = (0..<count).map { scores[$0] > threshold && classes[$0] == 1 ? UInt8(255) : UInt8(0) }

        guard let cfData = CFDataCreate(nil, pixelData, count),
              let provider = CGDataProvider(data: cfData) else {
            return nil
        }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    static func imageToMultiArray(_ image: UIImage, targetSize: CGSize = CGSize(width: 320, height: 320)) -> MLMultiArray? {
        guard let cgImage = image.cgImage else {
            print("Failed to get CGImage")
            return nil
        }

        return cgImageToMultiArray(cgImage, targetSize: targetSize)
    }
    
    static func multiArrayToUIImage(_ multiArray: MLMultiArray, width: Int = 320, height: Int = 320) -> UIImage? {
        guard multiArray.dataType == .float32 else {
            print("Expected MLMultiArray with Float32 type")
            return nil
        }

        let count = width * height
        let floatPointer = multiArray.dataPointer.bindMemory(to: Float32.self, capacity: count)
        let buffer = UnsafeBufferPointer(start: floatPointer, count: count)

        // Optional: Normalize or clamp pixel range as needed
        let pixelData = buffer.map { UInt8(min(max($0 * 255.0, 0), 255)) }

        guard let cfData = CFDataCreate(nil, pixelData, count),
              let provider = CGDataProvider(data: cfData) else {
            print("Failed to create CGDataProvider")
            return nil
        }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            print("Failed to create CGImage")
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    static func multiArrayToGrayscaleImage(_ multiArray: MLMultiArray) -> UIImage? {
        guard multiArray.dataType == .float16 || multiArray.dataType == .float32 else {
            print("❌ Unsupported MultiArray data type")
            return nil
        }

        let shape = multiArray.shape.map { $0.intValue }
        guard shape.count >= 3 else {
            print("❌ Unexpected shape for mask array")
            return nil
        }

        let height = shape[shape.count - 2]
        let width = shape[shape.count - 1]
        let totalCount = width * height

        let floatData: [Float]
        if multiArray.dataType == .float16 {
            floatData = (0..<totalCount).map {
                Float(truncating: multiArray[$0] as NSNumber)
            }
        } else {
            floatData = (0..<totalCount).map {
                multiArray[$0].floatValue
            }
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: totalCount)
        for i in 0..<totalCount {
            buffer[i] = UInt8(clamping: Int(floatData[i] * 255))
        }

        let grayColorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(data: buffer,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: width,
                                space: grayColorSpace,
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)

        guard let cgImage = context?.makeImage() else {
            buffer.deallocate()
            return nil
        }

        let uiImage = MaskProcessor.fillHolesInMask(cgImage)
    //    let uiImage = UIImage(cgImage: cgImage)
        buffer.deallocate()
        return uiImage
    }

    static func detectTopFaceBoundingBox(in image: UIImage) -> CGRect? {
        guard let ciImage = CIImage(image: image) else {
            fatalError("Unable to create CIImage from UIImage")
        }
        
        var topFaceRect: CGRect?
        
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
            if let error = error {
                print("Face detection error: \(error)")
                return
            }
            guard let observations = request.results as? [VNFaceObservation] else {
                return
            }
            
            var minY: CGFloat = CGFloat.greatestFiniteMagnitude
            
            for face in observations {
                let boundingBox = face.boundingBox
                let size = image.size
                let x = boundingBox.origin.x * size.width
                let y = (1 - boundingBox.origin.y - boundingBox.height) * size.height
                let width = boundingBox.width * size.width
                let height = boundingBox.height * size.height
                let faceRect = CGRect(x: x, y: y, width: width, height: height)
                
                // Update the topFaceRect if this face is closer to the top
                if y < minY {
                    minY = y
                    topFaceRect = faceRect
                }
            }
        }
        
        let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        do {
            try requestHandler.perform([faceDetectionRequest])
        } catch {
            print("Failed to perform face detection: \(error)")
            return nil
        }
        
        return topFaceRect
    }

    private static func cgImageToMultiArray(_ cgImage: CGImage, targetSize: CGSize = CGSize(width: 320, height: 320)) -> MLMultiArray? {
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)

        // Create RGB context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )

        guard let ctx = context else {
            print("Failed to create CGContext")
            return nil
        }

        // Draw the resized image into the context
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelBuffer = ctx.data else {
            print("Failed to get pixel data")
            return nil
        }

        // Create MLMultiArray (1, 320, 320, 3)
        guard let array = try? MLMultiArray(shape: [1, NSNumber(value: height), NSNumber(value: width), 3], dataType: .float32) else {
            print("Failed to create MLMultiArray")
            return nil
        }

        let buffer = pixelBuffer.bindMemory(to: UInt8.self, capacity: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * 4
                let r = Float(buffer[pixelIndex])
                let g = Float(buffer[pixelIndex + 1])
                let b = Float(buffer[pixelIndex + 2])

                let offset = (y * width + x) * 3
                array[[0, y as NSNumber, x as NSNumber, 0]] = NSNumber(value: r)
                array[[0, y as NSNumber, x as NSNumber, 1]] = NSNumber(value: g)
                array[[0, y as NSNumber, x as NSNumber, 2]] = NSNumber(value: b)
            }
        }

        return array
    }
}
