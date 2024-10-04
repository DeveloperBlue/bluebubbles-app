import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/helpers/types/classes/aliases.dart';
import 'package:bluebubbles/services/backend_ui_interop/event_dispatcher.dart';
import 'package:bluebubbles/services/ui/chat/global_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NotificationSettingsDialog extends StatelessWidget {
  NotificationSettingsDialog(this.chatGuid, this.updateParent, {super.key});
  final ChatGuid chatGuid;
  final VoidCallback updateParent;

  @override
  Widget build(BuildContext context) {
    Chat chat = GlobalChatService.getChat(chatGuid)!;
    return AlertDialog(
      title: Text("Chat-Specific Settings", style: context.theme.textTheme.titleLarge),
      content: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Obx(() {
              return ListTile(
                mouseCursor: MouseCursor.defer,
                title: Text(chat.observables.muteType.value == "mute" ? "Unmute" : "Mute",
                    style: context.theme.textTheme.bodyLarge),
                subtitle: Text(
                  "Completely ${chat.observables.muteType.value == "mute" ? "unmute" : "mute"} this chat",
                  style: context.theme.textTheme.bodySmall!.copyWith(color: context.theme.colorScheme.properOnSurface),),
                onTap: () async {
                  Get.back();
                  chat.toggleMuteType(null);
                  updateParent.call();
                  eventDispatcher.emit("refresh", null);
                },
              );
            }),
            Obx(() {
              if (!chat.isGroup) return const SizedBox.shrink();
              return ListTile(
                mouseCursor: MouseCursor.defer,
                title: Text("Mute Individuals", style: context.theme.textTheme.bodyLarge),
                subtitle: Text("Mute certain individuals in this chat",
                  style: context.theme.textTheme.bodySmall!.copyWith(color: context.theme.colorScheme.properOnSurface),),
                onTap: () async {
                  Get.back();
                  List<String?> names = chat.participants
                      .map((e) => e.displayName)
                      .toList();
                  List<String> existing = chat.muteArgs?.split(",") ?? [];
                  showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text("Mute Individuals", style: context.theme.textTheme.titleLarge),
                        backgroundColor: context.theme.colorScheme.properSurface,
                        content: SingleChildScrollView(
                          child: Container(
                            width: double.maxFinite,
                            child: StatefulBuilder(builder: (context, setState) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child:
                                    Text("Select the individuals you would like to mute"),
                                  ),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: context.mediaQuery.size.height * 0.4,
                                    ),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: chat.participants.length,
                                      findChildIndexCallback: (key) => findChildIndexByKey(chat.participants, key, (item) => item.address),
                                      itemBuilder: (context, index) {
                                        return CheckboxListTile(
                                          key: ValueKey(chat.participants[index].address),
                                          value: existing
                                              .contains(chat.participants[index].address),
                                          onChanged: (val) {
                                            setState(() {
                                              if (val!) {
                                                existing.add(chat.participants[index].address);
                                              } else {
                                                existing.removeWhere((element) =>
                                                element == chat.participants[index].address);
                                              }
                                            });
                                          },
                                          activeColor: context.theme.colorScheme.primary,
                                          title: Text(
                                              names[index] ?? chat.participants[index].address,
                                              style: context.theme.textTheme.bodyLarge),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                        actions: [
                          TextButton(
                              child: Text("OK", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                              onPressed: () {
                                if (existing.isEmpty) {
                                  showSnackbar("Error", "Please select at least one person!");
                                  return;
                                }

                                chat.toggleMuteType("mute_individuals", muteArgs: existing.join(","));
                                Get.back();
                                updateParent.call();
                                eventDispatcher.emit("refresh", null);
                              }
                          ),
                        ],
                      )
                  );
                },
              );
            }),
            Obx(() => ListTile(
              mouseCursor: MouseCursor.defer,
              title: Text(
                  chat.observables.muteType.value == "temporary_mute" && shouldMuteDateTime(chat.observables.muteArgs.value)
                      ? "Delete Temporary Mute"
                      : "Temporary Mute",
                  style: context.theme.textTheme.bodyLarge),
              subtitle: Text(
                chat.observables.muteType.value == "temporary_mute" && shouldMuteDateTime(chat.observables.muteArgs.value)
                    ? ""
                    : "Mute this chat temporarily",
                style: context.theme.textTheme.bodySmall!.copyWith(color: context.theme.colorScheme.properOnSurface),),
              onTap: () async {
                Get.back();
                if (shouldMuteDateTime(chat.muteArgs)) {
                  chat.toggleMuteType(null);
                } else {
                  final messageDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().toLocal(),
                      firstDate: DateTime.now().toLocal(),
                      lastDate: DateTime.now().toLocal().add(const Duration(days: 365)));
                  if (messageDate != null) {
                    final messageTime =
                    await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (messageTime != null) {
                      final finalDate = DateTime(messageDate.year, messageDate.month,
                          messageDate.day, messageTime.hour, messageTime.minute);

                      chat.toggleMuteType("temporary_mute", muteArgs: finalDate.toIso8601String());
                      updateParent.call();
                      eventDispatcher.emit("refresh", null);
                    }
                  }
                }
              },
            )),
            ListTile(
              mouseCursor: MouseCursor.defer,
              title: Text("Text Detection", style: context.theme.textTheme.bodyLarge),
              subtitle: Text(
                "Completely mute this chat, except when a message contains certain text",
                style: context.theme.textTheme.bodySmall!.copyWith(color: context.theme.colorScheme.properOnSurface),),
              onTap: () async {
                Get.back();
                final TextEditingController controller = TextEditingController();
                if (chat.muteType == "text_detection") {
                  controller.text = chat.muteArgs!;
                }
                await showDialog(
                  context: context,
                  builder: (context) => TextDetectionDialog(controller)
                );

                chat.toggleMuteType("text_detection", muteArgs: controller.text);
                updateParent.call();
                eventDispatcher.emit("refresh", null);
              },
            ),
            ListTile(
              mouseCursor: MouseCursor.defer,
              title: Text("Reset chat-specific settings",
                  style: context.theme.textTheme.bodyLarge),
              subtitle: Text("Delete your custom settings",
                style: context.theme.textTheme.bodySmall!.copyWith(color: context.theme.colorScheme.properOnSurface),),
              onTap: () async {
                Get.back();
                chat.toggleMuteType(null);
                updateParent.call();
                eventDispatcher.emit("refresh", null);
              },
            ),
          ]),
      backgroundColor: context.theme.colorScheme.properSurface,
    );
  }

  bool shouldMuteDateTime(String? muteArgs) {
    if (muteArgs == null) return false;
    DateTime? time = DateTime.tryParse(muteArgs);
    if (time == null) return false;
    return DateTime.now().toLocal().difference(time).inSeconds.isNegative;
  }
}

class TextDetectionDialog extends StatelessWidget {
  TextDetectionDialog(this.controller, {super.key});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Text detection", style: context.theme.textTheme.titleLarge),
      backgroundColor: context.theme.colorScheme.properSurface,
      content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "Enter any text separated by commas to whitelist notifications for. These are case insensitive.\n\nE.g. 'John,hey guys,homework'\n", style: context.theme.textTheme.bodyLarge,),
            ),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: "Enter text to whitelist...",
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: context.theme.colorScheme.outline,
                    )),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: context.theme.colorScheme.primary,
                    )),
              ),
            ),
          ]),
      actions: [
        TextButton(
            child: Text("OK", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
            onPressed: () {
              if (controller.text.isEmpty) {
                showSnackbar("Error", "Please enter text!");
                return;
              }
              Get.back();
            }
        ),
      ],
    );
  }
}
