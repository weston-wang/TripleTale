//
//  CameraViewController.swift
//  JPForensics
//
//  Created by Wes Wang on 10/6/23.
//

import UIKit
import CoreImage
import AVFoundation

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var captureButton: UIButton!

    var photoCaptureCompletion: ((UIImage?, UIImage?) -> Void)?

    var photoOutput: AVCapturePhotoOutput!

    var cameraOverlay: UIView?

    let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Cancel", for: .normal)
        
        // Set the title color to black
        button.setTitleColor(.black, for: .normal)
        
        // Set the background color to white
        button.backgroundColor = .white
        
        // Optional: Rounded corners
        button.layer.cornerRadius = 15
        button.clipsToBounds = true

        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    let messageLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.boldSystemFont(ofSize: 17)
        label.textAlignment = .center
//        label.backgroundColor = UIColor.black.withAlphaComponent(0.1)  // Semi-transparent background
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }()

    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupCamera()
        
        // Add the camera overlay if it's set
        if let overlay = cameraOverlay {
            view.addSubview(overlay)
        }
        
        // Add the cancel button to the view
        view.addSubview(cancelButton)
        
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)

        // Constraints for placing the cancel button at the bottom-left of the screen
        NSLayoutConstraint.activate([
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),  // specify desired width
            cancelButton.heightAnchor.constraint(equalToConstant: 40) // specify desired height
        ])
        
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            messageLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            messageLabel.heightAnchor.constraint(equalToConstant: 50)  // Adjust as needed
        ])
    }
    
    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo

        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInUltraWideCamera,
            .builtInWideAngleCamera,
            .builtInDualCamera,
            .builtInTrueDepthCamera,
            .builtInLiDARDepthCamera
        ]
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(
           deviceTypes: deviceTypes,
           mediaType: .video,
           position: .back
        )

        var cameraDevice: AVCaptureDevice?

        // Separate the camera and LiDAR devices
        for device in deviceDiscoverySession.devices {
            if device.deviceType == .builtInLiDARDepthCamera {
                cameraDevice = device
                break
            }
        }

        if let camera = cameraDevice {
            do {
                let cameraInput = try AVCaptureDeviceInput(device: camera)
                if captureSession.canAddInput(cameraInput) {
                    captureSession.addInput(cameraInput)
                    print("Camera added: \(camera.localizedName)")
                }
            } catch {
                print("Failed to add camera input: \(error)")
                return
            }
        } else {
            print("No suitable camera found.")
            return
        }

        // Add photo and video outputs
        photoOutput = AVCapturePhotoOutput()
        
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            if photoOutput.isDepthDataDeliverySupported {
                photoOutput.isDepthDataDeliveryEnabled = true
                print("Depth Data Delivery is supported and enabled.")
            } else {
                print("Depth Data Delivery is not supported on this device.")
            }
            print("Photo output added.")
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            print("Video output added.")
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.frame
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        // Here you can add your overlay view and other UI components
        
        captureButton = UIButton(frame: CGRect(x: (view.bounds.width - 70)/2, y: view.bounds.height - 150, width: 70, height: 70))
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(captureButton)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            
            DispatchQueue.main.async {
                // If you have any UI updates related to the camera setup, do them here
            }
        }
    }
    
    func updateMessageLabel(with text: String) {
        messageLabel.text = text
        messageLabel.textColor = UIColor.red
    }

    @objc func capturePhoto() {
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()
        
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        // Check and enable depth data in settings
        if photoOutput.isDepthDataDeliveryEnabled {
            settings.isDepthDataDeliveryEnabled = true
            print("Configured settings to capture depth data.")
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    @objc func cancelButtonTapped() {
        photoCaptureCompletion?(nil, nil)
        dismiss(animated: true, completion: nil)
    }
}

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func cgImage(from ciImage: CIImage) -> CGImage? {
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
    
    func extractTarget(from image: CIImage) -> CIImage {
        let scale = image.extent.width / UIScreen.main.bounds.height
        let screenRectangle = UIScreen.main.fullScreenThreeTwoRectangle()
        let newWidth = screenRectangle.height * scale
        let newHeight = screenRectangle.width * scale
        
        let newOffsetW = screenRectangle.origin.y * scale
        let newOffsetH = screenRectangle.origin.x * scale  + (image.extent.height - UIScreen.main.bounds.width * scale)/2
        
        let scaledRectangle = CGRect(x: newOffsetW, y: newOffsetH , width: newWidth, height: newHeight)

        return image.cropped(to: scaledRectangle)
    }
    
    func createUIImage(from ciImage: CIImage) -> UIImage? {
        let context = CIContext(options: nil)
        
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            return UIImage(cgImage: cgImage)
        } else {
            return nil
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        self.captureButton.isEnabled = false
        
        guard let data = photo.fileDataRepresentation(), let capturedImage = UIImage(data: data) else {
            print("Error capturing or converting the photo")
            return
        }

        let ciImage = CIImage(cgImage: capturedImage.cgImage!)
        
        print("Camera UIImage size: \(ciImage.extent.width) x \(ciImage.extent.height)")

        let rotation = CGAffineTransform(rotationAngle: -.pi / 2)
        let rotatedCIImage = ciImage.transformed(by: rotation)

        // Convert CIImage to UIImage
        let colorImage = createUIImage(from: rotatedCIImage)

        // Check for depth data
        var depthDataImage: UIImage? = nil
        if let depthData = photo.depthData {
            let depthCIImage = CIImage(cvPixelBuffer: depthData.depthDataMap)
            let rotatedDepthCIImage = depthCIImage.transformed(by: rotation)
            let context = CIContext(options: nil)
            if let cgImage = context.createCGImage(rotatedDepthCIImage, from: rotatedDepthCIImage.extent) {
                depthDataImage = UIImage(cgImage: cgImage)
            }
        }

        print("Depth Data UIImage size (points): \(depthDataImage!.size.width) x \(depthDataImage!.size.height)")

        DispatchQueue.main.async {
            self.dismiss(animated: true) {
                self.photoCaptureCompletion?(colorImage, depthDataImage)
            }
        }
    }
    
}
