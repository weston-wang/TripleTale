//
//  MainFlow.swift
//  tripletalear
//
//  Created by Wes Wang on 8/19/24.
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
import Accelerate

func findDepthEllipseVertices(from image: UIImage, debug: Bool = false) -> ([CGPoint]?, (center: CGPoint, size: CGSize, rotationInDegrees: CGFloat)?, [CGPoint]?) {
    // get foreground mask
    guard let maskImage = CIImage(image: image) else { return (nil, nil, nil) }
    
    // turn into gray scale pixel data
    let context = CIContext()
    guard let cgImage = context.createCGImage(maskImage, from: maskImage.extent) else { return (nil, nil, nil) }
    guard let originalPixelData = convertCGImageToGrayscalePixelData(cgImage) else { return (nil, nil, nil) }
    
    // find all contours
    let width = cgImage.width
    let height = cgImage.height
    
    // Convert grayscale to binary using a threshold
    let threshold: UInt8 = UInt8(255 * 0.85) // 85% brightness
    let pixelData = thresholdGrayscaleImage(pixelData: originalPixelData, width: width, height: height, threshold: threshold)
    
    let (contours, perimeters) = extractContours(from: pixelData, width: width, height: height)
    
    // find center contour
    guard let closestContour = findContourClosestToCenter(contours: contours, imageWidth: width, imageHeight: height) else { return (nil, nil, nil) }
    
    // fit ellipse
    guard let ellipse = fitEllipseMinimax(to: closestContour) else { return (nil, nil, nil) }
    
    // find ellipse tips to use for measurements
    let size = CGSize(width: ellipse.size.width, height: ellipse.size.height)
    let tips = calculateEllipseTips(center: ellipse.center, size: size, rotation: ellipse.rotationInDegrees)
    
    // for debug display only
    if debug {
        let maskUiImage = maskImage.toUIImage()!
        let resultImage = drawContoursEllipseAndTips(on: maskUiImage, contours: contours, closestContour: closestContour, ellipse: (center: ellipse.center, size: size, rotation: ellipse.rotationInDegrees), tips: tips)
        
        saveImageToGallery(image)
        saveImageToGallery(resultImage!)
    }
    
    return (tips, ellipse, perimeters[0])
}



func findEllipseVertices(from image: UIImage, for portion: CGFloat, debug: Bool = false) -> [CGPoint]? {
    // get foreground mask
    guard let maskImage = generateMaskImage(from: image, for: portion) else { return nil }
    
    // turn into gray scale pixel data
    let context = CIContext()
    guard let cgImage = context.createCGImage(maskImage, from: maskImage.extent) else { return nil }
    guard let pixelData = convertCGImageToGrayscalePixelData(cgImage) else { return nil }

    // find all contours
    let width = cgImage.width
    let height = cgImage.height
    let (contours, _) = extractContours(from: pixelData, width: width, height: height)
    
    // find center contour
    guard let closestContour = findContourClosestToCenter(contours: contours, imageWidth: width, imageHeight: height) else { return nil }
    
    // fit ellipse
    guard let ellipse = fitEllipseMinimax(to: closestContour) else { return nil }
    
    // find ellipse tips to use for measurements
    let size = CGSize(width: ellipse.size.width, height: ellipse.size.height)
    let tips = calculateEllipseTips(center: ellipse.center, size: size, rotation: ellipse.rotationInDegrees)
    let intersections = findEllipseAxisIntersections(ellipse: ellipse, contour: closestContour, extendPercentage: 0)

    // for debug display only
    if debug {
//        let maskUiImage = maskImage.toUIImage()!
        
        let ellipseImage = drawEllipse(on: image, ellipse: (center: ellipse.center, size: size, rotationInDegrees: ellipse.rotationInDegrees), tips: tips)

        let perimeter = marchingSquares(from: closestContour)
        let perimImage = drawPerimeterDots(on: ellipseImage!, perimeter: perimeter)

        let pcaPoints = findFishTips(from: closestContour)
        let lineImage = drawDotsAndLine(on: perimImage!, points: [pcaPoints!.mouthTip, pcaPoints!.tailTip])
        
        let testImage = drawDotsAndLine(on: lineImage!, points: [intersections![1], intersections![3]], dotColor:UIColor.yellow, lineColor: UIColor.black)
        
//        saveImageToGallery(image)
//        saveImageToGallery(resultImage!)
//        saveImageToGallery(dotsImage!)
        saveImageToGallery(testImage!)
    }
    
    guard let intersections = findEllipseAxisIntersections(ellipse: ellipse, contour: closestContour, extendPercentage: 0) else {
        print("Error: Failed to find ellipse axis intersections.")
        return nil
    }

    let tipsNormalized = intersections.map { point in
        CGPoint(x: point.x / CGFloat(width), y: (CGFloat(height) - point.y) / CGFloat(height))
    }

    return tipsNormalized

}

