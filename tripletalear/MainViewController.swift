//
//  ViewController.swift
//  tripletalear
//
//  Created by Wes Wang on 8/18/24.
//

import UIKit
import SceneKit
import ARKit
import Vision
import CoreMotion

class MainViewController: UIViewController, ARSCNViewDelegate {

    var sceneView: ARSCNView!
    
    private var tapCounter = 0
    var scaleFactor: Double = 500.0
    var lengthNudge: Double = 1.2
    var widthNudge: Double = 1.2
    
    private var freezeButton: UIButton?
    private var isFrozen = false
    
    var bracketView: BracketView?
    private var imagePortion: CGFloat = 1.0

    let motionManager = CMMotionManager()
    private var isForwardFacing = false

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView = ARSCNView(frame: self.view.frame)
        sceneView.delegate = self
        view.addSubview(sceneView)
        
        // Add the bracket view to the main view
        bracketView = BracketView(frame: view.bounds)
        bracketView?.isUserInteractionEnabled = false // Make sure it doesn't intercept touch events
        view.addSubview(bracketView!)
        
        // Add the freeze button and other UI elements
        freezeButton = createFreezeButton()
        view.addSubview(freezeButton!)

        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)
        
        // Initial bracket update
        updateBracketSize()
        
        
        // Check if the motion is available
        guard motionManager.isDeviceMotionAvailable else {
            print("Motion Sensor is not available")
            return
        }
        
        // Start Device Motion Updates
        motionManager.startDeviceMotionUpdates(to: .main) { (motion, error) in
            guard let motion = motion else { return }
            
            let previousFacing = self.isForwardFacing
            self.isForwardFacing = self.detectOrientation(attitude: motion.attitude)
            
            if self.isForwardFacing != previousFacing {
                
                // Update the bracket size based on the current state
                self.updateBracketSize()
            }
        }
        
        
        // Create a transparent view for the bottom left corner
        let cornerView = UIView()
        cornerView.translatesAutoresizingMaskIntoConstraints = false
        cornerView.backgroundColor = UIColor.clear
        view.addSubview(cornerView)
        
        // Set constraints to position the view in the bottom left corner
        NSLayoutConstraint.activate([
            cornerView.widthAnchor.constraint(equalToConstant: 100), // Adjust size as needed
            cornerView.heightAnchor.constraint(equalToConstant: 100), // Adjust size as needed
            cornerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            cornerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        ])
        
        // Add tap gesture recognizer to the corner view
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        cornerView.addGestureRecognizer(tapGesture)
        
    }

    
    @objc private func handleTapGesture() {
        tapCounter += 1
        
        if tapCounter == 3 {
            tapCounter = 0 // Reset counter after showing the popup
            
            // Show the input popup
            showInputPopup(title: "Developer Mode", message: "Update Values Below", placeholders: [
                "Weight Scale: \(self.scaleFactor)",
                "Length Scale: \(self.lengthNudge)",
                "Width Scale: \(self.widthNudge)"
            ]) { inputs in
                // Handle the user inputs here
                if let value1 = inputs[0] {
                    self.scaleFactor = value1
                }
                
                if let value2 = inputs[1] {
                    self.lengthNudge = value2
                }
                
                if let value3 = inputs[2] {
                    self.widthNudge = value3
                }
            }
        }
    }
    
    @objc func toggleFreeze() {
        DispatchQueue.main.async {
            self.isFrozen.toggle()  // Toggle the state of isFrozen
            
            let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
            feedbackGenerator.prepare()
            feedbackGenerator.impactOccurred()

            if self.isFrozen {
                if let image = self.captureFrameAsUIImage(from: self.sceneView) {
                    // Save the image to the photo album
                    saveImageToGallery(image)
                }
                
                self.isFrozen.toggle()
            }
        }
    }
    
    func createFreezeButton() -> UIButton {
        let button = UIButton(frame: CGRect(x: (view.bounds.width - 70)/2, y: view.bounds.height - 150, width: 70, height: 70))
        button.backgroundColor = .white
        button.layer.cornerRadius = 35
        button.clipsToBounds = true

        // Set the button images for different states
        button.setImage(UIImage(named: "measure"), for: .normal)
        button.setImage(UIImage(named: "pressed"), for: .highlighted)

        button.imageView?.contentMode = .scaleAspectFill

        button.isHidden = false

        button.addTarget(self, action: #selector(toggleFreeze), for: .touchUpInside)
        return button
    }
    
    func updateBracketSize() {
        guard let bracketView = bracketView else { return }
        
        // Define different sizes for forward-facing and not forward-facing
        let width: CGFloat
        let height: CGFloat
        if isForwardFacing {
            imagePortion = 0.6
            
            width = view.bounds.width * imagePortion // Example size for forward-facing, adjust as needed
            height = width * 16 / 9 // Maintain 9:16 aspect ratio
        } else {
            imagePortion = 0.85
            
            width = view.bounds.width * imagePortion // Example size for not forward-facing, adjust as needed
            height = width * 16 / 9 // Maintain 9:16 aspect ratio
        }
        
        let rect = CGRect(origin: CGPoint(x: view.bounds.midX - width / 2, y: view.bounds.midY - height / 2), size: CGSize(width: width, height: height))
        bracketView.updateBracket(rect: rect)
    }
    
    func detectOrientation(attitude: CMAttitude) -> Bool {
        return  attitude.pitch * 180 / .pi > 60.0
    }
    
    func captureFrameAsUIImage(from arSCNView: ARSCNView) -> UIImage? {
        // Capture the current view as a UIImage
        let image = arSCNView.snapshot()
        return image
    }
}
