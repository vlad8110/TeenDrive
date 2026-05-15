/*
 File: MakeVideo.swift
 Created: 2026-05-12
 Creator: Vladimyr Merci

 Purpose:
 Builds an MP4 video from the rendered TeenDrive ad PNG frame sequence.

 Developer Notes:
 The script uses AVFoundation so the repo can render video on macOS without ffmpeg.
*/
import AppKit
import AVFoundation
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let framesDirectory = root.appendingPathComponent("marketing/video-ad/frames")
let outputURL = root.appendingPathComponent("marketing/video-ad/teendrive_video_ad.mp4")
let fps: Int32 = 8
let width = 1080
let height = 1920

try? FileManager.default.removeItem(at: outputURL)

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 7_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
    ]
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false

let attributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height
]
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)

guard writer.canAdd(input) else {
    fatalError("Cannot add video input")
}
writer.add(input)

let frameURLs = try FileManager.default.contentsOfDirectory(at: framesDirectory, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !frameURLs.isEmpty else {
    fatalError("No rendered frames found")
}

func pixelBuffer(from imageURL: URL) -> CVPixelBuffer? {
    guard let image = NSImage(contentsOf: imageURL),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }

    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32ARGB,
        attributes as CFDictionary,
        &buffer
    )
    guard status == kCVReturnSuccess, let buffer else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    ) else {
        return nil
    }

    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
}

writer.startWriting()
writer.startSession(atSourceTime: .zero)

let mediaInputQueue = DispatchQueue(label: "teendrive.video.writer")
var frameIndex = 0
let frameDuration = CMTime(value: 1, timescale: fps)

input.requestMediaDataWhenReady(on: mediaInputQueue) {
    while input.isReadyForMoreMediaData && frameIndex < frameURLs.count {
        autoreleasepool {
            if let buffer = pixelBuffer(from: frameURLs[frameIndex]) {
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                adaptor.append(buffer, withPresentationTime: presentationTime)
            }
            frameIndex += 1
        }
    }

    if frameIndex >= frameURLs.count {
        input.markAsFinished()
        writer.finishWriting {
            if writer.status == .completed {
                print(outputURL.path)
                exit(0)
            } else {
                print(writer.error?.localizedDescription ?? "Video export failed")
                exit(1)
            }
        }
    }
}

dispatchMain()
