import 'dart:async';
import 'dart:math' as math;

import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/models/models.dart' show HandleLookupKey;
import 'package:flutter/foundation.dart';

/// A Find My friend's matching chat [Handle] and/or address-book [ContactV2].
/// Used by the list, map markers, and popups for name and avatar.
class FindMyFriendIdentity {
  const FindMyFriendIdentity({this.handle, this.contact});

  final Handle? handle;
  final ContactV2? contact;

  /// Contact name, then handle name, then the formatted Find My address.
  String displayName(FindMyFriend friend) {
    if (contact != null && !isNullOrEmpty(contact!.computedDisplayName)) {
      return contact!.computedDisplayName;
    }
    if (handle != null) return handle!.displayName;
    final raw = friend.handleAddress ?? friend.title;
    if (isNullOrEmpty(raw)) return 'Unknown Friend';
    return raw!.contains('@') ? raw : formatPhoneNumber(raw);
  }
}

/// Resolves a Find My friend to a [Handle] and/or [ContactV2], and matches
/// friends to chat participants when they use different identifiers
/// (e.g. iCloud email in Find My vs phone in chat).
///
/// Identity lookup (names/avatars):
/// 1. Look up a [Handle] with this exact address
/// 2. Otherwise look up a [ContactV2] that lists this email or phone.
/// 3. If that contact has a handle already linked to a 1:1 chat, use that
///    handle instead. Otherwise fall back to any other handle on the contact.
///
/// Participant matching is intentionally conservative — only deterministic
/// identity signals: handle IDs, address equality (normalized), shared
/// [ContactV2] records, and contact phone/email entries. Display names are
/// never compared.
///
/// [resolveFriendHandle] memoizes ObjectBox lookups for the process lifetime:
/// positives are sticky; nulls use an exponential TTL backoff.
/// The email/phone → contact index is also process-lifetime; contact sync
/// calls [clearContactIndex], which emits [indexCleared] so Find My can refresh.
class FindMyHandleMatcher {
  FindMyHandleMatcher._();

  static const Duration _nullTtlBase = Duration(seconds: 2);
  static const int _nullTtlFactor = 2;
  static const Duration _nullTtlCap = Duration(minutes: 10);

  static Map<String, ContactV2>? _index;
  static final _indexCleared = StreamController<void>.broadcast(sync: true);
  static final Map<String, _ResolveCacheEntry> _resolveCache = <String, _ResolveCacheEntry>{};

  /// Broadcast after [clearContactIndex] so Find My can rebuild names/avatars.
  static Stream<void> get indexCleared => _indexCleared.stream;

  /// Drops cached lookups and emits [indexCleared]. Called after contact sync.
  static void clearContactIndex() {
    _index = null;
    _resolveCache.clear();
    _indexCleared.add(null);
  }

  /// Returns the [Handle] and/or [ContactV2] for [friend], following the class lookup order.
  static FindMyFriendIdentity resolveIdentity(FindMyFriend friend) {
    final handle = resolveFriendHandle(friend);
    if (handle != null) return FindMyFriendIdentity(handle: handle);

    final contact = _findContact(friend);
    if (contact == null) return const FindMyFriendIdentity();
    return FindMyFriendIdentity(handle: _linkedHandle(contact, friend), contact: contact);
  }

  static bool matchesAny(FindMyFriend friend, List<Handle> handles) =>
      handles.any((handle) => matchesFriend(friend, handle));

  static bool matchesFriend(FindMyFriend friend, Handle handle) {
    final resolvedFriendHandle = resolveFriendHandle(friend);

    if (friend.handle != null) {
      if (friend.handle!.id != null && handle.id != null && friend.handle!.id == handle.id) return true;
      if (friend.handle!.uniqueAddressAndService == handle.uniqueAddressAndService) return true;
      if (_handlesShareContact(friend.handle!, handle)) return true;
    }

    if (resolvedFriendHandle != null && _handlesShareContact(resolvedFriendHandle, handle)) return true;

    for (final participantId in _handleIdentifiers(handle)) {
      for (final friendId in _friendIdentifiers(friend)) {
        if (_identifiersMatch(participantId, friendId)) return true;
      }
    }

    for (final contact in handle.contactsV2) {
      for (final friendId in _friendIdentifiers(friend)) {
        if (_contactMatchesIdentifier(contact, friendId)) return true;
      }
    }

    return false;
  }

