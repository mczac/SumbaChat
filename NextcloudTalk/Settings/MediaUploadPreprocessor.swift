//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import UIKit
import UniformTypeIdentifiers

/// Compresses photos and videos before they are staged for upload.
@objcMembers public class MediaUploadPreprocessor: NSObject {

    public static let maxImageDimension: CGFloat = 2048
    public static let jpegQuality: CGFloat = 0.7

    @objc(compressImageAtURL:toDestinationURL:)
    public static func compressImage(at sourceURL: URL, toDestinationURL destinationURL: URL) -> Bool {
        let fileExtension = sourceURL.pathExtension.lowercased()

        if fileExtension == "gif" {
            return false
        }

        guard let image = UIImage(contentsOfFile: sourceURL.path) else {
            return false
        }

        guard let jpegData = compressedJPEGData(from: image) else {
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

    @objc(compressedJPEGDataFromImage:)
    public static func compressedJPEGData(from image: UIImage) -> Data? {
        let resizedImage = resizeImageIfNeeded(image, maxDimension: maxImageDimension)
        return resizedImage.jpegData(compressionQuality: jpegQuality)
    }

    @objc(isVideoFileExtension:)
    public static func isVideo(fileExtension: String) -> Bool {
        guard let fileType = UTType(filenameExtension: fileExtension) else {
            return false
        }

        return fileType.conforms(to: .movie)
    }

    @objc(compressVideoAtURL:toDestinationURL:completion:)
    public static func compressVideo(at sourceURL: URL,
                                     toDestinationURL destinationURL: URL,
                                     completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: sourceURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
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
}
