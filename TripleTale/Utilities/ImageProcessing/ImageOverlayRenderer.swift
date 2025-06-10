//
//  ImageOverlayRenderer.swift
//  TripleTale
//
//  Created by Wes Wang on 6/9/25.
//
import UIKit

struct ImageOverlayRenderer {
    static func drawContoursEllipseAndTips(on image: UIImage, contours: [[CGPoint]], closestContour: [CGPoint], ellipse: (center: CGPoint, size: CGSize, rotation: CGFloat), tips: [CGPoint]) -> UIImage? {
        // Create a renderer format with the appropriate scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale // Match the input image scale

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        let renderedImage = renderer.image { context in
            // Draw the original image
            image.draw(at: .zero)
            
            // Set the contour drawing properties
            context.cgContext.setStrokeColor(UIColor.blue.cgColor)
            context.cgContext.setLineWidth(1.0)
            
            // Draw all contours
            for contour in contours {
                context.cgContext.beginPath()
                for point in contour {
                    if point == contour.first {
                        context.cgContext.move(to: point)
                    } else {
                        context.cgContext.addLine(to: point)
                    }
                }
                context.cgContext.strokePath()
            }
            
            // Set the ellipse drawing properties
            context.cgContext.setStrokeColor(UIColor.red.cgColor)
            context.cgContext.setLineWidth(2.0)
            
            // Save the context state
            context.cgContext.saveGState()
            
            // Move to the ellipse center
            context.cgContext.translateBy(x: ellipse.center.x, y: ellipse.center.y)
            
            // Rotate the context
            context.cgContext.rotate(by: ellipse.rotation * CGFloat.pi / 180)
            
            // Draw the ellipse
            let rect = CGRect(x: -ellipse.size.width, y: -ellipse.size.height, width: 2 * ellipse.size.width, height: 2 * ellipse.size.height)
            context.cgContext.strokeEllipse(in: rect)
            
            // Restore the context state
            context.cgContext.restoreGState()
            
            // Set the tips drawing properties
            context.cgContext.setFillColor(UIColor.green.cgColor)
            
            // Draw the tips
            for tip in tips {
                context.cgContext.fillEllipse(in: CGRect(x: tip.x, y: tip.y, width: 15, height: 15))
            }
        }

        return renderedImage
    }
    
    static func drawRectanglesOnImage(image: UIImage, boundingBoxes: [CGRect]) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(at: CGPoint.zero)
        
        let context = UIGraphicsGetCurrentContext()!
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(5.0)
        
