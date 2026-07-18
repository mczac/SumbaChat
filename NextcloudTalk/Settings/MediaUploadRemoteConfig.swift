//
// SPDX-FileCopyrightText: 2026 Ivan Cursoroff and Peter Zakharov
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Future remote client settings for media upload / compression.
///
/// Compression preferences are local today (`NCUserDefaults` + Debug profiles).
/// When the server starts advertising SumbaChat client knobs, apply them here.
///
/// This is invoked from `NCDatabaseManager.setTalkCapabilities`, which runs on
/// initial capability load and again whenever `x-nextcloud-talk-hash` changes
/// (see `NCTalkConfigurationHashChanged` → capabilities refresh).
enum MediaUploadRemoteConfig {

    /// Apply any remote client settings present in the Talk capabilities payload.
    /// Currently a no-op — uploads keep using local settings only.
    static func applyIfPresent(from capabilitiesDict: [AnyHashable: Any]) {
        // Example future shape (not read yet):
        // config.attachments["sumbachat-client"] or a dedicated top-level key.
        _ = capabilitiesDict
    }
}
