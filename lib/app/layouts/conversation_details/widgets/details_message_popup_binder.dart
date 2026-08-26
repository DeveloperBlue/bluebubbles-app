import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/attachment_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/interactive_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/show_message_popup.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:universal_html/html.dart' as html;

/// Long-press / right-click wrapper that opens [showMessagePopup] for a details
/// tile or collection-gallery cell. Does not enable double-tap or quick-tapback
/// shortcuts; collection origin still shows the in-popup reaction picker.
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
    this.origin = MessagePopupOrigin.details,
  }) : assert(attachment != null || message != null);

  final Chat chat;
  final Widget child;
  final Attachment? attachment;
  final Message? message;
  final RxList<String>? selected;
  final ValueChanged<Message>? onMessageDeleted;
  final MessagePopupOrigin origin;

  /// When true and [origin] is details, [popToConversation] pops
  /// [ConversationAttachments] then [ConversationDetails]. When false, only the
  /// current host route is popped. Ignored for [MessagePopupOrigin.collection]
  /// (always a single pop of the gallery).
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
    final origin = widget.origin;

    showMessagePopup(
      context: context,
      size: _overlaySize(size, widget.attachment),
      childPosition: childPos,
      child: _overlayChild(part),
      part: part,
      controller: messageState,
      cvController: cvController,
      widthContext: () => mounted ? context : null,
      origin: origin,
      sendTapback: origin.usesConversationChrome ? _sendTapback : null,
      detailsSelected: origin == MessagePopupOrigin.details || origin == MessagePopupOrigin.collection
          ? widget.selected
          : null,
      detailsAttachmentGuid: widget.attachment?.guid,
      onMessageDeleted: widget.onMessageDeleted,
      popToConversation: () {
        if (origin == MessagePopupOrigin.collection) {
          if (navigator.canPop()) navigator.pop();
          return;
        }
        if (popAttachmentsRoute && navigator.canPop()) {
          navigator.pop();
        }
        if (navigator.canPop()) {
          navigator.pop();
        }
      },
    );
  }

  void _sendTapback([String? type, int? part]) {
    HapticFeedback.lightImpact();
    final message = widget.message ?? widget.attachment?.message.target;
    if (message == null) return;

    final reaction = type ?? SettingsSvc.settings.quickTapbackType.value;
    Logger.info("Sending reaction type: $reaction");

    final tempMessage = Message(
      associatedMessageGuid: message.guid,
      associatedMessageType: reaction,
      associatedMessagePart: part,
      dateCreated: DateTime.now(),
      hasAttachments: false,
      isFromMe: true,
      handleId: 0,
    );

    OutgoingMsgHandler.queue(
      OutgoingReaction(
        chat: message.chat.target ?? ChatStateScope.chatOf(context),
        message: tempMessage,
        selectedMessage: message,
        reaction: reaction,
      ),
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
      return AttachmentHolder(message: part);
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
      part: match.partIdForAttachment(idx),
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
