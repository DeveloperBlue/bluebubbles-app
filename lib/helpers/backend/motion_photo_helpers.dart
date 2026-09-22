import 'dart:convert';

import 'package:bluebubbles/services/backend/filesystem/filesystem_service.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:motion_photos/motion_photos.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

/// Android Motion Photo → Live Photo send helpers.
///
/// Split across prep and send so the bubble can appear before remux:
///
/// 1. [truncateStill] — called from `OutgoingMessageHandler.prepAttachment`
///    (main). Writes a clean still. When Private API attachment send is on,
///    the caller sets `metadata['motion_source_path']` and optimistic
///    `hasLivePhoto`.
/// 2. [remuxCompanion] — called from `OutgoingMessageHandler.sendAttachment`
///    on the **main** isolate (FFmpegKit uses platform channels and cannot run
///    in GlobalIsolate). Extracts the embedded MP4 and remuxes → same-stem
///    `.mov` (`ffmpeg -c copy`). The isolate only uploads the resulting path.
///
/// [cachedMotionVideoPath] is also shared with `LivePhotoMixin` playback.
class MotionPhotoHelpers {
  static const _tag = 'MotionPhoto';

  static final _useSystemFfmpeg = !kIsWeb && Platform.isLinux && Platform.version.contains('linux_arm64');

  /// Temp-cache path for the embedded MP4 extracted from [stillPath].
  ///
  /// Shared by send remux and `LivePhotoMixin` local playback.
  static Future<String> cachedMotionVideoPath(String stillPath) async {
    final destDir = Directory(p.join(FilesystemSvc.sysTempPath, 'motion_photos'));
    await destDir.create(recursive: true);
    final digest = sha256.convert(utf8.encode(stillPath)).toString();
    return p.join(destDir.path, '$digest.mp4');
  }

  /// Same-stem `.mov` path beside a staged still (matches server / helper pairing).
  static String companionPathForStill(String stillPath) {
    return p.join(p.dirname(stillPath), '${p.basenameWithoutExtension(stillPath)}.mov');
  }

  /// If [sourcePath] is a Motion Photo with a real embedded video, write a clean
  /// still (no embedded video) to [stillDestPath] and return the still bytes.
  ///
  /// Called from prep on the main isolate (before the bubble appears).
  /// Returns null when the file is not a usable Motion Photo (caller should copy as-is).
  static Future<Uint8List?> truncateStill({
    required String sourcePath,
    required String stillDestPath,
  }) async {
    if (kIsWeb) return null;

    final index = await _validVideoIndex(sourcePath);
    if (index == null) return null;

    final raf = await File(sourcePath).open(mode: FileMode.read);
    late final Uint8List stillBytes;
    try {
      stillBytes = await raf.read(index.start);
    } finally {
      await raf.close();
    }

    await File(stillDestPath).create(recursive: true);
    await File(stillDestPath).writeAsBytes(stillBytes, flush: true);
    Logger.info('Motion Photo still truncated → $stillDestPath (${stillBytes.length} bytes)', tag: _tag);
    return stillBytes;
  }

  /// Extract embedded MP4 from [motionSourcePath] (cache hit ok) and remux to a
  /// same-stem `.mov` beside [stillDestPath].
  ///
  /// Must run on the **root/main** isolate — FFmpegKit initializes EventChannels
  /// that background isolates reject (`setMessageHandler` unsupported).
  /// Returns the companion path on success, or null on failure.
  static Future<String?> remuxCompanion({
    required String motionSourcePath,
    required String stillDestPath,
  }) async {
    if (kIsWeb) return null;

    final companionDest = companionPathForStill(stillDestPath);
    final mp4Path = await cachedMotionVideoPath(motionSourcePath);
    final mp4File = File(mp4Path);

    if (!await mp4File.exists()) {
      try {
        final index = await _validVideoIndex(motionSourcePath);
        if (index == null) {
          Logger.warn('No usable Motion Photo video index for remux', tag: _tag);
          return null;
        }
        final motion = MotionPhotos(motionSourcePath);
        final videoBytes = await motion.getMotionVideo(index: index);
        if (videoBytes.isEmpty || !_looksLikeMp4(videoBytes)) {
          Logger.warn(
            'Extracted Motion Photo video is empty or not MP4 (${videoBytes.length} bytes)',
            tag: _tag,
          );
          return null;
        }
        await mp4File.writeAsBytes(videoBytes, flush: true);
      } catch (ex, st) {
        Logger.error('Failed to extract Motion Photo video', error: ex, trace: st, tag: _tag);
        return null;
      }
    } else if (await mp4File.length() == 0) {
      Logger.warn('Cached Motion Photo MP4 is empty; refusing remux', tag: _tag);
      await mp4File.delete();
      return null;
    }

    final remuxed = await _remuxMp4ToMov(mp4Path, companionDest);
    if (!remuxed) {
      Logger.warn('Motion Photo remux failed', tag: _tag);
      return null;
    }

    Logger.info('Motion Photo companion remuxed → $companionDest', tag: _tag);
    return companionDest;
  }

  /// Reject indexes that would truncate to the whole file or an empty still.
  ///
  /// `motion_photos` can return `Item:Length=0` from the Primary XMP item, which
  /// yields `start == fileLength` and a zero-length "video".
  static Future<VideoIndex?> _validVideoIndex(String sourcePath) async {
    final motion = MotionPhotos(sourcePath);
    final index = await motion.getMotionVideoIndex();
    if (index == null) return null;

    final fileLen = await File(sourcePath).length();
    if (index.start <= 0 || index.videoLength <= 0 || index.start >= fileLen) {
      Logger.warn(
        'Ignoring invalid Motion Photo index start=${index.start} '
        'videoLength=${index.videoLength} fileLen=$fileLen',
        tag: _tag,
      );
      return null;
    }
    return index;
  }

  static bool _looksLikeMp4(Uint8List bytes) {
    if (bytes.length < 8) return false;
    // ISO BMFF: size (4) + 'ftyp' (4)
    return bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70;
  }

  static Future<bool> _remuxMp4ToMov(String mp4Path, String movPath) async {
    try {
      await File(movPath).parent.create(recursive: true);
      if (_useSystemFfmpeg) {
        final result = await Process.run('ffmpeg', [
          '-y',
          '-i',
          mp4Path,
          '-c',
          'copy',
          '-f',
          'mov',
          movPath,
        ]);
        if (result.exitCode != 0) {
          Logger.warn(
            'ffmpeg remux failed (rc=${result.exitCode}) stderr=${result.stderr}',
            tag: _tag,
          );
          return false;
        }
        return true;
      }

      final command = '-y '
          '-i "${_ffmpegEscapePath(mp4Path)}" '
          '-c copy -f mov '
          '"${_ffmpegEscapePath(movPath)}"';
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        Logger.warn('ffmpeg remux failed (rc=$returnCode) command="$command" logs=$logs', tag: _tag);
        return false;
      }
      return true;
    } catch (ex, st) {
      Logger.error('ffmpeg remux threw', error: ex, trace: st, tag: _tag);
      return false;
    }
  }

  static String _ffmpegEscapePath(String path) => path.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
