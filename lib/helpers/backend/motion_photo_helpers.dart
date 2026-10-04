import 'dart:convert';
import 'dart:typed_data';

import 'package:bluebubbles/helpers/backend/samsung_motion_photo.dart';
import 'package:bluebubbles/services/backend/filesystem/filesystem_service.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:motion_photos/motion_photos.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

/// Result of [MotionPhotoHelpers.truncateStill].
class MotionStillTruncate {
  /// Byte length of the still written to disk (for `Attachment.totalBytes`).
  final int byteLength;

  /// True when an HEIC/AVIF Motion Photo still was re-encoded to JPEG.
  final bool convertedToJpeg;

  const MotionStillTruncate({
    required this.byteLength,
    this.convertedToJpeg = false,
  });
}

/// Android Motion Photo → Live Photo send helpers.
///
/// Split across prep and send so the bubble can appear before remux:
///
/// 1. [truncateStill] — called from staging on the main isolate (before the
///    bubble appears). Writes a clean still (byte-split, then ffmpeg sanitize
///    to strip leftover Motion Photo XMP / repair HEIC). When Live Photo send
///    is allowed, the caller sets `metadata['motion_source_path']` and
///    optimistic `hasLivePhoto`.
/// 2. [remuxCompanion] — called from send on the **main** isolate (FFmpegKit
///    uses platform channels and cannot run in GlobalIsolate). Extracts the
///    embedded MP4 and remuxes → same-stem `.mov` (`ffmpeg -c copy`). The
///    isolate only uploads the resulting path.
///
/// Split order: Samsung SEF → HEIC `mpvd` → Google/`motion_photos` XMP+mp42.
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

  /// Extract embedded Motion Photo video bytes (Samsung SEF, HEIC `mpvd`, or Google).
  ///
  /// Used by local playback (`LivePhotoMixin`) as well as send remux.
  static Future<Uint8List?> extractVideoBytes(String sourcePath) async {
    if (kIsWeb) return null;
    final split = await _split(sourcePath);
    return split?.video;
  }

  /// If [sourcePath] is a Motion Photo with a real embedded video, write a clean
  /// still (no embedded video / SEF trailer / `mpvd`, no Motion Photo XMP) and
  /// return it.
  ///
  /// Byte-split first, then ffmpeg re-encode with `-map_metadata -1` so Apple
  /// does not see a still that still advertises an embedded video. HEIC/`mpvd`
  /// stills are emitted as JPEG (extension may change).
  ///
  /// Called from prep on the main isolate (before the bubble appears).
  /// Returns null when the file is not a usable Motion Photo (caller should copy as-is).
  static Future<MotionStillTruncate?> truncateStill({
    required String sourcePath,
    required String stillDestPath,
  }) async {
    if (kIsWeb) return null;

    final split = await _split(sourcePath);
    if (split == null) return null;

    await File(stillDestPath).parent.create(recursive: true);

    final ext = p.extension(stillDestPath).toLowerCase();
    final needsJpegOut = split.kind == 'mpvd' || ext == '.heic' || ext == '.heif';
    final outPath = needsJpegOut ? p.setExtension(stillDestPath, '.jpg') : stillDestPath;

    final truncPath = '$stillDestPath.motion_trunc';
    await File(truncPath).writeAsBytes(split.still, flush: true);

    var sanitizeMethod = 'none';
    Uint8List? outBytes;
    try {
      final ffmpegOk = await _ffmpegExtractStill(truncPath, outPath);
      if (ffmpegOk && await File(outPath).exists()) {
        outBytes = await File(outPath).readAsBytes();
        sanitizeMethod = 'ffmpeg';
      }
    } catch (ex, st) {
      Logger.warn('ffmpeg still sanitize threw; trying JPEG XMP strip', error: ex, tag: _tag);
      Logger.debug('$st', tag: _tag);
    }

    // Lossless fallback for JPEG when ffmpeg sanitize fails. Byte-truncation
    // removes the embedded video but leaves GCamera / MotionPhoto XMP that still
    // advertises a companion — Apple/iMessage can reject or mis-handle that
    // still. Used for Live Photo send staging and for future still-only sends.
    if (outBytes == null && !needsJpegOut) {
      final stripped = _stripJpegXmp(split.still);
      if (stripped != null) {
        await File(outPath).writeAsBytes(stripped, flush: true);
        outBytes = stripped;
        sanitizeMethod = 'xmp-strip';
      }
    }

    try {
      await File(truncPath).delete();
    } catch (_) {}

    if (outBytes == null) {
      if (needsJpegOut) {
        // Last resort when HEIC→JPEG sanitize fails (broken truncated HEIC, or
        // min FFmpegKit missing a decoder). Keep the byte-chopped HEIC at the
        // original path rather than claiming a .jpg we never produced — prep
        // can still proceed; Apple may still dislike the container.
        await File(stillDestPath).writeAsBytes(split.still, flush: true);
        outBytes = split.still;
        sanitizeMethod = 'truncate-only-heic';
        Logger.warn(
          'Motion Photo HEIC sanitize failed; wrote truncated HEIC → $stillDestPath',
          tag: _tag,
        );
        return MotionStillTruncate(byteLength: outBytes.length);
      }
      // Last resort: write the byte-truncated still (may still carry Motion Photo XMP).
      await File(outPath).writeAsBytes(split.still, flush: true);
      outBytes = split.still;
      sanitizeMethod = 'truncate-only';
      Logger.warn(
        'Motion Photo still sanitize failed; wrote truncated bytes only → $outPath',
        tag: _tag,
      );
    }

    if (needsJpegOut && outPath != stillDestPath) {
      try {
        if (await File(stillDestPath).exists()) await File(stillDestPath).delete();
      } catch (_) {}
    }

    Logger.info(
      'Motion Photo still ready (${split.kind}, sanitize=$sanitizeMethod) → $outPath (${outBytes.length} bytes)',
      tag: _tag,
    );
    return MotionStillTruncate(
      byteLength: outBytes.length,
      convertedToJpeg: needsJpegOut,
    );
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
        final split = await _split(motionSourcePath);
        if (split == null) {
          Logger.warn('No usable Motion Photo split for remux', tag: _tag);
          return null;
        }
        await mp4File.writeAsBytes(split.video, flush: true);
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

  /// Samsung SEF → HEIC `mpvd` → Google/`motion_photos`.
  static Future<MotionPhotoSplit?> _split(String sourcePath) async {
    final data = await File(sourcePath).readAsBytes();
    final native = SamsungMotionPhoto.tryParse(data);
    if (native != null) {
      Logger.info(
        'Motion Photo split via ${native.kind} '
        '(still=${native.still.length}, video=${native.video.length})',
        tag: _tag,
      );
      return native;
    }
    return _tryGoogleSplit(sourcePath, data);
  }

  /// Fallback for Pixel / Google MicroVideo-style files via `motion_photos`.
  static Future<MotionPhotoSplit?> _tryGoogleSplit(String sourcePath, Uint8List data) async {
    final motion = MotionPhotos(sourcePath);
    final index = await motion.getMotionVideoIndex();
    if (index == null) return null;

    final fileLen = data.length;
    if (index.start <= 0 || index.videoLength <= 0 || index.start >= fileLen) {
      Logger.warn(
        'Ignoring invalid Google Motion Photo index start=${index.start} '
        'videoLength=${index.videoLength} fileLen=$fileLen',
        tag: _tag,
      );
      return null;
    }
    if (index.start + index.videoLength > fileLen) {
      Logger.warn(
        'Ignoring Google Motion Photo index that extends past EOF '
        '(end=${index.start + index.videoLength}, fileLen=$fileLen)',
        tag: _tag,
      );
      return null;
    }

    final still = data.sublist(0, index.start);
    final video = data.sublist(index.start, index.start + index.videoLength);
    if (video.isEmpty || !_looksLikeMp4(video)) {
      Logger.warn(
        'Google Motion Photo video is empty or not MP4 (${video.length} bytes)',
        tag: _tag,
      );
      return null;
    }
    Logger.info(
      'Motion Photo split via google (still=${still.length}, video=${video.length})',
      tag: _tag,
    );
    return MotionPhotoSplit(still: still, video: video, kind: 'google');
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

  /// Decode [inputPath] to a single clean JPEG at [outputPath] with no metadata.
  ///
  /// Strips GCamera Motion Photo XMP that survives byte-truncation and repairs
  /// HEIC containers left with a dangling `mpvd` header.
  static Future<bool> _ffmpegExtractStill(String inputPath, String outputPath) async {
    try {
      await File(outputPath).parent.create(recursive: true);
      if (_useSystemFfmpeg) {
        final result = await Process.run('ffmpeg', [
          '-y',
          '-i',
          inputPath,
          '-map_metadata',
          '-1',
          '-frames:v',
          '1',
          '-q:v',
          '2',
          outputPath,
        ]);
        if (result.exitCode != 0) {
          Logger.warn(
            'ffmpeg still extract failed (rc=${result.exitCode}) stderr=${result.stderr}',
            tag: _tag,
          );
          return false;
        }
      } else {
        final command = '-y '
            '-i "${_ffmpegEscapePath(inputPath)}" '
            '-map_metadata -1 -frames:v 1 -q:v 2 '
            '"${_ffmpegEscapePath(outputPath)}"';
        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();
        if (!ReturnCode.isSuccess(returnCode)) {
          final logs = await session.getAllLogsAsString();
          Logger.warn('ffmpeg still extract failed (rc=$returnCode) command="$command" logs=$logs', tag: _tag);
          return false;
        }
      }
      final out = File(outputPath);
      return await out.exists() && await out.length() > 0;
    } catch (ex, st) {
      Logger.error('ffmpeg still extract threw', error: ex, trace: st, tag: _tag);
      return false;
    }
  }

  /// Remove JPEG APP1 XMP packets (lossless). Returns null if not a JPEG or no XMP.
  ///
  /// Byte-truncating a Google Motion Photo leaves the still + GCamera XMP that
  /// still advertises an embedded video. Without stripping that XMP (or
  /// re-encoding via ffmpeg), Apple/iMessage can fail or mis-handle the still —
  /// including when we later send Motion Photos as stills only.
  static Uint8List? _stripJpegXmp(Uint8List data) {
    if (data.length < 4 || data[0] != 0xff || data[1] != 0xd8) return null;
    final out = BytesBuilder(copy: false);
    out.add([0xff, 0xd8]);
    var i = 2;
    var stripped = false;
    while (i + 3 < data.length) {
      if (data[i] != 0xff) {
        out.add(data.sublist(i));
        break;
      }
      final marker = data[i + 1];
      if (marker == 0xd9) {
        out.add([0xff, 0xd9]);
        break;
      }
      if (marker == 0xda) {
        out.add(data.sublist(i));
        break;
      }
      if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
        out.add([0xff, marker]);
        i += 2;
        continue;
      }
      if (i + 4 > data.length) break;
      final seglen = (data[i + 2] << 8) | data[i + 3];
      if (seglen < 2 || i + 2 + seglen > data.length) {
        out.add(data.sublist(i));
        break;
      }
      final isXmp = marker == 0xe1 &&
          seglen >= 31 &&
          i + 4 + 29 <= data.length &&
          _indexOf(data, utf8.encode('http://ns.adobe.com/xap/1.0/'), i + 4) == i + 4;
      if (isXmp) {
        stripped = true;
        i += 2 + seglen;
        continue;
      }
      out.add(data.sublist(i, i + 2 + seglen));
      i += 2 + seglen;
    }
    if (!stripped) return null;
    return out.toBytes();
  }

  static int _indexOf(Uint8List data, List<int> pattern, [int start = 0]) {
    if (pattern.isEmpty || data.length < pattern.length) return -1;
    outer:
    for (var i = start; i <= data.length - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static String _ffmpegEscapePath(String path) => path.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
