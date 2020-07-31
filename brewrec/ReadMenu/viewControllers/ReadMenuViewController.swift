//
//  ReadMenuViewController.swift
//  brewrec
//
//  Created by Daniel Martinez Condinanza on 3/9/19.
//  Copyright © 2019 danielm. All rights reserved.
//

import Firebase
import AVFoundation
import CoreVideo
import UIKit

class ReadMenuViewController: UIViewController {
    
    // MARK: - IBOutlets
    
    @IBOutlet private weak var cameraView: UIView!
    
    // MARK: - Properties
    
    private let detectors: [Detector] = [.onDeviceText]
    private var currentDetector: Detector = .onDeviceText
    private var isUsingFrontCamera = false
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    private lazy var captureSession = AVCaptureSession()
    private lazy var sessionQueue = DispatchQueue(label: Constant.sessionQueueLabel)
    private lazy var vision = Vision.vision()
    private var lastFrame: CMSampleBuffer?
    
    private lazy var previewOverlayView: UIImageView = {
        precondition(isViewLoaded)
        let previewOverlayView = UIImageView(frame: .zero)
        previewOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return previewOverlayView
    }()
    
    private lazy var annotationOverlayView: UIView = {
        precondition(isViewLoaded)
        let annotationOverlayView = UIView(frame: .zero)
        annotationOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return annotationOverlayView
    }()
    
    // MARK: - Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        
        setUpPreviewOverlayView()
        setUpAnnotationOverlayView()
        setUpCaptureSessionOutput()
        setUpCaptureSessionInput()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        startSession()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        stopSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        previewLayer.frame = cameraView.frame
    }
    
    // MARK: - Actions
    
    @IBAction func selectDetector(sender: AnyObject) {
        presentDetectorsAlertController()
    }
    
    @IBAction func switchCamera(sender: AnyObject) {
        isUsingFrontCamera = !isUsingFrontCamera
        removeDetectionAnnotations()
        setUpCaptureSessionInput()
    }
    
    private func recognizeTextOnDevice(in image: VisionImage, width: CGFloat, height: CGFloat) {
        let textRecognizer = vision.onDeviceTextRecognizer()
        textRecognizer.process(image) { text, error in
            self.removeDetectionAnnotations()
            self.updatePreviewOverlayView()
            guard error == nil, let text = text else {
                print("On-Device text recognizer error: " +
                    "\(error?.localizedDescription ?? Constant.noResultsMessage)")
                return
            }
            // Blocks.
            for block in text.blocks {
                let points = self.convertedPoints(from: block.cornerPoints, width: width, height: height)
                UIUtilities.addShape(
                    withPoints: points,
                    to: self.annotationOverlayView,
                    color: UIColor.purple
                )
                
                // Lines.
                for line in block.lines {
                    let points = self.convertedPoints(from: line.cornerPoints, width: width, height: height)
                    UIUtilities.addShape(
                        withPoints: points,
                        to: self.annotationOverlayView,
                        color: UIColor.orange
                    )
                    
                    // Elements.
                    for element in line.elements {
                        let normalizedRect = CGRect(
                            x: element.frame.origin.x / width,
                            y: element.frame.origin.y / height,
                            width: element.frame.size.width / width,
                            height: element.frame.size.height / height
                        )
                        let convertedRect = self.previewLayer.layerRectConverted(
                            fromMetadataOutputRect: normalizedRect
                        )
                        UIUtilities.addRectangle(
                            convertedRect,
                            to: self.annotationOverlayView,
                            color: UIColor.green
                        )
                        let label = UILabel(frame: convertedRect)
                        label.text = element.text
                        label.adjustsFontSizeToFitWidth = true
                        self.annotationOverlayView.addSubview(label)
                    }
                }
            }
        }
    }
    
    // MARK: - Private
    
    private func setUpCaptureSessionOutput() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            // When performing latency tests to determine ideal capture settings,
            // run the app in 'release' mode to get accurate performance metrics
            self.captureSession.sessionPreset = AVCaptureSession.Preset.medium
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings =
                [(kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA]
            let outputQueue = DispatchQueue(label: Constant.videoDataOutputQueueLabel)
            output.setSampleBufferDelegate(self, queue: outputQueue)
            guard self.captureSession.canAddOutput(output) else {
                print("Failed to add capture session output.")
                return
            }
            self.captureSession.addOutput(output)
            self.captureSession.commitConfiguration()
        }
    }
    
    private func setUpCaptureSessionInput() {
        sessionQueue.async {
            let cameraPosition: AVCaptureDevice.Position = .back
            guard let device = self.captureDevice(forPosition: cameraPosition) else {
                print("Failed to get capture device for camera position: \(cameraPosition)")
                return
            }
            do {
                self.captureSession.beginConfiguration()
                let currentInputs = self.captureSession.inputs
                for input in currentInputs {
                    self.captureSession.removeInput(input)
                }
                
                let input = try AVCaptureDeviceInput(device: device)
                guard self.captureSession.canAddInput(input) else {
                    print("Failed to add capture session input.")
                    return
                }
                self.captureSession.addInput(input)
                self.captureSession.commitConfiguration()
            } catch {
                print("Failed to create capture device input: \(error.localizedDescription)")
            }
        }
    }
    
    private func setUpPreviewOverlayView() {
        cameraView.addSubview(previewOverlayView)
        NSLayoutConstraint.activate([
            previewOverlayView.topAnchor.constraint(greaterThanOrEqualTo: cameraView.topAnchor),
            previewOverlayView.centerYAnchor.constraint(equalTo: cameraView.centerYAnchor),
            previewOverlayView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
            previewOverlayView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
            previewOverlayView.bottomAnchor.constraint(lessThanOrEqualTo: cameraView.bottomAnchor),
            ])
    }
    
    private func setUpAnnotationOverlayView() {
        cameraView.addSubview(annotationOverlayView)
        NSLayoutConstraint.activate([
            annotationOverlayView.topAnchor.constraint(equalTo: cameraView.topAnchor),
            annotationOverlayView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
            annotationOverlayView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
            annotationOverlayView.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor),
            ])
    }
    
    private func startSession() {
        sessionQueue.async {
            self.captureSession.startRunning()
        }
    }
    
    private func stopSession() {
        sessionQueue.async {
            self.captureSession.stopRunning()
        }
    }
    
    private func captureDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if #available(iOS 10.0, *) {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .unspecified
            )
            return discoverySession.devices.first { $0.position == position }
        }
        return nil
    }
    
    private func presentDetectorsAlertController() {
        let alertController = UIAlertController(
            title: Constant.alertControllerTitle,
            message: Constant.alertControllerMessage,
            preferredStyle: .alert
        )
        detectors.forEach { detectorType in
            let action = UIAlertAction(title: detectorType.rawValue, style: .default) {
                [unowned self] (action) in
                guard let value = action.title else { return }
                guard let detector = Detector(rawValue: value) else { return }
                self.currentDetector = detector
                self.removeDetectionAnnotations()
            }
            if detectorType.rawValue == currentDetector.rawValue { action.isEnabled = false }
            alertController.addAction(action)
        }
        alertController.addAction(UIAlertAction(title: Constant.cancelActionTitleText, style: .cancel))
        present(alertController, animated: true)
    }
    
    private func removeDetectionAnnotations() {
        for annotationView in annotationOverlayView.subviews {
            annotationView.removeFromSuperview()
        }
    }
    
    private func updatePreviewOverlayView() {
        guard let lastFrame = lastFrame,
            let imageBuffer = CMSampleBufferGetImageBuffer(lastFrame)
            else {
                return
        }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }
        let rotatedImage =
            UIImage(cgImage: cgImage, scale: Constant.originalScale, orientation: .right)
        if isUsingFrontCamera {
            guard let rotatedCGImage = rotatedImage.cgImage else {
                return
            }
            let mirroredImage = UIImage(
                cgImage: rotatedCGImage, scale: Constant.originalScale, orientation: .leftMirrored)
            previewOverlayView.image = mirroredImage
        } else {
            previewOverlayView.image = rotatedImage
        }
    }
    
    private func convertedPoints(
        from points: [NSValue]?,
        width: CGFloat,
        height: CGFloat
        ) -> [NSValue]? {
        return points?.map {
            let cgPointValue = $0.cgPointValue
            let normalizedPoint = CGPoint(x: cgPointValue.x / width, y: cgPointValue.y / height)
            let cgPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
            let value = NSValue(cgPoint: cgPoint)
            return value
        }
    }
    
    private func normalizedPoint(
        fromVisionPoint point: VisionPoint,
        width: CGFloat,
        height: CGFloat
        ) -> CGPoint {
        let cgPoint = CGPoint(x: CGFloat(point.x.floatValue), y: CGFloat(point.y.floatValue))
        var normalizedPoint = CGPoint(x: cgPoint.x / width, y: cgPoint.y / height)
        normalizedPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
        return normalizedPoint
    }
   
}

