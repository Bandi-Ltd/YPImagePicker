//
//  YPCropVC.swift
//  YPImagePicker
//
//  Created by Sacha DSO on 12/02/2018.
//  Copyright © 2018 Yummypets. All rights reserved.
//

import UIKit

public enum YPCropType {
    case none
    case rectangle(ratio: Double)
}

class YPCropVC: UIViewController {
    
    public var didFinishCropping: ((UIImage) -> Void)?
    
    override var prefersStatusBarHidden: Bool { return YPConfig.hidesStatusBar }
    
    private let originalImage: UIImage
    private let pinchGR = UIPinchGestureRecognizer()
    private let panGR = UIPanGestureRecognizer()
    
    private let v: YPCropView
    override func loadView() { view = v }
    
    required init(image: UIImage, ratio: Double) {
        v = YPCropView(image: image, ratio: ratio)
        originalImage = image
        super.init(nibName: nil, bundle: nil)
        self.title = YPConfig.wordings.crop
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //        setupToolbar()
        setupGestureRecognizers()
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: imageFromBundle("yp_next").withRenderingMode(.alwaysOriginal), style: .plain, target: self, action: #selector(done))
        navigationItem.rightBarButtonItem?.tintColor = YPConfig.colors.tintColor
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: imageFromBundle("yp_back").withRenderingMode(.alwaysOriginal), style: .plain, target: self, action: #selector(cancel))
        
        view.backgroundColor = YPConfig.colors.safeAreaBackgroundColor
        v.backgroundColor = YPConfig.colors.safeAreaBackgroundColor
    }
    
    //    func setupToolbar() {
    //        let cancelButton = UIBarButtonItem(title: YPConfig.wordings.cancel,
    //                                           style: .plain,
    //                                           target: self,
    //                                           action: #selector(cancel))
    //        cancelButton.tintColor = .ypLabel
    //        cancelButton.setFont(font: YPConfig.fonts.leftBarButtonFont, forState: .normal)
    //
    //        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    //
    //        let saveButton = UIBarButtonItem(title: YPConfig.wordings.save,
    //                                           style: .plain,
    //                                           target: self,
    //                                           action: #selector(done))
    //        saveButton.setFont(font: YPConfig.fonts.rightBarButtonFont, forState: .normal)
    //        saveButton.tintColor = .ypLabel
    //        v.toolbar.items = [cancelButton, flexibleSpace, saveButton]
    //    }
    
    func setupGestureRecognizers() {
        // Pinch Gesture
        pinchGR.addTarget(self, action: #selector(pinch(_:)))
        pinchGR.delegate = self
        v.imageView.addGestureRecognizer(pinchGR)
        
        // Pan Gesture
        panGR.addTarget(self, action: #selector(pan(_:)))
        panGR.delegate = self
        v.imageView.addGestureRecognizer(panGR)
    }
    
    @objc
    func cancel() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc
    func done() {
        guard let image = v.imageView.image else {
            return
        }
        
        let xCrop = v.cropArea.frame.minX - v.imageView.frame.minX
        let yCrop = v.cropArea.frame.minY - v.imageView.frame.minY
        let widthCrop = v.cropArea.frame.width
        let heightCrop = v.cropArea.frame.height
        let scaleRatio = image.size.width / v.imageView.frame.width
        let scaledCropRect = CGRect(x: xCrop * scaleRatio,
                                    y: yCrop * scaleRatio,
                                    width: widthCrop * scaleRatio,
                                    height: heightCrop * scaleRatio)
        if let cgImage = image.toCIImage()?.toCGImage(),
           let imageRef = cgImage.cropping(to: scaledCropRect) {
            let croppedImage = UIImage(cgImage: imageRef)
            didFinishCropping?(croppedImage)
        }
    }
}

extension YPCropVC: UIGestureRecognizerDelegate {
    
    // MARK: - Pinch Gesture
    
    @objc
    func pinch(_ sender: UIPinchGestureRecognizer) {
        // TODO: Zoom where the fingers are (more user friendly)
        switch sender.state {
        case .began, .changed:
            var transform = v.imageView.transform
            // Apply zoom level.
            transform = transform.scaledBy(x: sender.scale,
                                           y: sender.scale)
            v.imageView.transform = transform
        case .ended:
            pinchGestureEnded()
        case .cancelled, .failed, .possible:
            ()
        @unknown default:
            fatalError()
        }
        // Reset the pinch scale.
        sender.scale = 1.0
    }
    
    private func pinchGestureEnded() {
        var transform = v.imageView.transform
        let kMinZoomLevel: CGFloat = 1.0
        let kMaxZoomLevel: CGFloat = 3.0
        var wentOutOfAllowedBounds = false
        
        // Prevent zooming out too much
        if transform.a < kMinZoomLevel {
            transform = .identity
            wentOutOfAllowedBounds = true
        }
        
        // Prevent zooming in too much
        if transform.a > kMaxZoomLevel {
            transform.a = kMaxZoomLevel
            transform.d = kMaxZoomLevel
            wentOutOfAllowedBounds = true
        }
        
        // Animate coming back to the allowed bounds with a haptic feedback.
        if wentOutOfAllowedBounds {
            generateHapticFeedback()
            UIView.animate(withDuration: 0.3, animations: {
                self.v.imageView.transform = transform
            })
        }
    }
    
    func generateHapticFeedback() {
        if #available(iOS 10.0, *) {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
    
    // MARK: - Pan Gesture
    
    @objc
    func pan(_ sender: UIPanGestureRecognizer) {
        let translation = sender.translation(in: view)
        let imageView = v.imageView
        
        // Apply the pan translation to the image.
        imageView.center = CGPoint(x: imageView.center.x + translation.x, y: imageView.center.y + translation.y)
        
        // Reset the pan translation.
        sender.setTranslation(CGPoint.zero, in: view)
        
        if sender.state == .ended {
            keepImageIntoCropArea()
        }
    }
    
    private func keepImageIntoCropArea() {
        let imageRect = v.imageView.frame
        let cropRect = v.cropArea.frame
        
        var dy: CGFloat = 0
        var dx: CGFloat = 0
        
        // Cap Top.
        if imageRect.minY > cropRect.minY {
            dy = imageRect.origin.y - cropRect.minY
        }
        
        // Cap Bottom.
        if imageRect.maxY < cropRect.maxY {
            dy = imageRect.origin.y - (cropRect.maxY - imageRect.height)
        }
        
        // Cap Left.
        if imageRect.minX > cropRect.minX {
            dx = imageRect.origin.x - cropRect.minX
        }
        
        // Cap Right.
        if imageRect.maxX < cropRect.maxX {
            dx = imageRect.origin.x - (cropRect.maxX - imageRect.width)
        }
        
        // Animate back to allowed bounds
        if dx != 0 || dy != 0 {
            UIView.animate(withDuration: 0.3, animations: {
                self.v.imageView.center = CGPoint(x: self.v.imageView.center.x - dx, y: self.v.imageView.center.y - dy)
            })
        }
    }
    
    /// Allow both Pinching and Panning at the same time.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
