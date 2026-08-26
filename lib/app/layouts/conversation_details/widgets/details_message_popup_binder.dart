import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/attachment_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/interactive_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/show_message_popup.dart';
import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:universal_html/html.dart' as html;

/// Long-press / right-click wrapper that opens [showMessagePopup] for a details
/// tile. Does not enable double-tap or quick-tapback.
class DetailsMessagePopupBinder extends StatefulWidget {
  const DetailsMessagePopupBinder({
    super.key,
    required this.chat,
    required this.child,
    this.attachment,
    this.message,
    this.selected,
    this.onMessageDeleted,
    this.popAttachmentsRoute = false,
  }) : assert(attachment != null || message != null);

  final Chat chat;
  final Widget child;
  final Attachment? attachment;
  final Message? message;
  final RxList<String>? selected;
  final ValueChanged<Message>? onMessageDeleted;

  /// When true, [popToConversation] pops [ConversationAttachments] then
  /// [ConversationDetails]. When false, only [ConversationDetails] is popped.
  final bool popAttachmentsRoute;

  @override
  State<DetailsMessagePopupBinder> createState() => _DetailsMessagePopupBinderState();
}

class _DetailsMessagePopupBinderState extends State<DetailsMessagePopupBinder> {
  final GlobalKey _key = GlobalKey();

  void _openPopup() {
    final size = _key.currentContext?.size;
    final childPos = (_key.currentContext?.findRenderObject() as RenderBox?)?.localToGlobal(Offset.zero);
    if (size == null || childPos == null) return;

    final chatGuid = widget.chat.guid;
    if (!Get.isRegistered<ConversationViewController>(tag: chatGuid)) return;
    final service = maybeFindMessagesSvc(chatGuid);
    if (service == null) return;

    final message = widget.message ?? widget.attachment?.message.target;
    if (message == null) return;

    final cvController = Get.find<ConversationViewController>(tag: chatGuid);
    final messageState = service.getOrCreateState(message);
    final part = _partFor(messageState, widget.attachment);

    final navigator = Navigator.of(context);
    final popAttachmentsRoute = widget.popAttachmentsRoute;

    showMessagePopup(
      context: context,
      size: _overlaySize(size, widget.attachment),
      childPosition: childPos,
      child: _overlayChild(part),
      part: part,
      controller: messageState,
      cvController: cvController,
      widthContext: () => mounted ? context : null,
      origin: MessagePopupOrigin.details,
      detailsSelected: widget.selected,
      detailsAttachmentGuid: widget.attachment?.guid,
      onMessageDeleted: widget.onMessageDeleted,
      popToConversation: () {
        if (popAttachmentsRoute && navigator.canPop()) {
          navigator.pop();
        }
        if (navigator.canPop()) {
          navigator.pop();
        }
      },
    );
  }

  /// Conversation-view attachment box (50% pane × 60% screen), not the grid cell.
  Size _overlaySize(Size tileSize, Attachment? attachment) {
    final halfWidth = NavigationSvc.width(context) * 0.5;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    if (attachment != null && (attachment.mimeStart == 'image' || attachment.mimeStart == 'video')) {
      final box = attachment.displayBox(halfWidth, maxHeight);
      return Size(box.width, box.height);
    }
    if (attachment != null) {
      return Size(halfWidth, tileSize.height);
    }
    final linkWidth = NavigationSvc.width(context) * (NavigationSvc.isTabletMode(context) ? 0.5 : 0.6);
    return Size(linkWidth, tileSize.height);
  }

  Widget _overlayChild(MessagePart part) {
    if (widget.attachment != null) {
      return AttachmentHolder(
        message: part,
        transparentBackground: true,
        showCardShadow: true,
      );
    }
    return InteractiveHolder(message: part);
  }

  MessagePart _partFor(MessageState state, Attachment? attachment) {
    state.buildMessageParts();
    if (attachment == null) {
      return state.parts.firstWhereOrNull((p) => p.part == 0) ?? MessagePart(part: 0);
    }

    final match = state.parts.firstWhereOrNull(
      (p) => p.attachments.any((a) => a.guid != null && a.guid == attachment.guid),
    );
    if (match == null) {
      return MessagePart(part: 0, attachments: [attachment]);
    }
    if (match.attachments.length == 1) return match;

    final idx = match.attachments.indexWhere((a) => a.guid != null && a.guid == attachment.guid);
    if (idx < 0) {
      return MessagePart(part: match.part, attachments: [attachment]);
    }
    return MessagePart(
      part: match.partIndexForAttachment(idx),
      attachments: [match.attachments[idx]],
      shouldRedact: match.shouldRedact,
      mentions: const [],
      edits: const [],
      isUnsent: match.isUnsent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _key,
      onLongPress: _openPopup,
      onSecondaryTapUp: (details) async {
        if (!kIsWeb && !kIsDesktop) return;
        if (kIsWeb) {
          (await html.document.onContextMenu.first).preventDefault();
        }
        _openPopup();
      },
      child: widget.child,
    );
  }
}
