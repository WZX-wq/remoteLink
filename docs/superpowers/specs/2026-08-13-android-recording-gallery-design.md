# Android Recording Gallery Design

## Goal

Publish completed Android remote-session recordings to the phone's system
gallery so users can find them quickly. Recordings appear in the dedicated
album backed by `DCIM/鲲穹远程桌面`.

After a recording is published successfully, delete its private app-storage
source file so only the gallery copy remains. If publication fails, keep the
source file and tell the user where it remains. A failed or partial copy must
never cause recording loss.

## Platform Boundary

This behavior is Android-only. iOS and desktop keep their current recording
directory, stop behavior, notifications, and file lifecycle. Shared recording
and codec code continues to finalize the source media in app-controlled
storage; it does not write directly to Android public storage.

Android gallery integration belongs in a dedicated Kotlin component reached
through the existing `mChannel`. Flutter invokes that method only when
`isAndroid` is true. No Android storage rules or paths are added to the Rust
recorder, iOS code, or desktop code.

## Recording Discovery

One recording session can produce more than one file when the stream codec,
resolution, or timestamp sequence changes. The Android Flutter recording model
therefore snapshots eligible recording files before recording starts and
compares that snapshot with the finalized directory after recording stops.

An eligible file must:

- be a regular `.mp4` or `.webm` file in the configured recording directory;
- be new or have a changed file identity after recording started;
- have non-zero length after the Rust stop call returns; and
- still exist when publication begins.

All eligible files from the session are published in deterministic filename
order. Existing recordings in the directory are never republished or deleted.
The snapshot remains Android-only and is cleared when the session model resets.

## Android MediaStore Publisher

A focused Kotlin publisher receives one absolute source path at a time. It
validates that the source is a readable regular file and accepts only `.mp4`
and `.webm`. It chooses `video/mp4` or `video/webm` from the extension and
creates a row in `MediaStore.Video.Media.EXTERNAL_CONTENT_URI`.

On Android 10 and newer, the row uses:

- `DISPLAY_NAME` equal to the source filename;
- the matching video MIME type;
- `RELATIVE_PATH` equal to `DCIM/鲲穹远程桌面`; and
- `IS_PENDING = 1` until the copy has completed and flushed.

The publisher copies bytes on a background dispatcher, closes both streams,
then commits the row with `IS_PENDING = 0`. Only after the commit succeeds may
it delete the source file. It returns structured data containing success,
display name, gallery URI when available, retained source path on failure, and
a stable error code.

On Android 9 and older, the publisher writes into the public DCIM album using
the legacy media-storage path, requests write permission through the existing
Android permission flow when required, and registers the completed file with
the media scanner. The source is deleted only after both the copy and media
registration succeed.

## Name Collisions

The publisher must not overwrite an existing gallery recording. If the target
display name already exists, it appends a numeric suffix before the extension,
for example `recording (1).mp4`. This applies to both MediaStore and legacy
Android paths.

## Stop Flow And User Feedback

Stopping recording follows this sequence:

1. Await the existing Rust stop call so the muxer writes its tail and closes.
2. Discover all eligible files created during the current session.
3. Publish each file through the Android channel, sequentially.
4. Show a concise success message naming the system album when all files were
   published.
5. If any file fails, show a partial-failure or failure message and include the
   retained app-storage path. Successfully published files remain in the
   gallery and their source copies remain deleted.

The stop action must remain responsive while publication runs. Repeated taps
cannot start a second publication pass for the same files. A recording that
produced no valid media reports that no usable recording file was generated
rather than claiming it was saved.

## Failure Safety

If MediaStore insertion, stream creation, copying, flushing, commit, permission,
or source deletion fails, the publisher reports the exact stage. Before commit,
it removes the incomplete MediaStore row or partial legacy destination when
possible. It never deletes the source after a failed publication.

If gallery publication succeeds but source deletion fails, the result reports
success-with-cleanup-warning. The gallery file remains valid, and the user is
told that the source copy was retained. Errors are logged without exposing
remote IDs or unrelated filesystem details in normal success messages.

## Permissions

Android 10 and newer use scoped storage through MediaStore and do not require
`MANAGE_EXTERNAL_STORAGE`. Android 9 and older use only the storage permission
needed by the legacy public-DCIM path. Broad storage-permission cleanup outside
this recording flow is not part of this change because other existing features
may still depend on it and require a separate audit.

## Verification

Focused Flutter contract tests verify Android-only invocation, multi-file
discovery, exclusion of pre-existing files, no-file feedback, and success,
partial-failure, and cleanup-warning messages. Kotlin tests verify MIME
selection, supported extensions, collision-safe names, MediaStore metadata,
source deletion only after commit, and source retention on every failure path.

Run targeted Flutter tests, Android unit tests, touched-file analysis, and
`git diff --check`. Then build the signed Android release APK with a build
number above the currently installed or latest artifact version, overwrite the
existing release APK, and verify package name, version code, ABI, signature,
and checksum. iOS and desktop are not built because their code paths remain
unchanged.
