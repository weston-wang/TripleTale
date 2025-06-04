//
//  UIViewController+Popups.swift
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

/// - Tag: UIViewController
extension UIViewController {
    func showPopupMessage(title: String?, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        present(alert, animated: true, completion: nil)
    }
    
    func showImagePopup(combinedImage: UIImage, orientation: UIImage.Orientation) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)

        // Create a new image with the specified orientation
        let orientedImage = UIImage(cgImage: combinedImage.cgImage!, scale: combinedImage.scale, orientation: orientation)

        // Create an image view with the oriented image
        let imageView = UIImageView(image: orientedImage)
        imageView.contentMode = .scaleAspectFit

        // Set the desired width and height for the image view with padding
        let maxWidth: CGFloat = 270
        let maxHeight: CGFloat = 480

        // Calculate the aspect ratio
        let aspectRatio = orientedImage.size.width / orientedImage.size.height

        // Determine the width and height based on the aspect ratio
        var imageViewWidth = maxWidth
        var imageViewHeight = maxWidth / aspectRatio

        if imageViewHeight > maxHeight {
            imageViewHeight = maxHeight
            imageViewWidth = maxHeight * aspectRatio
        }

        // Create a container view for the image view to add constraints
        let containerView = UIView()
        containerView.addSubview(imageView)

        // Set up auto layout constraints
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: imageViewWidth),
            imageView.heightAnchor.constraint(equalToConstant: imageViewHeight),
            imageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: imageViewWidth + 20),  // Adding padding
            containerView.heightAnchor.constraint(equalToConstant: imageViewHeight + 20) // Adding padding
        ])

        // Add the container view to the alert controller
        alert.view.addSubview(containerView)

        // Set up the container view's constraints within the alert view
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            containerView.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 20),
            containerView.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -45)
        ])

        // Add an action to dismiss the alert
        alert.addAction(UIAlertAction(title: "Fish on!", style: .default, handler: nil))

        // Present the alert controller
        present(alert, animated: true, completion: nil)
    }
    
    /// Shows a scrollable popup with multiple images horizontally.
    func showScrollableImagePopup(images: [UIImage]) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)

        // Create a scroll view
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Create a horizontal stack view to hold the images
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        for image in images {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(equalToConstant: 200).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 200).isActive = true
            stackView.addArrangedSubview(imageView)
        }

        // Container view for layout inside the alert
        let containerView = UIView()
        containerView.addSubview(scrollView)
        containerView.translatesAutoresizingMaskIntoConstraints = false

        // Add constraints to scrollView and stackView
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])

        // Add the container to the alert
        alert.view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 20),
            containerView.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -45),
            containerView.leadingAnchor.constraint(equalTo: alert.view.leadingAnchor, constant: 10),
            containerView.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -10),
            containerView.heightAnchor.constraint(equalToConstant: 220)
        ])

        alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil))

        self.present(alert, animated: true, completion: nil)
    }
    
    func showInputPopup(title: String?, message: String?, placeholders: [String], completion: @escaping ([Double?]) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        // Add text fields to the alert based on the provided placeholders
        for placeholder in placeholders {
            alert.addTextField { textField in
                textField.placeholder = placeholder
                textField.keyboardType = .decimalPad // Set keyboard type to decimal pad for double values
            }
        }
        
        // Add an action to submit the input
        let submitAction = UIAlertAction(title: "Submit", style: .default) { _ in
            let inputs = alert.textFields?.map { textField -> Double? in
                guard let text = textField.text, !text.isEmpty else {
                    return nil
                }
                return Double(text)
            }
            completion(inputs ?? [])
        }
        alert.addAction(submitAction)
        
        // Add a cancel action
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alert.addAction(cancelAction)
        
        // Present the alert controller
        present(alert, animated: true, completion: nil)
    }
}
