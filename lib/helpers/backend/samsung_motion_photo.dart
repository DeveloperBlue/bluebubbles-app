import 'dart:typed_data';

/// Result of splitting an Android Motion Photo into a clean still + video.
class MotionPhotoSplit {
  final Uint8List still;
  final Uint8List video;

  /// `sef` (Samsung JPEG trailer), `mpvd` (HEIC/AVIF Android box), or `google`.
  final String kind;

  const MotionPhotoSplit({
    required this.still,
    required this.video,
    required this.kind,
  });
}

/// Pure-Dart parsers for Samsung SEF trailers and Android HEIC `mpvd` boxes.
///
/// Prefer these over XMP `Item:Length` / `motion_photos` for Samsung and HEIC
/// Motion Photos — XMP is advertising, not the trailer index (see ExifTool /
/// Immich guidance).
class SamsungMotionPhoto {
  SamsungMotionPhoto._();

  static const _motionPhotoData = 'MotionPhoto_Data';
  static const _embeddedVideoType = 0x0a30;

  /// Try Samsung SEF, then HEIC/AVIF `mpvd`. Returns null if neither matches.
  static MotionPhotoSplit? tryParse(Uint8List data) {
    return trySef(data) ?? tryMpvd(data);
  }

  /// Samsung JPEG/PNG SEF trailer ending in `SEFT` (ExifTool ProcessSamsungTrailer).
  static MotionPhotoSplit? trySef(Uint8List data) {
    if (data.length < 14) return null;

    // Trailer must end with 00 00 'SEFT' (or QDIOBS audio variant we ignore).
    final end = data.length;
    if (!_equalsAt(data, end - 6, const [0x00, 0x00, 0x53, 0x45, 0x46, 0x54])) {
      return null;
    }

    final bd = ByteData.sublistView(data);
    var blockEnd = end;
    // Walk backward over [payload][len u32le][TYPE] blocks until SEFT directory.
    for (;;) {
      if (blockEnd < 8) return null;
      final len = bd.getUint32(blockEnd - 8, Endian.little);
      final type = String.fromCharCodes(data.sublist(blockEnd - 4, blockEnd));
      if (len < 4 || len >= 0x10000 || len + 8 >= blockEnd) return null;
      final payloadStart = blockEnd - 8 - len;
      if (payloadStart < 0) return null;

      if (type != 'SEFT') {
        blockEnd = payloadStart;
        continue;
      }

      // Directory payload should begin with SEFH.
      if (!_equalsAt(data, payloadStart, const [0x53, 0x45, 0x46, 0x48])) {
        // Samsung Gallery sometimes corrupts trailers; bail.
        return null;
      }

      final dirPos = payloadStart;
      final count = bd.getUint32(dirPos + 8, Endian.little);
      if (12 + 12 * count > len) return null;

      var firstBlock = 0;
      for (var i = 0; i < count; i++) {
        final entry = 12 + 12 * i;
        final noff = bd.getUint32(dirPos + entry + 4, Endian.little);
        if (noff > firstBlock) firstBlock = noff;
      }
      if (firstBlock <= 0 || firstBlock > dirPos) return null;

      final trailerStart = dirPos - firstBlock;
      if (trailerStart <= 0 || trailerStart >= data.length) return null;

      Uint8List? video;
      for (var i = 0; i < count; i++) {
        final entry = 12 + 12 * i;
        final marker = bd.getUint16(dirPos + entry + 2, Endian.little);
        final noff = bd.getUint32(dirPos + entry + 4, Endian.little);
        final size = bd.getUint32(dirPos + entry + 8, Endian.little);
        if (noff > dirPos || size > noff || size < 8) return null;
        if (marker != _embeddedVideoType) continue;

        final fieldStart = dirPos - noff;
        final nameLen = bd.getUint32(fieldStart + 4, Endian.little);
        if (nameLen + 8 > size) return null;
        final name = String.fromCharCodes(data.sublist(fieldStart + 8, fieldStart + 8 + nameLen));
        if (name != _motionPhotoData && name.isNotEmpty) {
          // Unexpected name for 0x0a30 — still try payload after the name.
        }
        final videoStart = fieldStart + 8 + nameLen;
        final videoEnd = fieldStart + size;
        if (videoStart >= videoEnd) return null;
        video = data.sublist(videoStart, videoEnd);
        break;
      }
      if (video == null || video.isEmpty || !_looksLikeMp4(video)) return null;

      // Clean still = everything before the SEF trailer (JPEG through EOI + APP
      // segments; no MotionPhoto_Data / SEFH).
      final still = data.sublist(0, trailerStart);
      if (still.isEmpty) return null;
      return MotionPhotoSplit(still: still, video: video, kind: 'sef');
    }
  }

  /// Android Motion Photo HEIC/AVIF: top-level `mpvd` box after image boxes.
  static MotionPhotoSplit? tryMpvd(Uint8List data) {
    if (data.length < 16) return null;
    // Must look like ISOBMFF (ftyp at start).
    if (!_equalsAt(data, 4, const [0x66, 0x74, 0x79, 0x70])) return null;

    var offset = 0;
    while (offset + 8 <= data.length) {
      final size32 = ByteData.sublistView(data, offset, offset + 4).getUint32(0, Endian.big);
      final type = String.fromCharCodes(data.sublist(offset + 4, offset + 8));
      int boxSize;
      int headerLen;
      if (size32 == 1) {
        if (offset + 16 > data.length) return null;
        boxSize = ByteData.sublistView(data, offset + 8, offset + 16).getUint64(0, Endian.big);
        headerLen = 16;
      } else if (size32 == 0) {
        boxSize = data.length - offset;
        headerLen = 8;
      } else {
        boxSize = size32;
        headerLen = 8;
      }
      if (boxSize < headerLen || offset + boxSize > data.length) {
        // Truncated / incomplete container — not usable.
        return null;
      }

      if (type == 'mpvd') {
        final video = data.sublist(offset + headerLen, offset + boxSize);
        final still = data.sublist(0, offset);
        if (still.isEmpty || video.isEmpty || !_looksLikeMp4(video)) return null;
        return MotionPhotoSplit(still: still, video: video, kind: 'mpvd');
      }

      offset += boxSize;
    }
    return null;
  }

  static bool _looksLikeMp4(Uint8List bytes) {
    if (bytes.length < 8) return false;
    return bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70;
  }

  static bool _equalsAt(Uint8List data, int offset, List<int> expected) {
    if (offset < 0 || offset + expected.length > data.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (data[offset + i] != expected[i]) return false;
    }
    return true;
  }
}
