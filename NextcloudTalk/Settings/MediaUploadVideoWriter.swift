//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import CoreMedia
import UIKit

/// AVAssetWriter-based video compress with bitrate, max edge, and fps targets.
enum MediaUploadVideoWriter {

    static func compress(at sourceURL: URL,
                         toDestinationURL destinationURL: URL,
                         profile: MediaUploadProfileConfig,
                         cancelToken: MediaUploadPreparationToken?,
                         progress: ((Float) -> Void)?,
                         completion: @escaping (Bool) -> Void) {
        if cancelToken?.isCancelled == true {
            completion(false)
            return
        }

        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            NCLog.log("MediaUploadVideoWriter: no video track")
            completion(false)
            return
        }

        let durationSeconds = CMTimeGetSeconds(asset.duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            NCLog.log("MediaUploadVideoWriter: invalid duration")
            completion(false)
            return
        }

        // Scale storage (natural) size so the on-screen longest edge ≤ maxEdge; keep preferredTransform.
        let natural = videoTrack.naturalSize
        let displaySize = orientedSize(for: videoTrack)
        let maxEdge = CGFloat(max(320, profile.videoMaxEdge))
        let displayLong = max(displaySize.width, displaySize.height)
        let scale = displayLong > maxEdge ? maxEdge / displayLong : 1
        let width = evenInt(natural.width * scale)
        let height = evenInt(natural.height * scale)
        if width < 2 || height < 2 {
            NCLog.log("MediaUploadVideoWriter: invalid output size \(width)x\(height)")
            completion(false)
            return
        }

        let rateMBps = MediaUploadDebugSettings.effectiveRateMBps(profile: profile, durationSeconds: durationSeconds)
        let totalBitsPerSecond = rateMBps * 1_048_576.0 * 8.0
        let audioBitsPerSecond = 128_000.0
        let videoBitsPerSecond = max(100_000, Int(totalBitsPerSecond - audioBitsPerSecond))

        do {
            try? FileManager.default.removeItem(at: destinationURL)
            let reader = try AVAssetReader(asset: asset)
            let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)

