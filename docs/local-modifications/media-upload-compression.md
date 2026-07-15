# Local modification: media upload compression

Branch: `feature/media-upload-compression`

## What changed

Photos and videos are compressed before upload staging in `ShareItemController`.

| File | Change |
|------|--------|
| `NextcloudTalk/Settings/MediaUploadPreprocessor.swift` | **New** — image resize/JPEG + video export helper |
| `ShareExtension/ShareItemController.m` | Compress images/videos when items are staged |
| `NextcloudTalk.xcodeproj/project.pbxproj` | Include preprocessor in ShareExtension target |

## Behavior

- **Photos** (except GIF): max dimension 2048px, JPEG quality 0.7
- **Videos**: `AVAssetExportPresetMediumQuality` → `.mp4`
- **GIF / pasted PNG**: unchanged
- **Video compression failure**: falls back to original file

## Revert this feature only

```bash
cd /Users/peterzakharov/Developer/NextCloutTalk
git checkout main -- ShareExtension/ShareItemController.m
git rm NextcloudTalk/Settings/MediaUploadPreprocessor.swift
git checkout main -- NextcloudTalk.xcodeproj/project.pbxproj
```

Or discard the whole branch:

```bash
git checkout main
git branch -D feature/media-upload-compression
```

## Revert everything on this branch

```bash
git checkout main
git branch -D feature/media-upload-compression
```

(ADC signing changes from the initial setup are still uncommitted local edits on this branch.)
