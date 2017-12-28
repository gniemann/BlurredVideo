//
// BlurredVideoMPSView.swift
// fox-flagship-tvOS
//
// Created by Greg Niemann on 12/27/17.
// Copyright (c) 2017 Greg Niemann. All rights reserved.
//

import UIKit
import MetalKit
import MetalPerformanceShaders
import AVKit

class BlurredVideoMPSView: MTKView {
    var player: AVPlayer!
    var output: AVPlayerItemVideoOutput!
    var item: AVPlayerItem!
    var displayLink: CADisplayLink!

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    lazy var commandQueue: MTLCommandQueue? = {
        return self.device!.makeCommandQueue()
    }()

    lazy var content: CIContext = {
        return CIContext(mtlDevice: self.device!, options: [kCIContextWorkingColorSpace : NSNull()])
    }()

    var gaussianBlur: MPSImageGaussianBlur?

    var blurRadius: Double = 6.0 {
        didSet {
            createGaussianBlur()
        }
    }

    var onPlay: (()->Void)?

    var image: CIImage? {
        didSet {
            draw()
        }
    }

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        setup()
    }

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        device = MTLCreateSystemDefaultDevice()
        setup()
    }

    func setup() {
        framebufferOnly = false
        isPaused = false
        enableSetNeedsDisplay = false
        createGaussianBlur()
    }

    func createGaussianBlur() {
        if let device = device, MPSSupportsMTLDevice(device) {
            gaussianBlur = MPSImageGaussianBlur(device: device, sigma: Float(blurRadius))
        }
    }

    deinit {
        if item != nil {
            item.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
        }
    }

    func play(stream: URL, withBlur blur: Double? = nil, completion:  (()->Void)? = nil) {
        layer.isOpaque = true
        onPlay = completion
        if let blur = blur {
            blurRadius = blur
        }

        item = AVPlayerItem(url: stream)
        output = AVPlayerItemVideoOutput(outputSettings: nil)
        item.add(output)

        item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.old, .new], context: nil)

        player = AVPlayer(playerItem: item)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let item = object as? AVPlayerItem, keyPath == #keyPath(AVPlayerItem.status) else {
            return
        }

        if item.status == .readyToPlay {
            displayLink = CADisplayLink(target: self, selector: #selector(displayLinkUpdated(link:)))
            displayLink.preferredFramesPerSecond = 20
            displayLink.add(to: .main, forMode: .commonModes)

            player.play()
            onPlay?()
        }
    }

    @objc func displayLinkUpdated(link: CADisplayLink) {
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let pixbuf = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let baseImg = CIImage(cvImageBuffer: pixbuf)

        if gaussianBlur != nil {
            image = baseImg
        } else {
            image = baseImg.clampedToExtent()
                    .applyingGaussianBlur(sigma: blurRadius)
                    .cropped(to: baseImg.extent)
        }
    }

    override func draw(_ rect: CGRect) {
        guard let image = image,
              let currentDrawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer()
                else {
            return
        }
        let currentTexture = currentDrawable.texture
        let drawingBounds = CGRect(origin: .zero, size: drawableSize)

        let scaleX = drawableSize.width / image.extent.width
        let scaleY = drawableSize.height / image.extent.height
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        content.render(scaledImage, to: currentTexture, commandBuffer: commandBuffer, bounds: drawingBounds, colorSpace: colorSpace)
        commandBuffer.present(currentDrawable)

        if let gaussianBlur = gaussianBlur {
            // apply the gaussian blur with MPS
            let inplaceTexture = UnsafeMutablePointer<MTLTexture>.allocate(capacity: 1)
            inplaceTexture.initialize(to: currentTexture)
            gaussianBlur.encode(commandBuffer: commandBuffer, inPlaceTexture: inplaceTexture)
        }

        commandBuffer.commit()
    }

    func stop() {
        player.rate = 0
        displayLink.invalidate()
    }
}