  static bool friendIdentifiersMatch(FindMyFriend a, FindMyFriend b) {
    if (a.stableId != null && b.stableId != null && a.stableId == b.stableId) return true;
    for (final aId in friendIdentifiers(a)) {
      for (final bId in friendIdentifiers(b)) {
        if (identifiersMatch(aId, bId)) return true;
      }
    }
    return false;
  }

  static Set<String> friendIdentifiers(FindMyFriend friend) => _friendIdentifiers(friend);

  static bool identifiersMatch(String a, String b) => _identifiersMatch(a, b);

  /// Resolves a friend without a hydrated [FindMyFriend.handle] via local DB lookup.
  /// Results are cached: positives stick; nulls back off with an increasing TTL.
  static Handle? resolveFriendHandle(FindMyFriend friend) {
    if (friend.handle != null) return friend.handle;

    final key = _cacheKey(friend);
    if (key != null) {
      final cached = _resolveCache[key];
      if (cached != null) {
        if (cached.handle != null) return cached.handle;
        final expiresAt = cached.expiresAt;
        if (expiresAt != null && DateTime.now().isBefore(expiresAt)) return null;
      }
    }

    final resolved = _findHandle(friend);

    if (key == null) return resolved;

    if (resolved != null) {
      _resolveCache[key] = _ResolveCacheEntry(handle: resolved);
      return resolved;
    }

    final previousFails = _resolveCache[key]?.failCount ?? 0;
    final failCount = previousFails + 1;
    final ttlMs = math.min(
      _nullTtlCap.inMilliseconds,
      _nullTtlBase.inMilliseconds * math.pow(_nullTtlFactor, failCount - 1).toInt(),
    );
    _resolveCache[key] = _ResolveCacheEntry(
      handle: null,
      failCount: failCount,
      expiresAt: DateTime.now().add(Duration(milliseconds: ttlMs)),
    );
    return null;
  }

  static String? _cacheKey(FindMyFriend friend) {
    final key = friend.stableId ?? friend.handleAddress ?? friend.title;
    if (key == null || key.isEmpty) return null;
    return key;
  }

  /// Exact iMessage, then SMS, handle for any address on [friend].
  static Handle? _findHandle(FindMyFriend friend) {
    for (final addr in _addresses(friend)) {
      final iMessage = Handle.findOne(addressAndService: HandleLookupKey(addr, 'iMessage'));
      if (iMessage != null) return iMessage;
      final sms = Handle.findOne(addressAndService: HandleLookupKey(addr, 'SMS'));
      if (sms != null) return sms;
    }
    return null;
  }

  /// Contact whose indexed emails/phones include an address on [friend].
  static ContactV2? _findContact(FindMyFriend friend) {
    final index = _contactIndex();
    if (index == null) return null;
    for (final addr in _addresses(friend)) {
      if (addr.contains('@')) {
        final hit = index[ContactV2.normalizeEmail(addr)];
        if (hit != null) return hit;
      } else {
        for (final key in getPhoneNumberVariants(addr)) {
          final hit = index[key];
          if (hit != null) return hit;
        }
      }
    }
    return null;
  }

  /// Distinct addresses from [FindMyFriend.handleAddress] and [FindMyFriend.title].
  /// Truncates at `/` — some Find My payloads use `address/suffix`.
  static Iterable<String> _addresses(FindMyFriend friend) {
    return {friend.handleAddress, friend.title}
        .whereType<String>()
        .map((value) {
          final trimmed = value.trim();
          return trimmed.contains('/') ? trimmed.split('/').first : trimmed;
        })
        .where((addr) => addr.isNotEmpty);
  }

  /// Lazy map of normalized contact email/phone → [ContactV2]. Null on web.
  static Map<String, ContactV2>? _contactIndex() {
    if (kIsWeb) return null;
    if (_index != null) return _index;

    final index = <String, ContactV2>{};
    for (final contact in Database.contactsV2.getAll()) {
      for (final address in contact.addresses) {
        if (address.contains('@')) {
          final email = ContactV2.normalizeEmail(address);
          if (email.isNotEmpty) index[email] = contact;
        } else {
          for (final key in getPhoneNumberVariants(address)) {
            if (key.isNotEmpty) index[key] = contact;
          }
        }
      }
    }
    return _index = index;
  }

