//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import UIKit
import UniformTypeIdentifiers

@objcMembers public final class MediaUploadCompressionSettings: NSObject {

    public static let defaultImageMaxDimension = 1280
    public static let defaultImageJPEGQuality = 45
    public static let defaultVideoPreset = "low"

    public let enabled: Bool
    public let imageEnabled: Bool
    public let imageMaxDimension: CGFloat
    public let imageJPEGQuality: CGFloat
    public let videoEnabled: Bool
    public let videoPreset: String

    public override convenience init() {
        self.init(enabled: true,
                  imageEnabled: true,
                  imageMaxDimension: Self.defaultImageMaxDimension,
                  imageJPEGQuality: Self.defaultImageJPEGQuality,
                  videoEnabled: true,
                  videoPreset: Self.defaultVideoPreset)
    }

    @objc(initWithTalkCapabilities:)
    public convenience init(talkCapabilities: TalkCapabilities) {
        // Newly added Realm properties are empty until capabilities are
        // refreshed after migration. Keep the app defaults during that window.
        guard !talkCapabilities.videoCompressionPreset.isEmpty else {
            self.init()
            return
        }

        self.init(enabled: talkCapabilities.uploadCompressionEnabled,
                  imageEnabled: talkCapabilities.imageCompressionEnabled,
                  imageMaxDimension: talkCapabilities.imageMaxDimension,
                  imageJPEGQuality: talkCapabilities.imageJPEGQuality,
                  videoEnabled: talkCapabilities.videoCompressionEnabled,
                  videoPreset: talkCapabilities.videoCompressionPreset)
    }

    public init(enabled: Bool,
                imageEnabled: Bool,
                imageMaxDimension: Int,
                imageJPEGQuality: Int,
                videoEnabled: Bool,
                videoPreset: String) {
        self.enabled = enabled
        self.imageEnabled = imageEnabled
        self.imageMaxDimension = CGFloat(Self.validImageMaxDimension(imageMaxDimension))
        self.imageJPEGQuality = CGFloat(Self.validImageJPEGQuality(imageJPEGQuality)) / 100
        self.videoEnabled = videoEnabled
        self.videoPreset = Self.validVideoPreset(videoPreset)
    }

    public var shouldCompressImages: Bool {
        enabled && imageEnabled
    }

    public var shouldCompressVideos: Bool {
        enabled && videoEnabled
    }

    fileprivate var avVideoPreset: String {
        switch videoPreset {
        case "medium":
            return AVAssetExportPresetMediumQuality
        case "high":
            return AVAssetExportPresetHighestQuality
        case "480p":
            return AVAssetExportPreset640x480
        case "720p":
            return AVAssetExportPreset1280x720
        case "1080p":
            return AVAssetExportPreset1920x1080
        case "2160p":
            return AVAssetExportPreset3840x2160
        default:
            return AVAssetExportPresetLowQuality
        }
    }

    private static func validImageMaxDimension(_ value: Int) -> Int {
        guard (320...8192).contains(value) else {
            return defaultImageMaxDimension
        }
        return value
    }

    private static func validImageJPEGQuality(_ value: Int) -> Int {
        guard (10...100).contains(value) else {
            return defaultImageJPEGQuality
        }
        return value
    }

    private static func validVideoPreset(_ value: String) -> String {
        let supportedPresets = ["low", "medium", "high", "480p", "720p", "1080p", "2160p"]
        return supportedPresets.contains(value) ? value : defaultVideoPreset
    }
}

/// Compresses photos and videos before they are staged for upload.
@objcMembers public class MediaUploadPreprocessor: NSObject {

    @objc(compressImageAtURL:toDestinationURL:settings:)
    public static func compressImage(at sourceURL: URL,
                                     toDestinationURL destinationURL: URL,
                                     settings: MediaUploadCompressionSettings) -> Bool {
        let fileExtension = sourceURL.pathExtension.lowercased()

        if fileExtension == "gif" || !settings.shouldCompressImages {
            return false
        }

        guard let image = UIImage(contentsOfFile: sourceURL.path) else {
            return false
        }

        guard let jpegData = compressedJPEGData(from: image, settings: settings) else {
            return false
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try jpegData.write(to: destinationURL, options: .atomic)
            return true
        } catch {
            NSLog("MediaUploadPreprocessor: failed to write compressed image: \(error.localizedDescription)")
            return false
        }
    }

    @objc(compressedJPEGDataFromImage:settings:)
    public static func compressedJPEGData(from image: UIImage, settings: MediaUploadCompressionSettings) -> Data? {
        let resizedImage = settings.shouldCompressImages
            ? resizeImageIfNeeded(image, maxDimension: settings.imageMaxDimension)
            : image
        let quality = settings.shouldCompressImages ? settings.imageJPEGQuality : 1
        return resizedImage.jpegData(compressionQuality: quality)
    }

    @objc(isVideoFileExtension:)
    public static func isVideo(fileExtension: String) -> Bool {
        guard let fileType = UTType(filenameExtension: fileExtension) else {
            return false
        }

        return fileType.conforms(to: .movie)
    }

    @objc(compressVideoAtURL:toDestinationURL:settings:completion:)
    public static func compressVideo(at sourceURL: URL,
                                     toDestinationURL destinationURL: URL,
                                     settings: MediaUploadCompressionSettings,
                                     completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: sourceURL)

        guard settings.shouldCompressVideos else {
            completion(false)
            return
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: settings.avVideoPreset) else {
            NSLog("MediaUploadPreprocessor: unable to create export session")
            completion(false)
            return
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                let sourceSize = fileSize(at: sourceURL)
                let compressedSize = fileSize(at: destinationURL)

                guard compressedSize > 0, sourceSize == 0 || compressedSize < sourceSize else {
                    try? FileManager.default.removeItem(at: destinationURL)
                    NSLog("MediaUploadPreprocessor: compressed video was not smaller; using original")
                    completion(false)
                    return
                }

                NSLog("MediaUploadPreprocessor: compressed video from \(sourceSize) to \(compressedSize) bytes")
                completion(true)
            case .failed, .cancelled:
                NSLog("MediaUploadPreprocessor: video export failed: \(exportSession.error?.localizedDescription ?? "unknown error")")
                completion(false)
            default:
                completion(false)
            }
        }
    }

    private static func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largestSide = max(size.width, size.height)

        guard largestSide > maxDimension else {
            return image
        }

        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        return NCUtils.renderAspectImage(image: image, ofSize: targetSize, scale: 1.0, centerImage: false) ?? image
    }

    private static func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
