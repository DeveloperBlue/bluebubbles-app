import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/components/bb_chip.dart';
import 'package:bluebubbles/app/layouts/conversation_details/attachment_section_type.dart';
import 'package:bluebubbles/app/layouts/conversation_details/dialogs/timeframe_picker.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

typedef AttachmentFiltersChanged = void Function(AttachmentFiltersState filters);

/// Opens the shared attachment filters bottom sheet.
void showAttachmentFiltersSheet(
  BuildContext pageContext, {
  required Chat chat,
  required AttachmentFiltersState filters,
  required AttachmentFiltersChanged onChanged,
  AttachmentFiltersTypeSection typeSection = AttachmentFiltersTypeSection.media,
}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet<void>(
    context: pageContext,
    backgroundColor: pageContext.theme.colorScheme.surfaceContainerHighest,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) {
      var currentFilters = filters;

      return StatefulBuilder(
        builder: (context, setSheetState) {
          final labelStyle = TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: Theme.of(context).colorScheme.onSurface,
          );
          final sectionLabelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              );
          final primaryColor = Theme.of(context).colorScheme.primary;

          void updateFilters({
            MediaFilter? type,
            PhotoSubfilter? photoSubfilter,
            FileTypeFilter? fileType,
            MediaSenderFilter? sender,
            DateTime? date,
            bool clearDate = false,
            bool? bookmarkedOnly,
          }) {
            final nextType = type ?? currentFilters.mediaFilter;
            currentFilters = currentFilters.copyWith(
              mediaFilter: type,
              photoSubfilter: nextType != MediaFilter.images ? PhotoSubfilter.all : photoSubfilter,
              fileTypeFilter: fileType,
              senderFilter: sender,
              sinceDate: date,
              clearSinceDate: clearDate,
              bookmarkedOnly: bookmarkedOnly,
            );
            onChanged(currentFilters);
            setSheetState(() {});
          }

          void resetFilters() {
            currentFilters = const AttachmentFiltersState();
            onChanged(currentFilters);
            setSheetState(() {});
          }

          Widget sectionLabel(String label) => Padding(
                padding: const EdgeInsets.only(top: 16, left: 10),
                child: Text(label, style: sectionLabelStyle),
              );

          Widget chipWrap(List<Widget> chips) => Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, left: 10, right: 10),
                  child: Wrap(spacing: 6, runSpacing: 6, children: chips),
                ),
              );

          Widget filterChip(String label, bool selected, ValueChanged<bool> onSelected) {
            return BBChip(
              showCheckmark: true,
              selected: selected,
              checkmarkColor: primaryColor,
              label: Text(label, style: labelStyle),
              onSelected: onSelected,
            );
          }

          final showFromYou = currentFilters.senderFilter.kind != MediaSenderFilterKind.fromOthers &&
              currentFilters.senderFilter.kind != MediaSenderFilterKind.participant;
          final showFromOthers = chat.isGroup &&
              currentFilters.senderFilter.kind != MediaSenderFilterKind.fromYou &&
              currentFilters.senderFilter.kind != MediaSenderFilterKind.participant;
          final showParticipants = currentFilters.senderFilter.kind != MediaSenderFilterKind.fromYou &&
              currentFilters.senderFilter.kind != MediaSenderFilterKind.fromOthers;

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
            padding: const EdgeInsets.only(left: 10, right: 10, bottom: 36, top: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: "Reset Filters",
                        icon: Icon(SettingsSvc.settings.skin.value == Skins.iOS
                            ? CupertinoIcons.restart
                            : Icons.restore),
                        onPressed: currentFilters.hasActiveFilter(typeSection) ? resetFilters : null,
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            "Filters",
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: currentFilters.bookmarkedOnly ? "Show All" : "Bookmarked Only",
                        isSelected: currentFilters.bookmarkedOnly,
                        icon: Icon(SettingsSvc.settings.skin.value == Skins.iOS
                            ? CupertinoIcons.bookmark
                            : Icons.bookmark_outline),
                        selectedIcon: Icon(SettingsSvc.settings.skin.value == Skins.iOS
                            ? CupertinoIcons.bookmark_fill
                            : Icons.bookmark),
                        color: currentFilters.bookmarkedOnly ? primaryColor : null,
                        onPressed: () => updateFilters(bookmarkedOnly: !currentFilters.bookmarkedOnly),
                      ),
                    ],
                  ),
                  sectionLabel("Sender"),
                  chipWrap([
                    if (showFromYou)
                      BBChip(
                        showCheckmark: true,
                        selected: currentFilters.senderFilter.kind == MediaSenderFilterKind.fromYou,
                        checkmarkColor: primaryColor,
                        padding: const EdgeInsets.all(4),
                        avatar: const ContactAvatarWidget(
                          handle: null,
                          size: 24,
                          editable: false,
                          scaleSize: false,
                          borderThickness: 0,
                        ),
                        label: Text("From You", style: labelStyle),
                        onSelected: (selected) {
                          updateFilters(
                            sender: selected ? const MediaSenderFilter.fromYou() : const MediaSenderFilter.any(),
                          );
                        },
                      ),
                    if (showFromOthers)
                      BBChip(
                        showCheckmark: true,
                        selected: currentFilters.senderFilter.kind == MediaSenderFilterKind.fromOthers,
                        checkmarkColor: primaryColor,
                        padding: const EdgeInsets.all(4),
                        avatar: const ContactAvatarWidget(
                          handle: null,
                          size: 24,
                          editable: false,
                          scaleSize: false,
                          borderThickness: 0,
                          useGroupIcon: true,
                        ),
                        label: Text("From Others", style: labelStyle),
                        onSelected: (selected) {
                          updateFilters(
                            sender: selected ? const MediaSenderFilter.fromOthers() : const MediaSenderFilter.any(),
                          );
                        },
                      ),
                    if (showParticipants)
                      for (final handle in chat.handles)
                        if (currentFilters.senderFilter.kind != MediaSenderFilterKind.participant ||
                            currentFilters.senderFilter.participant?.address == handle.address)
                          _ParticipantSenderChip(
                            handle: handle,
                            labelStyle: labelStyle,
                            primaryColor: primaryColor,
                            selected: currentFilters.senderFilter.kind == MediaSenderFilterKind.participant &&
                                currentFilters.senderFilter.participant?.address == handle.address,
                            onSelected: (selected) {
                              updateFilters(
                                sender: selected
                                    ? MediaSenderFilter.participant(handle)
                                    : const MediaSenderFilter.any(),
                              );
                            },
                          ),
                  ]),
                  if (typeSection == AttachmentFiltersTypeSection.media) ...[
                    sectionLabel("Type"),
                    chipWrap([
                      if (currentFilters.mediaFilter != MediaFilter.videos)
                        filterChip(
                          MediaFilter.images.label,
                          currentFilters.mediaFilter == MediaFilter.images,
                          (selected) => updateFilters(type: selected ? MediaFilter.images : MediaFilter.all),
                        ),
                      if (currentFilters.mediaFilter != MediaFilter.images)
                        filterChip(
                          "Videos",
                          currentFilters.mediaFilter == MediaFilter.videos,
                          (selected) => updateFilters(type: selected ? MediaFilter.videos : MediaFilter.all),
                        ),
                    ]),
                    if (currentFilters.mediaFilter == MediaFilter.images)
                      chipWrap([
                        if (currentFilters.photoSubfilter != PhotoSubfilter.gifs)
                          filterChip(
                            PhotoSubfilter.livePhotos.label,
                            currentFilters.photoSubfilter == PhotoSubfilter.livePhotos,
                            (selected) => updateFilters(
                              photoSubfilter: selected ? PhotoSubfilter.livePhotos : PhotoSubfilter.all,
                            ),
                          ),
                        if (currentFilters.photoSubfilter != PhotoSubfilter.livePhotos)
                          filterChip(
                            PhotoSubfilter.gifs.label,
                            currentFilters.photoSubfilter == PhotoSubfilter.gifs,
                            (selected) => updateFilters(
                              photoSubfilter: selected ? PhotoSubfilter.gifs : PhotoSubfilter.all,
                            ),
                          ),
                      ]),
                  ],
                  if (typeSection == AttachmentFiltersTypeSection.files) ...[
                    sectionLabel("Types"),
                    chipWrap([
                      if (currentFilters.fileTypeFilter != FileTypeFilter.audio &&
                          currentFilters.fileTypeFilter != FileTypeFilter.other)
                        filterChip(
                          "Documents",
                          currentFilters.fileTypeFilter == FileTypeFilter.documents,
                          (selected) =>
                              updateFilters(fileType: selected ? FileTypeFilter.documents : FileTypeFilter.all),
                        ),
                      if (currentFilters.fileTypeFilter != FileTypeFilter.documents &&
                          currentFilters.fileTypeFilter != FileTypeFilter.other)
                        filterChip(
                          "Audio",
                          currentFilters.fileTypeFilter == FileTypeFilter.audio,
                          (selected) => updateFilters(fileType: selected ? FileTypeFilter.audio : FileTypeFilter.all),
                        ),
                      if (currentFilters.fileTypeFilter != FileTypeFilter.documents &&
                          currentFilters.fileTypeFilter != FileTypeFilter.audio)
                        filterChip(
                          "Other",
                          currentFilters.fileTypeFilter == FileTypeFilter.other,
                          (selected) => updateFilters(fileType: selected ? FileTypeFilter.other : FileTypeFilter.all),
                        ),
                    ]),
                  ],
                  sectionLabel("Date"),
                  chipWrap([
                    BBChip(
                      padding: const EdgeInsets.all(4),
                      avatar: CircleAvatar(
                        radius: 12,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(
                          Icons.calendar_today_outlined,
                          color: primaryColor,
                          size: 14,
                        ),
                      ),
                      label: currentFilters.sinceDate != null
                          ? Text(
                              "Since ${buildFullDate(currentFilters.sinceDate!, includeTime: currentFilters.sinceDate!.isToday(), useTodayYesterday: true)}",
                              style: labelStyle,
                              overflow: TextOverflow.ellipsis,
                            )
                          : Text("Filter by Date", style: labelStyle),
                      onDeleted: currentFilters.sinceDate == null ? null : () => updateFilters(clearDate: true),
                      onPressed: () async {
                        final picked = await showTimeframePicker(
                          "Since When?",
                          context,
                          customTimeframes: {
                            "1 Hour": 1,
                            "1 Day": 24,
                            "1 Week": 168,
                            "1 Month": 720,
                            "6 Months": 4320,
                            "1 Year": 8760,
                          },
                          selectionSuffix: "Ago",
                          useTodayYesterday: true,
                        );
                        if (picked != null) {
                          updateFilters(date: picked);
                        }
                      },
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _ParticipantSenderChip extends StatelessWidget {
  final Handle handle;
  final TextStyle labelStyle;
  final Color primaryColor;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _ParticipantSenderChip({
    required this.handle,
    required this.labelStyle,
    required this.primaryColor,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final handleState = HandleSvc.getOrCreateHandleState(handle);

    return Obx(() {
      final displayName = handleState.displayName.value ?? handle.address;
      return BBChip(
        showCheckmark: true,
        selected: selected,
        checkmarkColor: primaryColor,
        padding: const EdgeInsets.all(4),
        avatar: ContactAvatarWidget(
          handle: handle,
          size: 24,
          editable: false,
          scaleSize: false,
          borderThickness: 0,
        ),
        label: Text(displayName, style: labelStyle),
        onSelected: onSelected,
      );
    });
  }
}

/// Filter button with badge, matching the search filters trigger.
class AttachmentFiltersButton extends StatelessWidget {
  /// Trailing inset of the tune icon within the 48px [IconButton] touch target.
  static const double _iconTrailingInset = 12;

  final AttachmentFiltersState filters;
  final AttachmentFiltersTypeSection typeSection;
  final Color? iconColor;
  final VoidCallback onPressed;

  const AttachmentFiltersButton({
    super.key,
    required this.filters,
    required this.typeSection,
    required this.onPressed,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final hasActiveFilter = filters.hasActiveFilter(typeSection);
    final color = iconColor ?? Theme.of(context).colorScheme.primary;
    final horizontalPadding = attachmentSectionHorizontalPadding().toDouble();
    final rightMargin = (horizontalPadding - _iconTrailingInset).clamp(0.0, double.infinity);

    return Padding(
      padding: EdgeInsets.only(right: rightMargin),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (hasActiveFilter)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            IconButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                onPressed();
              },
              icon: Icon(Icons.tune, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