        for rect in boundingBoxes {
            let transformedRect = CGRect(x: rect.origin.x * image.size.width,
                                         y: (1 - rect.origin.y - rect.size.height) * image.size.height,
                                         width: rect.size.width * image.size.width,
                                         height: rect.size.height * image.size.height)
            context.stroke(transformedRect)
        }
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return newImage
    }
    
    static func drawBracketsOnImage(image: UIImage, boundingBox: CGRect, bracketLength: CGFloat = 25.0, bracketThickness: CGFloat = 5.0) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(at: CGPoint.zero)
        
        let context = UIGraphicsGetCurrentContext()!
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(bracketThickness)
                   
            // Top-left bracket
            context.move(to: CGPoint(x: boundingBox.minX, y: boundingBox.minY + bracketLength))
            context.addLine(to: CGPoint(x: boundingBox.minX, y: boundingBox.minY))
            context.addLine(to: CGPoint(x: boundingBox.minX + bracketLength, y: boundingBox.minY))
            
            // Top-right bracket
            context.move(to: CGPoint(x: boundingBox.maxX - bracketLength, y: boundingBox.minY))
            context.addLine(to: CGPoint(x: boundingBox.maxX, y: boundingBox.minY))
            context.addLine(to: CGPoint(x: boundingBox.maxX, y: boundingBox.minY + bracketLength))
            
            // Bottom-left bracket
            context.move(to: CGPoint(x: boundingBox.minX, y: boundingBox.maxY - bracketLength))
            context.addLine(to: CGPoint(x: boundingBox.minX, y: boundingBox.maxY))
            context.addLine(to: CGPoint(x: boundingBox.minX + bracketLength, y: boundingBox.maxY))
            
            // Bottom-right bracket
            context.move(to: CGPoint(x: boundingBox.maxX - bracketLength, y: boundingBox.maxY))
            context.addLine(to: CGPoint(x: boundingBox.maxX, y: boundingBox.maxY))
            context.addLine(to: CGPoint(x: boundingBox.maxX, y: boundingBox.maxY - bracketLength))
            
            context.strokePath()
        
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return newImage
    }
    
    static func drawROI(on ciImage: CIImage, portion: CGFloat) -> UIImage? {
        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height
        
        // Calculate the dimensions of the ROI
        let roiWidth = imageWidth * portion
        let roiHeight = imageHeight * portion
        
        // Calculate the position to center the ROI
        let roiX = (imageWidth - roiWidth) / 2
        let roiY = (imageHeight - roiHeight) / 2
        
        // Create the CGRect for the ROI
        let roiRect = CGRect(x: roiX, y: roiY, width: roiWidth, height: roiHeight)
        
        // Convert CIImage to UIImage
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let uiImage = UIImage(cgImage: cgImage)
        
        // Begin drawing on the UIImage
        UIGraphicsBeginImageContextWithOptions(uiImage.size, false, uiImage.scale)
        uiImage.draw(at: .zero)
        
        // Draw the ROI rectangle
        let path = UIBezierPath(rect: roiRect)
        UIColor.red.setStroke()  // You can change the color as needed
        path.lineWidth = 2  // You can adjust the line width as needed
        path.stroke()
        
        // Get the resulting image
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resultImage
    }
    
    static func drawEllipse(on image: UIImage, ellipse: (center: CGPoint, size: CGSize, rotationInDegrees: CGFloat), tips: [CGPoint]) -> UIImage? {
        // Create a renderer format with the appropriate scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale // Match the input image scale

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        let renderedImage = renderer.image { context in
            // Draw the original image
            image.draw(at: .zero)
            
            // Set the contour drawing properties for closestContour
            // Ensure fill mode is disabled
            context.cgContext.drawPath(using: .stroke)  // Explicitly only stroke the path

            // Set the ellipse drawing properties
            context.cgContext.setStrokeColor(UIColor.red.cgColor)
            context.cgContext.setLineWidth(3.0)
            
            // Save the context state
            context.cgContext.saveGState()
            
            // Move to the ellipse center
            context.cgContext.translateBy(x: ellipse.center.x, y: ellipse.center.y)
            
            // Rotate the context for the ellipse
            context.cgContext.rotate(by: ellipse.rotationInDegrees * CGFloat.pi / 180)
            
            // Draw the ellipse
            let rect = CGRect(x: -ellipse.size.width, y: -ellipse.size.height, width: 2 * ellipse.size.width, height: 2 * ellipse.size.height)
            context.cgContext.strokeEllipse(in: rect)
            
            // Restore the context state
            context.cgContext.restoreGState()
            
            // Set the tips drawing properties
            context.cgContext.setFillColor(UIColor.yellow.cgColor)
            
            // Draw the tips
            for tip in tips {
                context.cgContext.fillEllipse(in: CGRect(x: tip.x, y: tip.y, width: 15, height: 15))
            }
        }

        return renderedImage
    }
    
    static func drawPerimeterDots(on image: UIImage, perimeter: [CGPoint], dotSize: CGFloat = 5.0) -> UIImage? {
        // Create a renderer format with the appropriate scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale // Match the input image scale

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        let renderedImage = renderer.image { context in
            // Draw the original image
            image.draw(at: .zero)

            // Set the dot drawing properties for the perimeter
            context.cgContext.setFillColor(UIColor.purple.cgColor)

            // Draw each perimeter point as a dot
            for point in perimeter {
                // Draw a small circle (dot) at each perimeter point
                let rect = CGRect(x: point.x - dotSize / 2, y: point.y - dotSize / 2, width: dotSize, height: dotSize)
                context.cgContext.fillEllipse(in: rect)
            }
        
        }

        return renderedImage
    }
    
    static func drawContourAndDots(on image: UIImage, closestContour: [CGPoint], tips: [CGPoint]) -> UIImage? {
        // Create a renderer format with the appropriate scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale // Match the input image scale

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        let renderedImage = renderer.image { context in
            // Draw the original image
            image.draw(at: .zero)

            // Set the dot drawing properties
            context.cgContext.setFillColor(UIColor.cyan.cgColor)

            // Draw each tip as a dot
            for tip in tips {
                let dotSize: CGFloat = 8.0
                let rect = CGRect(x: tip.x - dotSize / 2, y: tip.y - dotSize / 2, width: dotSize, height: dotSize)
                context.cgContext.fillEllipse(in: rect)
            }
        }

        return renderedImage
    }
    
    static func drawDotsAndLine(on image: UIImage, points: [CGPoint], dotSize: CGFloat = 20.0, lineWidth: CGFloat = 5.0, dotColor: UIColor? = nil, lineColor: UIColor? = nil) -> UIImage? {
        guard points.count == 2 else {
            print("Error: The function requires exactly two points.")
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale // Match the input image scale

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        let renderedImage = renderer.image { context in
            // Draw the original image
            image.draw(at: .zero)

            // Set the drawing properties
            let dotUIColor = dotColor ?? UIColor.green
            let lineUIColor = lineColor ?? UIColor.blue

            context.cgContext.setFillColor(dotUIColor.cgColor)  // Dot color
            context.cgContext.setStrokeColor(lineUIColor.cgColor)  // Line color
            context.cgContext.setLineWidth(lineWidth)

            // Draw dots
            for point in points {
                let rect = CGRect(x: point.x - dotSize / 2, y: point.y - dotSize / 2, width: dotSize, height: dotSize)
                context.cgContext.fillEllipse(in: rect)
            }

            // Draw line connecting the two points
            context.cgContext.move(to: points[0])
            context.cgContext.addLine(to: points[1])
            context.cgContext.strokePath()
        }

        return renderedImage
    }
    
    static func drawDot(on image: UIImage, point: CGPoint, dotSize: CGFloat = 20.0, dotColor: UIColor? = nil) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale // Match the input image scale

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        let renderedImage = renderer.image { context in
            // Draw the original image
            image.draw(at: .zero)

            // Set the drawing properties
            let dotUIColor = dotColor ?? UIColor.red

            context.cgContext.setFillColor(dotUIColor.cgColor)  // Dot color

            // Draw dot
            let rect = CGRect(x: point.x - dotSize / 2, y: point.y - dotSize / 2, width: dotSize, height: dotSize)
            context.cgContext.fillEllipse(in: rect)
        }

        return renderedImage
    }
    
    static func createGridTexture(size: Int, gridColor: UIColor, backgroundColor: UIColor = .clear) -> UIImage {
        let scale = UIScreen.main.scale
        let gridSize = CGFloat(size)

        UIGraphicsBeginImageContextWithOptions(CGSize(width: gridSize, height: gridSize), false, scale)
        let context = UIGraphicsGetCurrentContext()!

        // Fill the background with transparent color
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: gridSize, height: gridSize))

        // Draw vertical lines with semi-transparent grid color
        context.setStrokeColor(gridColor.withAlphaComponent(0.5).cgColor) // Adjust alpha here
        context.setLineWidth(2.0)
        for x in stride(from: 0, to: Int(gridSize), by: size / 10) {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: Int(gridSize)))
        }

        // Draw horizontal lines with semi-transparent grid color
        for y in stride(from: 0, to: Int(gridSize), by: size / 10) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: Int(gridSize), y: y))
        }

        context.strokePath()

        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        return image
    }
    
    // Draws a grayscale UIImage from the depth map, with (x, y) highlighted in red.
    static func drawDepthMapPointOverlay(depthMap: CVPixelBuffer, x: Int, y: Int) -> UIImage? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)

        // Normalize depth values to 0...1 range for grayscale image
        var maxDepth: Float = 0
        var minDepth: Float = .greatestFiniteMagnitude
        for i in 0..<(width * height) {
            let d = floatBuffer[i]
            if d > 0 {
                maxDepth = max(maxDepth, d)
                minDepth = min(minDepth, d)
            }
        }

        let scale = 255.0 / max(maxDepth - minDepth, 0.001)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }

        guard let ctxData = context.data else { return nil }
        let buffer = ctxData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for row in 0..<height {
            for col in 0..<width {
                let index = row * width + col
                let depth = floatBuffer[index]
                let normalized = UInt8(max(0, min(255, (depth - minDepth) * scale)))
                let isTarget = (col == x && row == y)
                let pixelColor: (UInt8, UInt8, UInt8) = isTarget ? (0, 255, 0) : (normalized, normalized, normalized)
                let offset = (row * width + col) * 4
                buffer[offset] = pixelColor.0
                buffer[offset+1] = pixelColor.1
                buffer[offset+2] = pixelColor.2
                buffer[offset+3] = 255
            }
        }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }

}