func buildRealWorldVerticesAnchors(
    _ currentView: ARSCNView,
    _ normalizedVertices: [CGPoint],
    _ capturedImageSize: CGSize
) -> ([ARAnchor], ARAnchor?, ARAnchor?, [ARAnchor]) {
    
    var adjustedVertices = normalizedVertices
    var verticesAnchors = getVertices(currentView, adjustedVertices, capturedImageSize)
    
    // 🔄 Retry with small dithers until we get at least 4 anchors
    var attempt = 0
    while verticesAnchors.count < 4 && attempt < 5 {  // Limit retries to prevent infinite loops
        attempt += 1
        adjustedVertices = applySmallDither(to: adjustedVertices) // Slightly modify the points
        verticesAnchors = getVertices(currentView, adjustedVertices, capturedImageSize)
    }

    if verticesAnchors.count < 4 {
        print("Error: Expected 4 vertex anchors, but got \(verticesAnchors.count).")
        return ([], nil, nil, []) // Return safe fallback values
    }
    
    // Attempt to get centroid anchor
    guard let centroidAboveAnchor = getVerticesCenter(currentView, adjustedVertices, capturedImageSize) else {
        print("Error: Failed to retrieve centroid above anchor.")
        return ([], nil, nil, []) // Return safe fallback values
    }
    
    let corners = calculateRectangleCorners(adjustedVertices, 0.0, 0.7) // First one is tall, second is wide
    let cornerAnchors = getAngledCorners(currentView, corners, capturedImageSize)
    
    if cornerAnchors.isEmpty {
        print("Error: Failed to retrieve corner anchors.")
        return ([], centroidAboveAnchor, nil, []) // At least return the above centroid
    }
    
    guard let centroidBelowAnchor = createCentroidAnchor(from: cornerAnchors) else {
        print("Error: Failed to create centroid below anchor.")
        return ([], centroidAboveAnchor, nil, cornerAnchors) // Return corner anchors at least
    }

    // Attempt distance calculations safely
    guard let distanceToFish = calculateDistanceToObject(centroidAboveAnchor),
          let distanceToGround = calculateDistanceToObject(centroidBelowAnchor),
          distanceToGround != 0 else {
        print("Error: Invalid distances for scaling factor computation.")
        return ([], centroidAboveAnchor, centroidBelowAnchor, cornerAnchors)
    }
    
    let scalingFactor = distanceToFish / distanceToGround
//    let outwardedScalingFactor = scalingFactor * 1.1
    
//    verticesAnchors = stretchVertices(verticesAnchors, verticalScaleFactor: outwardedScalingFactor, horizontalScaleFactor: outwardedScalingFactor)
    
    return (verticesAnchors, centroidAboveAnchor, centroidBelowAnchor, cornerAnchors)
}

