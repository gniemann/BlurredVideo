//
// BlurredVideoView.swift
// fox-flagship-tvOS
//
// Created by Greg Niemann on 10/4/17.
// Copyright (c) 2017 WillowTree, Inc. All rights reserved.
//

import UIKit
import AVKit

class BlurredVideoView: UIView {
    var player: AVPlayer!
    var output: AVPlayerItemVideoOutput!
    var item: AVPlayerItem!
    var displayLink: CADisplayLink!

    var context: CIContext = CIContext(options: [kCIContextWorkingColorSpace : NSNull()])

    var blurRadius: Double = 6.0

    var onPlay: (()->Void)?

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
        let blurImg = baseImg.clampedToExtent().applyingGaussianBlur(sigma: blurRadius).cropped(to: baseImg.extent)

        guard let cgImg = context.createCGImage(blurImg, from: blurImg.extent) else { return }

        layer.contents = cgImg
    }

    func stop() {
        player.rate = 0
        displayLink.invalidate()
    }
}