            let readerVideoSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerVideoSettings)
            videoReaderOutput.alwaysCopiesSampleData = false
            guard reader.canAdd(videoReaderOutput) else {
                completion(false)
                return
            }
            reader.add(videoReaderOutput)

            let compression: [String: Any] = [
                AVVideoAverageBitRateKey: videoBitsPerSecond,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
                AVVideoExpectedSourceFrameRateKey: max(1, Int(profile.videoFPS.rounded()))
            ]
            let writerVideoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compression
            ]
            let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerVideoSettings)
            videoWriterInput.expectsMediaDataInRealTime = false
            videoWriterInput.transform = videoTrack.preferredTransform
            guard writer.canAdd(videoWriterInput) else {
                completion(false)
                return
            }
            writer.add(videoWriterInput)

            var audioReaderOutput: AVAssetReaderTrackOutput?
            var audioWriterInput: AVAssetWriterInput?
            if let audioTrack = asset.tracks(withMediaType: .audio).first {
                let audioReaderSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM
                ]
                let aOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioReaderSettings)
                aOut.alwaysCopiesSampleData = false
                if reader.canAdd(aOut) {
                    reader.add(aOut)
                    audioReaderOutput = aOut

                    var layout = AudioChannelLayout()
                    layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
                    let layoutData = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
                    let audioWriterSettings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVNumberOfChannelsKey: 2,
                        AVSampleRateKey: 44_100,
                        AVEncoderBitRateKey: Int(audioBitsPerSecond),
                        AVChannelLayoutKey: layoutData
                    ]
                    let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioWriterSettings)
                    aIn.expectsMediaDataInRealTime = false
                    if writer.canAdd(aIn) {
                        writer.add(aIn)
                        audioWriterInput = aIn
                    }
                }
            }

            let state = WriterState()
            cancelToken?.attachWriterCancel { [weak state] in
                state?.cancel(reader: reader, writer: writer)
            }

            guard reader.startReading(), writer.startWriting() else {
                NCLog.log("MediaUploadVideoWriter: failed to start reader/writer")
                completion(false)
                return
            }
            writer.startSession(atSourceTime: .zero)

            let videoQueue = DispatchQueue(label: "com.spl.SumbaChat.media-upload-video")
            let audioQueue = DispatchQueue(label: "com.spl.SumbaChat.media-upload-audio")
            let group = DispatchGroup()
            let totalDuration = asset.duration

            group.enter()
            videoWriterInput.requestMediaDataWhenReady(on: videoQueue) {
                while videoWriterInput.isReadyForMoreMediaData {
                    if cancelToken?.isCancelled == true || state.isCancelled {
                        videoWriterInput.markAsFinished()
                        group.leave()
                        return
                    }
                    if let sample = videoReaderOutput.copyNextSampleBuffer() {
                        if !videoWriterInput.append(sample) {
                            videoWriterInput.markAsFinished()
                            group.leave()
                            return
                        }
                        let t = CMSampleBufferGetPresentationTimeStamp(sample)
                        let fraction = Float(CMTimeGetSeconds(t) / max(0.001, CMTimeGetSeconds(totalDuration)))
                        DispatchQueue.main.async {
                            progress?(min(0.99, max(0, fraction)))
                        }
                    } else {
                        videoWriterInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }

            if let audioWriterInput, let audioReaderOutput {
                group.enter()
                audioWriterInput.requestMediaDataWhenReady(on: audioQueue) {
                    while audioWriterInput.isReadyForMoreMediaData {
                        if cancelToken?.isCancelled == true || state.isCancelled {
                            audioWriterInput.markAsFinished()
                            group.leave()
                            return
                        }
                        if let sample = audioReaderOutput.copyNextSampleBuffer() {
                            if !audioWriterInput.append(sample) {
                                audioWriterInput.markAsFinished()
                                group.leave()
                                return
                            }
                        } else {
                            audioWriterInput.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }

            group.notify(queue: .global(qos: .userInitiated)) {
                if cancelToken?.isCancelled == true || state.isCancelled {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: destinationURL)
                    DispatchQueue.main.async {
                        progress?(0)
                        completion(false)
                    }
                    return
                }

                writer.finishWriting {
                    DispatchQueue.main.async {
                        if cancelToken?.isCancelled == true {
                            try? FileManager.default.removeItem(at: destinationURL)
                            completion(false)
                            return
                        }
                        guard writer.status == .completed else {
                            NCLog.log("MediaUploadVideoWriter: finish failed \(writer.error?.localizedDescription ?? "unknown")")
                            try? FileManager.default.removeItem(at: destinationURL)
                            completion(false)
                            return
                        }
                        let sourceSize = MediaUploadPreprocessor.fileSizePublic(at: sourceURL)
                        let compressedSize = MediaUploadPreprocessor.fileSizePublic(at: destinationURL)
                        guard compressedSize > 0, sourceSize == 0 || compressedSize < sourceSize else {
                            try? FileManager.default.removeItem(at: destinationURL)
                            NCLog.log("MediaUploadVideoWriter: output not smaller; using original")
                            completion(false)
                            return
                        }
                        let duration = CMTimeGetSeconds(asset.duration)
                        let srcMbps = duration > 0
                            ? MediaUploadDebugSettings.approximateSourceTotalMbps(fileBytes: sourceSize, durationSeconds: duration) : 0
                        let outMbps = duration > 0
                            ? MediaUploadDebugSettings.approximateSourceTotalMbps(fileBytes: compressedSize, durationSeconds: duration) : 0
                        NCLog.log(String(format:
                            "MediaUploadVideoWriter: ACTUAL %@ %lld (%.2f MB, %.3fMbps) → %lld (%.2f MB, %.3fMbps) %dx%d targetVideoBitrate=%d bps",
                            sourceURL.lastPathComponent,
                            sourceSize, Double(sourceSize) / 1_048_576.0, srcMbps,
                            compressedSize, Double(compressedSize) / 1_048_576.0, outMbps,
                            width, height, videoBitsPerSecond))
                        completion(true)
                    }
                }
            }
        } catch {
            NCLog.log("MediaUploadVideoWriter: \(error.localizedDescription)")
            completion(false)
        }
    }

    private static func orientedSize(for track: AVAssetTrack) -> CGSize {
        let natural = track.naturalSize
        let transformed = natural.applying(track.preferredTransform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    private static func evenInt(_ value: CGFloat) -> Int {
        var n = Int(value.rounded())
        if n % 2 != 0 { n += 1 }
        return max(2, n)
    }

    private final class WriterState {
        private let lock = NSLock()
        private(set) var isCancelled = false

        func cancel(reader: AVAssetReader, writer: AVAssetWriter) {
            lock.lock()
            isCancelled = true
            lock.unlock()
            reader.cancelReading()
            writer.cancelWriting()
        }
    }
}