func generateResultImage(_ inputImage: UIImage,
                         _ inputBoundingBox: CGRect? = nil,
                         _ widthInInches: Measurement<UnitLength>,
                         _ lengthInInches: Measurement<UnitLength>,
                         _ heightInInches: Measurement<UnitLength>,
                         _ circumferenceInInches: Measurement<UnitLength>,
                         _ weightInLb: Measurement<UnitMass>,
                         _ fishName: String,
                         debug: Bool = false) -> UIImage? {
//    let boundingBox = inputBoundingBox ?? CGRect(origin: .zero, size: inputImage.size)
    
    let rawLength = lengthInInches.value
    let roundedLength = floor(rawLength * 4) / 4.0
    let formattedLength = String(format: "%.2f", roundedLength)

    //    let formattedWeight = String(format: "%.2f", weightInLb.value)
    let formattedWidth = String(format: "%.2f", widthInInches.value)
    let formattedHeight = String(format: "%.2f", heightInInches.value)
    let formattedCircumference = String(format: "%.2f", circumferenceInInches.value)

//    let tempImage = inputImage.drawBoundingBox(inputBoundingBox!)
//    let tempImage = drawBracketsOnImage(image: inputImage, boundingBox: boundingBox)
//        self.anchorLabels[midpointAnchors[4].identifier] = "\(formattedWeight) lb, \(formattedLength) in "
//    let imageWithBox = drawBracketsOnImage(image: inputImage, boundingBoxes: [boundingBox])
//    let pt = CGPoint(x: 10, y: inputImage.size.height - 300)
//
//    let imageWithBox = tempImage.imageWithText(fishName, atPoint: pt, fontSize: 36, textColor: UIColor.white)

//    let weightTextImage = imageWithBox!.imageWithCenteredText("\(fishName) \n \(formattedWeight) lb", fontSize: 180, textColor: UIColor.white)
//    let weightTextImage = inputImage.imageWithCenteredText("\(formattedWeight) lb \n \(formattedLength) in", fontSize: 180, textColor: UIColor.white)
    let weightTextImage = inputImage.imageWithCenteredText("\(formattedLength) in", fontSize: 180, textColor: UIColor.white)

    let point = CGPoint(x: 10, y: weightTextImage!.size.height - 80)


    let combinedImage = weightTextImage

    saveImageToGallery(combinedImage!)

    if debug {
        let measurementTextImage = weightTextImage?.imageWithText("L \(formattedLength) in x W \(formattedWidth) in x H \(formattedHeight) in, C \(formattedCircumference) in", atPoint: point, fontSize: 40, textColor: UIColor.white)
        
        //    let overlayImage = UIImage(named: "shimano_logo")!
        //    let combinedImage = measurementTextImage!.addImageToBottomRightCorner(overlayImage: overlayImage)
        
        saveImageToGallery(measurementTextImage!)
    }
    return combinedImage!
}


func generateDebugImage(_ inputImage: UIImage, _ faceBoundingBox: CGRect, _ faceLocation: VNPoint, _ faceDistance: CGFloat, _ leftWristLocation: VNPoint, _ leftWristDistance: CGFloat, _ rightWristLocation: VNPoint, _ rightWristDistance: CGFloat, _ closestContour: [CGPoint], _ ellipse: (center: CGPoint, size: CGSize, rotationInDegrees: CGFloat), _ tips: [CGPoint], _ fishLength: CGFloat) -> UIImage? {

    // step 1: draw face box
    var faceImage = drawBracketsOnImage(image: inputImage, boundingBox: faceBoundingBox)

    // step 2: add face distance text below
    var pt = convertNormalizedPointToCGPoint(faceLocation.location, imageSize: inputImage.size)
    pt.y = pt.y - 20
    pt.x = pt.x + 10
    
    faceImage = faceImage.drawVNPoint(faceLocation)!
    faceImage = faceImage.imageWithText("\(String(format: "%.2f", faceDistance)) ft", atPoint: pt, fontSize: 36, textColor: UIColor.white)!
    
    var facePoint = faceBoundingBox.origin
    facePoint.y = facePoint.y - 50
    facePoint.x = facePoint.x + 10
    faceImage = faceImage.imageWithText("\(String(format: "%.2f", faceBoundingBox.height)) px", atPoint: facePoint, fontSize: 36, textColor: UIColor.white)!

    // step 3: draw fish
    let perimeter = marchingSquares(from: closestContour)
    var fishImage = drawPerimeterDots(on: faceImage, perimeter: perimeter)
    fishImage = drawEllipse(on: fishImage!, ellipse: ellipse, tips: tips)
    
    var fishPt = tips[1]
    fishPt.y = fishPt.y - 20
    fishPt.x = fishPt.x + 10
    
    fishImage = fishImage!.imageWithText("\(String(format: "%.2f", fishLength)) px", atPoint: fishPt, fontSize: 36, textColor: UIColor.white)!

    // step 4: draw wrists
    var leftPt = convertNormalizedPointToCGPoint(leftWristLocation.location, imageSize: inputImage.size)
    leftPt.y = leftPt.y - 20
    leftPt.x = leftPt.x + 10
    
    var rightPt = convertNormalizedPointToCGPoint(rightWristLocation.location, imageSize: inputImage.size)
    rightPt.y = rightPt.y - 20
    rightPt.x = rightPt.x + 10
    
    var wristImage = fishImage!.drawVNPoint(leftWristLocation)
    wristImage = wristImage!.imageWithText("\(String(format: "%.2f", leftWristDistance)) ft", atPoint: leftPt, fontSize: 36, textColor: UIColor.white)!
    
    wristImage = wristImage!.drawVNPoint(rightWristLocation)
    wristImage = wristImage!.imageWithText("\(String(format: "%.2f", rightWristDistance)) ft", atPoint: rightPt, fontSize: 36, textColor: UIColor.white)!

    return wristImage
}

