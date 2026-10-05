import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Compose-tray Motion Photo badges + options menu for [PickedAttachment].
///
/// Tap the badge to toggle Live ↔ still. Long-press / right-click (on the badge
/// or via [showMenuAt] from the parent preview) opens an overlay menu.
class PickedMotionPhotoControls extends StatefulWidget {
  const PickedMotionPhotoControls({
    super.key,
    required this.controller,
    required this.path,
  });

  final ConversationViewController? controller;
  final String? path;

  @override
  State<PickedMotionPhotoControls> createState() => PickedMotionPhotoControlsState();
}

class PickedMotionPhotoControlsState extends State<PickedMotionPhotoControls> with ThemeHelpers {
  late bool sendAsLivePhoto;
  late bool muteMotionAudio;
  Offset? _lastPointerGlobal;
  OverlayEntry? _menuEntry;

  @override
  void initState() {
    super.initState();
    final opts = widget.controller?.getMotionPhotoOptions(widget.path);
    sendAsLivePhoto = opts?.sendAsLivePhoto ?? !SettingsSvc.settings.motionPhotoSendAsStill.value;
    muteMotionAudio = opts?.muteMotionAudio ?? SettingsSvc.settings.motionPhotoMuteAudio.value;
  }

  @override
  void dispose() {
    _dismissMenu();
    super.dispose();
  }

  void _update({bool? sendAsLivePhoto, bool? muteMotionAudio}) {
    final nextLive = sendAsLivePhoto ?? this.sendAsLivePhoto;
    final nextMute = muteMotionAudio ?? this.muteMotionAudio;
    if (nextLive == this.sendAsLivePhoto && nextMute == this.muteMotionAudio) return;
    setState(() {
      this.sendAsLivePhoto = nextLive;
      this.muteMotionAudio = nextMute;
      final path = widget.path;
      if (path != null && widget.controller != null) {
        final opts = widget.controller!.ensureMotionPhotoOptions(path);
        opts.sendAsLivePhoto = nextLive;
        opts.muteMotionAudio = nextMute;
      }
    });
  }

  void _dismissMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
  }

  /// Show the options menu above [globalPosition] (keyboard-safe overlay).
  void showMenuAt(Offset globalPosition) {
    if (!mounted) return;
    _dismissMenu();
    HapticFeedback.mediumImpact();

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final local = overlayBox?.globalToLocal(globalPosition) ?? globalPosition;
    final screen = MediaQuery.sizeOf(context);
    const menuWidth = 240.0;
    const menuHeight = 96.0; // two rows
    final left = local.dx.clamp(8.0, screen.width - menuWidth - 8.0);
    var top = local.dy - menuHeight - 8.0;
    if (top < 8.0) top = local.dy + 8.0;
    top = top.clamp(8.0, (screen.height - menuHeight - 8.0).clamp(8.0, double.infinity));

    final color = context.theme.colorScheme.onSurfaceVariant;
    final bg = context.theme.colorScheme.surfaceContainerHighest;

    Widget row({
      required IconData icon,
      required String label,
      required VoidCallback? onTap,
    }) {
      final c = onTap != null ? color : color.withValues(alpha: 0.38);
      return InkWell(
        canRequestFocus: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 12.0),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(icon, color: c, size: 20),
              ),
              Expanded(
                child: Text(label, style: context.theme.textTheme.bodyLarge!.copyWith(color: c)),
              ),
            ],
          ),
        ),
      );
    }

    _menuEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissMenu,
              onSecondaryTap: _dismissMenu,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: Material(
              color: bg,
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(iOS ? 10 : 0)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  row(
                    icon: sendAsLivePhoto
                        ? Icons.motion_photos_off_outlined
                        : Icons.motion_photos_on_outlined,
                    label: sendAsLivePhoto ? 'Send as Photo' : 'Send as Live Photo',
                    onTap: () {
                      _dismissMenu();
                      _update(sendAsLivePhoto: !sendAsLivePhoto);
                    },
                  ),
                  row(
                    icon: muteMotionAudio ? Icons.volume_up : Icons.volume_off,
                    label: muteMotionAudio ? 'Unmute audio' : 'Mute audio',
                    onTap: sendAsLivePhoto
                        ? () {
                            _dismissMenu();
                            _update(muteMotionAudio: !muteMotionAudio);
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_menuEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 6,
      left: 6,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          _update(sendAsLivePhoto: !sendAsLivePhoto);
        },
        onTapDown: (details) => _lastPointerGlobal = details.globalPosition,
        onLongPress: () => showMenuAt(_lastPointerGlobal ?? Offset.zero),
        onSecondaryTapDown: (details) => _lastPointerGlobal = details.globalPosition,
        onSecondaryTap: () => showMenuAt(_lastPointerGlobal ?? Offset.zero),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              sendAsLivePhoto ? Icons.motion_photos_on_outlined : Icons.motion_photos_off_outlined,
              color: Colors.white,
              size: 18,
            ),
            if (sendAsLivePhoto && muteMotionAudio)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.volume_off, color: Colors.white, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
