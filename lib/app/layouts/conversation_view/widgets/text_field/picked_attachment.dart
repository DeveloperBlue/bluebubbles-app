import 'dart:async';

import 'package:animations/animations.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/text_field/picked_motion_photo_controls.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/single_attachment_fullscreen_viewer.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mime_type/mime_type.dart';
import 'package:motion_photos/motion_photos.dart';
import 'package:universal_io/io.dart';

class PickedAttachment extends StatefulWidget {
  const PickedAttachment({
    super.key,
    required this.data,
    required this.controller,
    required this.onRemove,
    required this.pickedAttachmentIndex,
  });
  final PlatformFile data;
  final ConversationViewController? controller;
  final Function(PlatformFile) onRemove;
  final int pickedAttachmentIndex;

  @override
  State<PickedAttachment> createState() => _PickedAttachmentState();
}

class _PickedAttachmentState extends State<PickedAttachment> with AutomaticKeepAliveClientMixin, ThemeHelpers {
  Uint8List? imageBytes;
  String? imagePath;
  bool isLoading = true;
  bool isEmpty = false;
  bool thumbnailFailed = false;
  bool isMotionPhoto = false;
  Offset? _lastPointerGlobal;
  final _motionControlsKey = GlobalKey<PickedMotionPhotoControlsState>();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final file = widget.data;
    final mimeType = mime(widget.data.name) ?? "";
    if (mimeType.startsWith("video/") && !kIsWeb && !kIsDesktop) {
      try {
        imagePath = await AttachmentsSvc.getVideoThumbnail(file.path!, useCachedFile: false);
        if (imagePath == null) thumbnailFailed = true;
      } catch (ex) {
        thumbnailFailed = true;
      }
      setState(() {
        isLoading = false;
      });
    } else if (mimeType == "image/heic" ||
        mimeType == "image/heif" ||
        mimeType == "image/tif" ||
        mimeType == "image/tiff") {
      // Use ensureImageCompatibility to get a compatible file path.
      // Pass actualPath — attachment.path would be attachments/<null>/<abs path>.
      try {
        final fakeAttachment = Attachment(
          transferName: file.name,
          mimeType: mimeType,
        );
        imagePath = await AttachmentsSvc.ensureImageCompatibility(
          fakeAttachment,
          actualPath: file.path,
        );
        if (imagePath == null && file.bytes != null) {
          // Fallback to bytes if conversion returns null
          imageBytes = file.bytes;
        }
      } catch (ex) {
        // Fallback to bytes if conversion fails
        imageBytes = file.bytes;
      }
      await _detectMotionPhoto(file.path, mimeType);
      setState(() {
        isLoading = false;
      });
    } else if (mimeType.startsWith("image/")) {
      // Use file path if available, otherwise use bytes
      if (file.path != null) {
        imagePath = file.path;
      } else if (file.bytes != null) {
        imageBytes = file.bytes;
      } else {
        isEmpty = true;
      }
      await _detectMotionPhoto(file.path, mimeType);
      setState(() {
        isLoading = false;
      });
    } else {
      setState(() {
        isEmpty = true;
        isLoading = false;
      });
    }
  }

  Future<void> _detectMotionPhoto(String? path, String mimeType) async {
    if (!Platform.isAndroid || path == null || !mimeType.startsWith("image/")) return;
    try {
      isMotionPhoto = await MotionPhotos(path).isMotionPhoto();
    } catch (_) {
      // Sniffing failed — treat as a still image.
    }
  }

  void _showMotionMenu() {
    _motionControlsKey.currentState?.showMenuAt(_lastPointerGlobal ?? Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: iOS ? const EdgeInsets.all(5) : const EdgeInsets.only(top: 15, left: 7.5, right: 7.5, bottom: 15),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
            ),
            constraints: BoxConstraints(
                maxWidth: isLoading
                    ? 0
                    : isEmpty
                        ? 100
                        : 200),
            clipBehavior: Clip.antiAlias,
            child: OpenContainer(
                tappable: false,
                openColor: Colors.black,
                closedColor: context.theme.colorScheme.surface,
                openBuilder: (_, closeContainer) {
                  // Use the full file path as transferName for metadata/mime lookups.
                  // Pass widget.data straight through as the file — it's already the
                  // real PlatformFile (path and/or bytes), no need to round-trip it
                  // through AttachmentsSvc.getContent() like the gallery holder does.
                  final fakeAttachment = Attachment(
                    transferName: widget.data.path ?? widget.data.name,
                    mimeType: mime(widget.data.name) ?? "",
                    bytes: imageBytes ?? widget.data.bytes,
                  );
                  return SingleAttachmentFullscreenViewer(
                    file: widget.data,
                    attachment: fakeAttachment,
                    showInteractions: false,
                  );
                },
                closedBuilder: (_, openContainer) {
                  final mimeType = mime(widget.data.name) ?? "";
                  final isVideo = mimeType.startsWith("video/");
                  return InkWell(
                    onTap: mimeType.startsWith("image") || isVideo ? openContainer : null,
                    onTapDown: isMotionPhoto ? (details) => _lastPointerGlobal = details.globalPosition : null,
                    onLongPress: isMotionPhoto ? _showMotionMenu : null,
                    onSecondaryTapDown:
                        isMotionPhoto ? (details) => _lastPointerGlobal = details.globalPosition : null,
                    onSecondaryTap: isMotionPhoto ? _showMotionMenu : null,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topRight,
                      children: <Widget>[
                        if (!isEmpty && !isLoading) _buildImage(),
                        if (isEmpty)
                          Positioned.fill(
                            child: Container(
                              color: context.theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  widget.data.name,
                                  maxLines: 3,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        if (!isLoading && isVideo)
                          Positioned.fill(
                            child: Center(
                              child: Icon(
                                iOS ? CupertinoIcons.play_circle_fill : Icons.play_circle_filled,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),
                        if (!isLoading && isMotionPhoto)
                          PickedMotionPhotoControls(
                            key: _motionControlsKey,
                            controller: widget.controller,
                            path: widget.data.path,
                          ),
                        if (!isLoading && iOS)
                          Positioned(
                            top: 5,
                            right: 5,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: context.theme.colorScheme.outline,
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(0),
                                maximumSize: const Size(32, 32),
                                minimumSize: const Size(32, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Icon(
                                CupertinoIcons.xmark,
                                color: Colors.white,
                                size: 18,
                              ),
                              onPressed: () {
                                if (widget.controller != null) {
                                  widget.controller!.removePickedAttachmentAt(widget.pickedAttachmentIndex);
                                  final remaining = widget.controller!.pickedAttachments
                                      .where((e) => e.path != null)
                                      .map((e) => e.path!)
                                      .toList();
                                  unawaited(ChatsSvc.setChatTextFieldAttachments(widget.controller!.chat, remaining));
                                  // Don't request focus if attachment picker is open
                                  if (!widget.controller!.showAttachmentPicker.value) {
                                    widget.controller!.lastFocusedNode.requestFocus();
                                  }
                                } else {
                                  widget.onRemove.call(widget.data);
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                }),
          ),
          if (!iOS)
            Positioned(
              top: -7,
              right: -7,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: context.theme.colorScheme.secondary,
                  shape: CircleBorder(side: BorderSide(color: context.theme.colorScheme.surfaceContainerHighest)),
                  padding: const EdgeInsets.all(0),
                  maximumSize: const Size(25, 25),
                  minimumSize: const Size(25, 25),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Icon(
                  Icons.close,
                  color: context.theme.colorScheme.surface,
                  size: 18,
                ),
                onPressed: () {
                  if (widget.controller != null) {
                    widget.controller!.removePickedAttachmentAt(widget.pickedAttachmentIndex);
                    widget.controller!.chat.textFieldAttachments.removeWhere((e) => e == widget.data.path);
                    widget.controller!.chat.saveAsync(updateTextFieldAttachments: true);
                    // Don't request focus if attachment picker is open
                    if (!widget.controller!.showAttachmentPicker.value) {
                      widget.controller!.lastFocusedNode.requestFocus();
                    }
                  } else {
                    widget.onRemove.call(widget.data);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    // Use Image.file when we have a path (memory efficient)
    if (imagePath != null) {
      return Image.file(
        File(imagePath!),
        key: ValueKey(widget.data.path),
        gaplessPlayback: true,
        fit: iOS ? BoxFit.fitHeight : BoxFit.cover,
        height: iOS ? 150 : 75,
        width: iOS ? null : 75,
        cacheWidth: 300,
      );
    }

    // Fall back to Image.memory when we have bytes
    if (imageBytes != null) {
      return Image.memory(
        imageBytes!,
        key: ValueKey(widget.data.path),
        gaplessPlayback: true,
        fit: iOS ? BoxFit.fitHeight : BoxFit.cover,
        height: iOS ? 150 : 75,
        width: iOS ? null : 75,
        cacheWidth: 300,
      );
    }

    if (thumbnailFailed) {
      return Container(
        color: context.theme.colorScheme.surfaceContainerHighest,
        height: iOS ? 150 : 75,
        width: iOS ? null : 75,
      );
    }

    return const SizedBox.shrink();
  }

  @override
  bool get wantKeepAlive => true;
}
