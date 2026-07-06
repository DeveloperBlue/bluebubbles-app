import 'dart:math';

import 'package:animations/animations.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/attachment_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/image_viewer.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/video_player.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup_holder.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/fullscreen_holder.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// Collage Widget - renders 2-3 visual media attachments with overlap
class CollageWidget extends StatelessWidget {
  final PartGroup partGroup;
  final MessageWidgetController parentController;
  final ConversationViewController cvController;
  final Message message;
  final bool showAvatar;
  final Message? newerMessage;
  final Message? olderMessage;
  final bool showSender;
  
  // ... existing params

  @override
  Widget build(BuildContext context) {
    final isLastElement = /* check if this is last in messageElements */;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: message.isFromMe! ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // Show sender for first part if needed
        if (chat.isGroup && !message.isFromMe! && showSender && 
            partGroup.parts.first.part == (messageParts.firstWhereOrNull((e) => !e.isUnsent)?.part))
          Padding(
            padding: showAvatar || ss.settings.alwaysShowAvatars.value
                ? EdgeInsets.only(left: 35.0 * ss.settings.avatarScale.value) 
                : EdgeInsets.zero,
            child: MessageSender(olderMessage: olderMessage, message: message),
          ),
        
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            // Avatar at bottom if this is the last element
            if (isLastElement && 
                message.showTail(newerMessage) && 
                (showAvatar || ss.settings.alwaysShowAvatars.value) &&
                !message.isFromMe! && 
                !message.isGroupEvent)
              Padding(
                padding: const EdgeInsets.only(left: 5.0),
                child: ContactAvatarWidget(
                  handle: message.handle,
                  size: iOS ? 30 : 35,
                  fontSize: context.theme.textTheme.bodyLarge!.fontSize!,
                  borderThickness: 0.1,
                ),
              ),
            
            Padding(
              padding: (showAvatar || ss.settings.alwaysShowAvatars.value)
                  ? EdgeInsets.only(left: 35.0 * ss.settings.avatarScale.value) 
                  : EdgeInsets.zero,
              child: Obx(() => GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: cvController.inSelectMode.value ? () {
                  if (cvController.isSelected(message.guid!)) {
                    cvController.selected.remove(message);
                  } else {
                    cvController.selected.add(message);
                  }
                } : kIsDesktop || kIsWeb || iOS || material ? () => tapped.value = !tapped.value : null,
                child: IgnorePointer(
                  ignoring: cvController.inSelectMode.value,
                  child: Container(
                    width: double.infinity,
                    alignment: message.isFromMe! ? Alignment.centerRight : Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Samsung timestamp (left side)
                        if (samsung)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: MessageTimestamp(
                              controller: parentController, 
                              cvController: cvController
                            ),
                          ),
                        
                        // The actual collage content
                        _buildCollageStack(context),
                        
                        // Swipe to reply indicator
                        if (canSwipeToReply)
                          Obx(() => SlideToReply(
                            width: replyOffset.value.abs(), 
                            isFromMe: message.isFromMe!
                          )),
                      ].conditionalReverse(message.isFromMe!),
                    ),
                  ),
                ),
              )),
            ),
          ],
        ),
        
        // Message properties for all parts in the group
        ...partGroup.parts.map((part) => Padding(
          padding: showAvatar || ss.settings.alwaysShowAvatars.value
              ? EdgeInsets.only(left: 35.0 * ss.settings.avatarScale.value) 
              : EdgeInsets.zero,
          child: MessageProperties(
            parentController: parentController,
            part: part
          ),
        )),
      ],
    );
  }
  
  Widget _buildCollageStack(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Base: Measured column to get total height
        Opacity(
          opacity: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: partGroup.parts.map((part) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0), // Your overlap amount
                child: AttachmentHolder(
                  parentController: parentController,
                  message: part,
                ),
              );
            }).toList(),
          ),
        ),
        
        // Actual positioned attachments with overlap
        ...partGroup.parts.asMap().entries.map((entry) {
          final index = entry.key;
          final part = entry.value;
          final reactions = reactionsForPart(part.part);
          final stickers = stickersForPart(part.part);
          
          return Positioned(
            top: index * 60.0, // Adjust overlap amount here
            left: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onHorizontalDragUpdate: !canSwipeToReply ? null : (details) {
                if (ReplyScope.maybeOf(context) != null) return;
                replyOffset.value += details.delta.dx * 0.5;
                if (message.isFromMe!) {
                  replyOffset.value = replyOffset.value.clamp(-double.infinity, 0);
                } else {
                  replyOffset.value = replyOffset.value.clamp(0, double.infinity);
                }
                if (!gaveHapticFeedback && replyOffset.value.abs() >= SlideToReply.replyThreshold) {
                  HapticFeedback.lightImpact();
                  gaveHapticFeedback = true;
                } else if (replyOffset.value.abs() < SlideToReply.replyThreshold) {
                  gaveHapticFeedback = false;
                }
              },
              onHorizontalDragEnd: !canSwipeToReply ? null : (details) {
                if (ReplyScope.maybeOf(context) != null) return;
                if (replyOffset.value.abs() >= SlideToReply.replyThreshold) {
                  cvController.replyToMessage = Tuple2(message, index);
                }
                replyOffset.value = 0;
              },
              onHorizontalDragCancel: !canSwipeToReply ? null : () {
                if (ReplyScope.maybeOf(context) != null) return;
                replyOffset.value = 0;
              },
              child: MessagePopupHolder(
                key: keys[index],
                controller: parentController,
                cvController: cvController,
                part: part,
                isEditing: false,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // No TailClipper for collages!
                    BubbleEffects(
                      message: message,
                      part: index,
                      globalKey: keys[index],
                      showTail: false, // Never show tail in collages
                      child: AttachmentHolder(
                        parentController: parentController,
                        message: part,
                      ),
                    ),
                    
                    // Stickers
                    if (stickers.isNotEmpty)
                      StickerHolder(
                        stickerMessages: stickers,
                        controller: cvController,
                      ),
                    
                    // Reactions
                    if (message.isFromMe!)
                      Positioned(
                        top: -14,
                        left: -20,
                        child: ReactionHolder(
                          reactions: reactions,
                          message: message,
                        ),
                      ),
                    if (!message.isFromMe!)
                      Positioned(
                        top: -14,
                        right: -20,
                        child: ReactionHolder(
                          reactions: reactions,
                          message: message,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// Stack/Grid Widget - renders 4+ visual media attachments
class StackGridWidget extends StatelessWidget {
  final PartGroup partGroup;
  final MessageWidgetController parentController;
  final ConversationViewController cvController;
  final Message message;
  final bool showAvatar;
  final Message? newerMessage;
  
  @override
  Widget build(BuildContext context) {
    final isLastElement = /* check if this is last in messageElements */;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: message.isFromMe! ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            // Avatar at bottom if this is the last element
            if (isLastElement && 
                message.showTail(newerMessage) && 
                (showAvatar || ss.settings.alwaysShowAvatars.value) &&
                !message.isFromMe! && 
                !message.isGroupEvent)
              Padding(
                padding: const EdgeInsets.only(left: 5.0),
                child: ContactAvatarWidget(
                  handle: message.handle,
                  size: iOS ? 30 : 35,
                  fontSize: context.theme.textTheme.bodyLarge!.fontSize!,
                  borderThickness: 0.1,
                ),
              ),
            
            Padding(
              padding: (showAvatar || ss.settings.alwaysShowAvatars.value)
                  ? EdgeInsets.only(left: 35.0 * ss.settings.avatarScale.value) 
                  : EdgeInsets.zero,
              child: Obx(() => GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: cvController.inSelectMode.value ? () {
                  if (cvController.isSelected(message.guid!)) {
                    cvController.selected.remove(message);
                  } else {
                    cvController.selected.add(message);
                  }
                } : null, // No tap for stack (no popover)
                child: IgnorePointer(
                  ignoring: cvController.inSelectMode.value,
                  child: Container(
                    width: double.infinity,
                    alignment: message.isFromMe! ? Alignment.centerRight : Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Grid placeholder for now
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            color: context.theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                            itemCount: partGroup.parts.length,
                            itemBuilder: (context, index) {
                              return AttachmentHolder(
                                parentController: parentController,
                                message: partGroup.parts[index],
                              );
                            },
                          ),
                        ),
                      ].conditionalReverse(message.isFromMe!),
                    ),
                  ),
                ),
              )),
            ),
          ],
        ),
        
        // Message properties
        ...partGroup.parts.map((part) => Padding(
          padding: showAvatar || ss.settings.alwaysShowAvatars.value
              ? EdgeInsets.only(left: 35.0 * ss.settings.avatarScale.value) 
              : EdgeInsets.zero,
          child: MessageProperties(
            parentController: parentController,
            part: part
          ),
        )),
      ],
    );
  }
}