func findEllipseAxisIntersections(
    ellipse: (center: CGPoint, size: CGSize, rotationInDegrees: CGFloat),
    contour: [CGPoint],
    extendPercentage: CGFloat = 0.0  // Default: no extension
) -> [CGPoint]? {
    
    let center = ellipse.center
    let angle = ellipse.rotationInDegrees * .pi / 180.0  // Convert to radians
    
    // Compute unit vectors for major and minor axes
    let majorAxisDir = CGPoint(x: cos(angle), y: sin(angle))  // Major axis direction
    let minorAxisDir = CGPoint(x: -sin(angle), y: cos(angle)) // Minor axis direction
    
    let threshold: CGFloat = 3.0  // Allowable distance from the infinite axis
    
    // Function to find the extreme intersection points along an axis
    func findExtremeIntersections(direction: CGPoint) -> [CGPoint] {
        var intersections: [CGPoint] = []
        var posExtreme: CGPoint? = nil
        var negExtreme: CGPoint? = nil
        var maxPosProj: CGFloat = -CGFloat.infinity
        var maxNegProj: CGFloat = CGFloat.infinity
        
        for point in contour {
            let relativePoint = CGPoint(x: point.x - center.x, y: point.y - center.y)
            
            // Projection of the point onto the axis
            let projection = relativePoint.x * direction.x + relativePoint.y * direction.y
            
            // Compute distance from the axis (perpendicular distance)
            let distanceToAxis = abs(relativePoint.x * direction.y - relativePoint.y * direction.x)
            
            // Keep only points near the infinite axis
            if distanceToAxis < threshold {
                if projection > maxPosProj {
                    maxPosProj = projection
                    posExtreme = point
                }
                if projection < maxNegProj {
                    maxNegProj = projection
                    negExtreme = point
                }
            }
        }
        
        if let pos = posExtreme { intersections.append(pos) }
        if let neg = negExtreme { intersections.append(neg) }
        
        return intersections
    }
    
    // Find intersections for both major and minor axes
    var majorIntersections = findExtremeIntersections(direction: majorAxisDir)
    var minorIntersections = findExtremeIntersections(direction: minorAxisDir)
    
    // Ensure exactly 4 intersections (2 per axis)
    guard majorIntersections.count == 2, minorIntersections.count == 2 else {
        return nil
    }
    
    // Function to extend a point along a given direction vector
    func extendPoint(_ point: CGPoint, direction: CGPoint, distance: CGFloat) -> CGPoint {
        return CGPoint(x: point.x + direction.x * distance, y: point.y + direction.y * distance)
    }
    
    // Compute extension distances
    let majorDist = distanceBetween(majorIntersections[0], majorIntersections[1])
    let minorDist = distanceBetween(minorIntersections[0], minorIntersections[1])
    
    let majorExtension = majorDist * extendPercentage / 100.0
    let minorExtension = minorDist * extendPercentage / 100.0
    
    // Extend the intersection points outward
    majorIntersections[0] = extendPoint(majorIntersections[0], direction: majorAxisDir, distance: majorExtension)
    majorIntersections[1] = extendPoint(majorIntersections[1], direction: majorAxisDir, distance: -majorExtension)
    
    minorIntersections[0] = extendPoint(minorIntersections[0], direction: minorAxisDir, distance: minorExtension)
    minorIntersections[1] = extendPoint(minorIntersections[1], direction: minorAxisDir, distance: -minorExtension)
    
    // Sort into consistent order: [top, right, bottom, left]
    var top: CGPoint?, right: CGPoint?, bottom: CGPoint?, left: CGPoint?

    for point in minorIntersections {
        if point.y < center.y {
            top = point
        } else {
            bottom = point
        }
    }

    for point in majorIntersections {
        if point.x > center.x {
            right = point
        } else {
            left = point
        }
    }

    // Ensure correct order: [top, right, bottom, left]
    guard let topFinal = top, let rightFinal = right, let bottomFinal = bottom, let leftFinal = left else {
        return nil
    }

    return [topFinal, rightFinal, bottomFinal, leftFinal]
}