  /// Best [Handle] already linked to [contact] after a contact-only match.
  /// Skips [friend]'s Find My address; prefers a 1:1 iMessage chat, then SMS, then any other.
  static Handle? _linkedHandle(ContactV2 contact, FindMyFriend friend) {
    final skip = {
      for (final addr in _addresses(friend)) _normalizeAddress(addr),
    };

    Handle? inChatIMessage;
    Handle? inChatSms;
    Handle? anyIMessage;
    Handle? anySms;
    for (final handle in contact.handles) {
      if (skip.contains(_normalizeAddress(handle.address))) continue;
      final used = _usedInDirectChat(handle);
      if (handle.service == 'iMessage') {
        if (used) {
          inChatIMessage ??= handle;
        } else {
          anyIMessage ??= handle;
        }
      } else if (used) {
        inChatSms ??= handle;
      } else {
        anySms ??= handle;
      }
    }
    return inChatIMessage ?? inChatSms ?? anyIMessage ?? anySms;
  }

  static String _normalizeAddress(String address) {
    return address.contains('@') ? ContactV2.normalizeEmail(address) : ContactV2.normalizePhoneNumber(address);
  }

  /// Whether [handle] appears in a 1:1 chat guid (`service;-;address`). Group chats are ignored.
  static bool _usedInDirectChat(Handle handle) {
    if (kIsWeb || handle.address.isEmpty) return false;
    final query = Database.chats.query(Chat_.guid.contains(';-;${handle.address}')).build();
    query.limit = 1;
    final found = query.findFirst() != null;
    query.close();
    return found;
  }

  static bool _handlesShareContact(Handle a, Handle b) {
    for (final ca in a.contactsV2) {
      for (final cb in b.contactsV2) {
        if (ca.id == cb.id) return true;
      }
    }
    return false;
  }

  static Set<String> _handleIdentifiers(Handle handle) {
    final ids = <String>{
      handle.uniqueAddressAndService,
      handle.address,
      if (handle.formattedAddress != null) handle.formattedAddress!,
    };
    if (handle.uniqueAddressAndService.contains('/')) {
      ids.add(handle.uniqueAddressAndService.split('/').first);
    }
    return ids;
  }

  static Set<String> _friendIdentifiers(FindMyFriend friend) {
    final ids = <String>{};
    if (friend.stableId != null) ids.add(friend.stableId!);
    if (friend.handleAddress != null) ids.add(friend.handleAddress!);
    if (friend.handle != null) {
      ids.add(friend.handle!.address);
      ids.add(friend.handle!.uniqueAddressAndService);
    }
    if (friend.subtitle != null && _looksLikeAddress(friend.subtitle!)) {
      ids.add(friend.subtitle!);
    }
    if (friend.title != null && _looksLikeAddress(friend.title!)) {
      ids.add(friend.title!);
    }
    return ids;
  }

  /// True when [value] is an email or phone-like string, not a display name.
  static bool _looksLikeAddress(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains('@')) return true;
    final digits = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    return digits.length >= 7;
  }

  static bool _identifiersMatch(String a, String b) {
    if (a == b) return true;

    final aIsEmail = a.contains('@');
    final bIsEmail = b.contains('@');
    if (aIsEmail != bIsEmail) return false;

    if (aIsEmail) {
      return ContactV2.normalizeEmail(a) == ContactV2.normalizeEmail(b);
    }

    final na = ContactV2.normalizePhoneNumber(a);
    final nb = ContactV2.normalizePhoneNumber(b);
    return na.isNotEmpty && na == nb;
  }

  static bool _contactMatchesIdentifier(ContactV2 contact, String identifier) {
    if (contact.hasMatchingAddress(identifier)) return true;
    for (final phone in contact.phoneNumbers) {
      if (_identifiersMatch(phone.number, identifier)) return true;
    }
    for (final email in contact.emailAddresses) {
      if (_identifiersMatch(email.address, identifier)) return true;
    }
    return false;
  }
}

class _ResolveCacheEntry {
  _ResolveCacheEntry({
    required this.handle,
    this.failCount = 0,
    this.expiresAt,
  });

  final Handle? handle;
  final int failCount;
  final DateTime? expiresAt;
}
