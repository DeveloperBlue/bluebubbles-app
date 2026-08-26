import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/details_menu_action.dart';
import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/ui/chat/conversation_view_controller.dart';
import 'package:bluebubbles/services/ui/message/messages_service.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Where the message popup was opened from. Controls tapback chrome, Material
/// selection highlighting, and origin-specific action routing.
enum MessagePopupOrigin {
  conversation,
  details,

  /// Collection overview gallery — conversation chrome (tapbacks + full menu),
  /// but [dismissForThread] pops the gallery host route.
  collection;

  /// Tapbacks, composer focus, and Material selection highlighting.
  bool get usesConversationChrome => this != details;

  /// Reply / thread / DM / etc. also pop the host route above the conversation.
  bool get popsHostOnDismiss => this == details || this == collection;

  /// Column-aligned menu for media grids (details + collection gallery).
  bool get usesGridMenuLayout => this == details || this == collection;

  /// Details-only action omissions and overlay tap-to-fullscreen.
  bool get usesDetailsMenuGates => this == details;
}

class MessagePopupServerDetails {
  final bool minSierra;
  final bool minBigSur;
  final bool supportsOriginalDownload;

  const MessagePopupServerDetails({
    required this.minSierra,
    required this.minBigSur,
    required this.supportsOriginalDownload,
  });
}

class MessagePopupActionContext {
  final BuildContext context;
  final BuildContext widthContext;
  final ConversationViewController cvController;
  final MessageState messageState;
  final Message message;
  final MessagePart part;
  final Chat chat;
  final MessagesService service;
  final MessagePopupServerDetails serverDetails;
  final DetailsMenuAction action;
  final void Function({bool returnVal}) popDetails;
  final void Function(String title, String body) showSnack;
  final Chat? dmChat;
  final bool isEmbeddedMedia;
  final MessagePopupOrigin origin;

  /// Host-grid multi-select (details media or collection gallery). Null when the
  /// popup was not opened from a section that supports GUID selection.
  final RxList<String>? detailsSelected;
  final String? detailsAttachmentGuid;

  /// Pops ConversationAttachments (if present) then ConversationDetails.
  /// The binder must capture the details [Navigator] before the popup is pushed;
  /// do not use [context] after [popDetails].
  final VoidCallback? popToConversation;

  final ValueChanged<Message>? onMessageDeleted;

  const MessagePopupActionContext({
    required this.context,
    required this.widthContext,
    required this.cvController,
    required this.messageState,
    required this.message,
    required this.part,
    required this.chat,
    required this.service,
    required this.serverDetails,
    required this.action,
    required this.popDetails,
    required this.showSnack,
    required this.dmChat,
    required this.isEmbeddedMedia,
    this.origin = MessagePopupOrigin.conversation,
    this.detailsSelected,
    this.detailsAttachmentGuid,
    this.popToConversation,
    this.onMessageDeleted,
  });

  /// Closes the popup, then pops the host route when opened from details or
  /// the collection gallery.
  void dismissForThread({bool returnVal = true}) {
    popDetails(returnVal: returnVal);
    if (origin.popsHostOnDismiss) {
      popToConversation?.call();
    }
  }
}