func findFishTips(from contour: [CGPoint]) -> (mouthTip: CGPoint, tailTip: CGPoint)? {
    
    guard contour.count > 1 else { return nil }

    // Compute the centroid of the contour
    let centerX = contour.map { $0.x }.reduce(0, +) / CGFloat(contour.count)
    let centerY = contour.map { $0.y }.reduce(0, +) / CGFloat(contour.count)
    let centroid = CGPoint(x: centerX, y: centerY)

    // Perform Principal Component Analysis (PCA) to get the major axis direction
    let (eigenvector, _) = performPCA(on: contour)

    // Project contour points onto the major axis
    var minProj: CGFloat = CGFloat.infinity
    var maxProj: CGFloat = -CGFloat.infinity
    var mouthTip: CGPoint? = nil
    var tailTip: CGPoint? = nil

    for point in contour {
        let relativePoint = CGPoint(x: point.x - centroid.x, y: point.y - centroid.y)
        let projection = relativePoint.x * eigenvector.x + relativePoint.y * eigenvector.y

        if projection < minProj {
            minProj = projection
            mouthTip = point
        }
        if projection > maxProj {
            maxProj = projection
            tailTip = point
        }
    }

    guard let mouth = mouthTip, let tail = tailTip else { return nil }
    return (mouth, tail)
}

func performPCA(on points: [CGPoint]) -> (direction: CGPoint, eigenvalues: (CGFloat, CGFloat)) {
    let meanX = points.map { $0.x }.reduce(0, +) / CGFloat(points.count)
    let meanY = points.map { $0.y }.reduce(0, +) / CGFloat(points.count)

    var covXX: CGFloat = 0, covXY: CGFloat = 0, covYY: CGFloat = 0

    for point in points {
        let dx = point.x - meanX
        let dy = point.y - meanY
        covXX += dx * dx
        covXY += dx * dy
        covYY += dy * dy
    }

    let trace = covXX + covYY
    let det = covXX * covYY - covXY * covXY
    let lambda1 = (trace + sqrt(trace * trace - 4 * det)) / 2
    let lambda2 = (trace - sqrt(trace * trace - 4 * det)) / 2

    let majorDirection: CGPoint
    if covXY != 0 {
        let vX = lambda1 - covYY
        let vY = covXY
        let length = sqrt(vX * vX + vY * vY)
        majorDirection = CGPoint(x: vX / length, y: vY / length)
    } else {
        majorDirection = covXX > covYY ? CGPoint(x: 1, y: 0) : CGPoint(x: 0, y: 1)
    }

    return (majorDirection, (lambda1, lambda2))
}
