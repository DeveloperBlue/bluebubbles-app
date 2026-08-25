# conversation_details/widgets/ — Detail Panel Sub-Widgets

Reusable widgets composing the conversation details / info panel.

## Root widgets

| File | Purpose |
|------|---------|
| `chat_info.dart` | **iOS-only.** Top section: avatar, name, participant count, edit name button. Material/Samsung use `../material/material_chat_header.dart` instead — routed from `conversation_details.dart` by skin |
| `chat_options.dart` | **iOS-only.** Action row: mute, pin, archive, block, delete. Material/Samsung use `../material/material_chat_options.dart` instead |
| `contact_tile.dart` | Single participant row (avatar, name, address, remove button) — shared by both skins |
| `participants_list.dart` | **iOS-only.** Scrollable list of `ContactTile`s for group chats. Material/Samsung use `../material/material_participants_section.dart` instead |
| `attachment_section_header.dart` | Section label + "Show more" for attachment previews |
| `attachments_loader.dart` | Loads shared attachments for media/docs/locations |
| `media_gallery_card.dart` | Tappable thumbnail card for media or file items |
| `details_message_popup_binder.dart` | Long-press / right-click wrapper that opens the message popup for a details tile |

All four widgets in `sections/` plus `attachment_section_header.dart` and `media_gallery_card.dart`
take an `expressive` flag (default `false`), threaded from `conversation_details.dart` /
`conversation_attachments.dart` by `SettingsSvc.settings.skin.value != Skins.iOS`. On expressive:
sentence-case headers via `M3ESectionHeader`, `M3EShapes.lg` card corners tonally derived from
`context.tileColor` (never a raw `colorScheme.surfaceContainer*` read), sections hide entirely
(`AnimatedSize` + `M3EMotion.spatialFast`) instead of rendering an empty placeholder once loading
finishes, and the media grid column count follows the Material window size class instead of
`max(2, width ~/ 200)`.

## `filters/`

| File | Purpose |
|------|---------|
| `media_filters_sheet.dart` | Shared attachment filters bottom sheet + app bar tune button |

## `sections/`

| Path | Purpose |
|------|---------|
| `media/media_grid_section.dart` | Photo/video grid (preview + full page). Long-press opens the message popup; Select Multiple starts GUID selection |
| `media/media_filter_selector.dart` | Inline All/Images/Videos segmented control |
| `links/links_section.dart` | Shared URL link previews. Long-press opens the message popup |
| `links/links_search_helper.dart` | Link search scoring and sort |
| `documents/documents_section.dart` | Shared files/documents grid. Long-press opens the message popup |
| `documents/documents_search_helper.dart` | File search scoring and sort |
| `locations/locations_section.dart` | Shared location message cards. Long-press opens the message popup |

Long-press / right-click on media, files, links, and locations opens `DetailsMessagePopupBinder` → `showMessagePopup` (`MessagePopupOrigin.details`, no tapbacks). Tap still opens/launches the item. Media GUID selection is unchanged: while active, tap toggles selection instead. Select Multiple is hidden for files, links, and locations.

## Related
- Parent panel: `../CLAUDE.md` (conversation_details)
- Dialogs (add participant, leave chat, etc.): `../dialogs/CLAUDE.md`
- Contact avatar: `lib/app/components/avatars/CLAUDE.md`
