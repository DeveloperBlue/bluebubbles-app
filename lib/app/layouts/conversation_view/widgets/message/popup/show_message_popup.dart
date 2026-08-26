import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

void _noopTapback([String? type, int? part]) {}

bool _allowDetailsOverlayPointers(MessagePart part) {
  return part.attachments.any((a) => a.mimeStart == 'video') && !SettingsSvc.settings.highPerfMode.value;
}

/// Presents [MessagePopup] as a translucent fullscreen route over [context].
///
/// [childPosition] should be the child's global origin from [RenderBox.localToGlobal];
/// this function subtracts view padding and the chat-list inset.
///
/// [origin] controls Material selection highlighting, composer focus, overlay
/// child pointer events, tapback chrome, and action routing (see
/// [MessagePopupActionContext.dismissForThread]).
Future<dynamic> showMessagePopup({
  required BuildContext context,
  required Size size,
  required Offset childPosition,
  required Widget child,
  required MessagePart part,
  required MessageState controller,
  required ConversationViewController cvController,
  required BuildContext? Function() widthContext,
  Function([String? type, int? part])? sendTapback,
  MessagePopupOrigin origin = MessagePopupOrigin.conversation,
  RxList<String>? detailsSelected,
  String? detailsAttachmentGuid,
  VoidCallback? popToConversation,
  ValueChanged<Message>? onMessageDeleted,
}) async {
  HapticFeedback.lightImpact();

  final usesConversationChrome = origin.usesConversationChrome;
  final isIos = SettingsSvc.settings.skin.value == Skins.iOS;
  if (usesConversationChrome) {
    cvController.focusNode.unfocus();
    cvController.subjectFocusNode.unfocus();
  }

  final adjustedPosition = Offset(
    childPosition.dx -
        MediaQueryData.fromView(View.of(context)).padding.left -
        (isIos ? 0 : NavigationSvc.widthChatListLeft(context)),
    childPosition.dy,
  );

  final serverDetails = SettingsSvc.serverDetails;
  if (usesConversationChrome && !isIos) {
    cvController.selected.add(controller.message);
  }

  // Details wraps most overlays in IgnorePointer (tap handled by MessagePopup).
  // Conversation + collection keep a live child so tapbacks / media controls work.
  final overlayChild = usesConversationChrome || _allowDetailsOverlayPointers(part)
      ? child
      : IgnorePointer(child: child);

  if (kIsDesktop || kIsWeb) {
    cvController.showingOverlays = true;
  }

  final chatState = ChatStateScope.of(context);
  // Capture the conversation's theme before pushing the route — if adaptive
  // theming is active, context.theme is already the per-chat theme.
  final capturedTheme = context.theme;
  final capturedIsM3 = ThemeSvc.isMaterialYouActive(context);
  final capturedBubbleExt = capturedTheme.extensions[BubbleColors] as BubbleColors?;

  final result = await Navigator.push(
    isIos ? Get.context! : context,
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: Theme(
            data: capturedTheme.copyWith(
              // in case some components still use legacy theming
              primaryColor: capturedBubbleExt?.iMessageBubbleColor ?? capturedTheme.colorScheme.primary,
              colorScheme: capturedTheme.colorScheme.copyWith(
                primary: capturedBubbleExt?.iMessageBubbleColor ?? capturedTheme.colorScheme.primary,
                onPrimary: capturedBubbleExt?.oniMessageBubbleColor ?? capturedTheme.colorScheme.onPrimary,
                surface: capturedIsM3 ? null : capturedBubbleExt?.receivedBubbleColor,
                onSurface: capturedIsM3 ? null : capturedBubbleExt?.onReceivedBubbleColor,
              ),
            ),
            child: ChatStateScope(
              chatState: chatState,
              child: PopupScope(
                child: MessagePopup(
                  childPosition: adjustedPosition,
                  size: size,
                  part: part,
                  controller: controller,
                  cvController: cvController,
                  serverDetails: MessagePopupServerDetails(
                    minSierra: serverDetails.isMinSierra,
                    minBigSur: serverDetails.isMinBigSur,
                    supportsOriginalDownload: serverDetails.serverVersionCode > 100,
                  ),
                  sendTapback: sendTapback ?? _noopTapback,
                  widthContext: widthContext,
                  origin: origin,
                  detailsSelected: detailsSelected,
                  detailsAttachmentGuid: detailsAttachmentGuid,
                  popToConversation: popToConversation,
                  onMessageDeleted: onMessageDeleted,
                  child: overlayChild,
                ),
              ),
            ),
          ),
        );
      },
      fullscreenDialog: true,
      opaque: false,
      barrierDismissible: true,
    ),
  );

  if (usesConversationChrome && result != false) {
    cvController.selected.clear();
  }
  if (kIsDesktop || kIsWeb) {
    cvController.showingOverlays = false;
    if (usesConversationChrome) {
      if (cvController.editing.isEmpty) {
        cvController.focusNode.requestFocus();
      } else {
        // This delay is necessary because there is a second instance of the focus node in the popup which gets focused otherwise
        // The autofocus doesn't seem to work on desktop
        Future.delayed(
          const Duration(milliseconds: 500),
          () => cvController.editing.last.controller.focusNode?.requestFocus(),
        );
      }
    }
  }
  return result;
}

class PopupScope extends InheritedWidget {
  const PopupScope({
    super.key,
    required super.child,
  });

  static PopupScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PopupScope>();
  }

  static PopupScope of(BuildContext context) {
    final PopupScope? result = maybeOf(context);
    assert(result != null, 'No PopupScope found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(PopupScope oldWidget) => true;
}