// MARK: AVCaptureVideoDataOutputSampleBufferDelegate
extension ReadMenuViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
        ) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer from sample buffer.")
            return
        }
        lastFrame = sampleBuffer
        let visionImage = VisionImage(buffer: sampleBuffer)
        let metadata = VisionImageMetadata()
        let orientation = UIUtilities.imageOrientation(
            fromDevicePosition: isUsingFrontCamera ? .front : .back
        )
        let visionOrientation = UIUtilities.visionImageOrientation(from: orientation)
        metadata.orientation = visionOrientation
        visionImage.metadata = metadata
        let imageWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        switch currentDetector {
        case .onDeviceText:
            recognizeTextOnDevice(
                in: visionImage,
                width: imageWidth,
                height: imageHeight
            )
        }
    }
}

// MARK: - Constants

public enum Detector: String {
    case onDeviceText = "On-Device Text Recognition"
}

private enum Constant {
    static let alertControllerTitle = "Vision Detectors"
    static let alertControllerMessage = "Select a detector"
    static let cancelActionTitleText = "Cancel"
    static let videoDataOutputQueueLabel = "com.brewrec.firebaseml.visiondetector.VideoDataOutputQueue"
    static let sessionQueueLabel = "com.brewrec.firebaseml.visiondetector.SessionQueue"
    static let noResultsMessage = "No Results"
    static let smallDotRadius: CGFloat = 4.0
    static let originalScale: CGFloat = 1.0
}
