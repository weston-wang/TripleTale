//
//  DepthDataProcessor.swift
//  TripleTale
//
//  Created by Wes Wang on 5/3/24.
//
import AVFoundation
import UIKit

class DepthDataProcessor: NSObject, AVCaptureDepthDataOutputDelegate {
    var lastDepthData: AVDepthData?
    
    var session: AVCaptureSession = AVCaptureSession() // Defined as a class-wide property

    func setupCamera() {
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }

        session.addInput(input)
        let depthOutput = AVCaptureDepthDataOutput()
        depthOutput.isFilteringEnabled = true

        if session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            depthOutput.setDelegate(self, callbackQueue: DispatchQueue(label: "com.example.depthDataQueue"))
            session.startRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        // Convert the depth data to a format that can be easily manipulated if necessary
        let convertedDepthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        
        self.lastDepthData = convertedDepthData
        // Optionally, process this data to analyze or display
        DispatchQueue.main.async {
            self.processDepthData(convertedDepthData)
        }
    }

    func processDepthData(_ depthData: AVDepthData) {
        let depthDataMap = depthData.depthDataMap
        depthDataMap.normalize()

        // Example: accessing a specific pixel's depth
        let width = CVPixelBufferGetWidth(depthDataMap)
        let height = CVPixelBufferGetHeight(depthDataMap)
        CVPixelBufferLockBaseAddress(depthDataMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthDataMap, .readOnly) }

        let rowData = CVPixelBufferGetBaseAddress(depthDataMap)!.assumingMemoryBound(to: Float32.self)
        // Choose a pixel near the center or a meaningful location
        let pixelIndex = (height / 2) * width + (width / 2)
        let distanceAtCenter = rowData[pixelIndex]

        print("Distance at center: \(distanceAtCenter) meters")
    }
}

extension CVPixelBuffer {
    func normalize() {
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        CVPixelBufferLockBaseAddress(self, .readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(self)!.assumingMemoryBound(to: Float.self)
        
        var minDepth: Float = Float.greatestFiniteMagnitude
        var maxDepth: Float = 0

        for y in 0..<height {
            for x in 0..<width {
                let pixel = baseAddress[y * width + x]
                if pixel > 0 { // Check if depth data is valid
                    minDepth = min(minDepth, pixel)
                    maxDepth = max(maxDepth, pixel)
                }
            }
        }

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * width + x
                if baseAddress[pixelIndex] > 0 {
                    baseAddress[pixelIndex] = (baseAddress[pixelIndex] - minDepth) / (maxDepth - minDepth)
                }
            }
        }
        
        CVPixelBufferUnlockBaseAddress(self, .readOnly)
    }
    
}

extension DepthDataProcessor {
    func stopCamera() {
        session.stopRunning()
    }
}
