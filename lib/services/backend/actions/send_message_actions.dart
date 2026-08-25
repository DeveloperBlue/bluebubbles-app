import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';
import 'package:bluebubbles/services/services.dart';

/// Isolate-dispatchable actions for sending messages via HTTP.
///
/// Each method accepts `Map<String, dynamic>` (as required by [IsolateAction])
/// and returns the decoded server response body so the main isolate can
/// hydrate a [Message] via `Message.fromMap(result['data'])`.
///
class SendMessageActions {
  /// Sends a text message via HTTP.
  static Future<Map<String, dynamic>> sendTextMessage(dynamic data) async {
    final map = data as Map<String, dynamic>;
    final chatGuid = map['chatGuid'] as String;
    final tempGuid = map['tempGuid'] as String;
    final message = map['message'] as String;
    final method = map['method'] as String?;
    final effectId = map['effectId'] as String?;
    final subject = map['subject'] as String?;
    final selectedMessageGuid = map['selectedMessageGuid'] as String?;
    final partIndex = map['partIndex'] as int?;
    final ddScan = map['ddScan'] as bool?;

    final response = await HttpSvc.message.sendText(
      chatGuid,
      tempGuid,
      message,
      method: method,
      effectId: effectId,
      subject: subject,
      selectedMessageGuid: selectedMessageGuid,
      partIndex: partIndex,
      ddScan: ddScan,
    );
    return response.data as Map<String, dynamic>;
  }

  /// Sends a tapback via HTTP.
  static Future<Map<String, dynamic>> sendTapback(dynamic data) async {
    final map = data as Map<String, dynamic>;
    final chatGuid = map['chatGuid'] as String;
    final selectedMessageText = map['selectedMessageText'] as String;
    final selectedMessageGuid = map['selectedMessageGuid'] as String;
    final reaction = map['reaction'] as String;
    final partIndex = map['partIndex'] as int?;

    final response = await HttpSvc.message.sendTapback(
      chatGuid,
      selectedMessageText,
      selectedMessageGuid,
      reaction,
      partIndex: partIndex,
    );
    return response.data as Map<String, dynamic>;
  }

  /// Sends a multipart (mention / mixed-content / attachment) message via HTTP.
  ///
  /// When [data] contains an `attachments` list, each staged file is first
  /// uploaded via `POST /attachment/upload` (progress reported per attachment
  /// through [IsolateEvent.attachmentUploadProgress]), and the returned upload
  /// id is substituted into the matching part's `attachment` field before the
  /// multipart request fires.
  static Future<Map<String, dynamic>> sendMultipartMessage(dynamic data) async {
    final map = data as Map<String, dynamic>;
    final chatGuid = map['chatGuid'] as String;
    final tempGuid = map['tempGuid'] as String;
    final parts = (map['parts'] as List).cast<Map<String, dynamic>>();
    final attachments = (map['attachments'] as List? ?? const []).cast<Map<String, dynamic>>();
    final effectId = map['effectId'] as String?;
    final subject = map['subject'] as String?;
    final selectedMessageGuid = map['selectedMessageGuid'] as String?;
    final partIndex = map['partIndex'] as int?;
    final ddScan = map['ddScan'] as bool?;

    for (final att in attachments) {
      final attachmentGuid = att['tempGuid'] as String;
      final filePath = att['filePath'] as String;
      final fileName = att['fileName'] as String;
      final fileSize = att['fileSize'] as int? ?? 0;

      final uploadResponse = await HttpSvc.attachment.upload(
        PlatformFile(
          name: fileName,
          path: filePath,
          size: fileSize,
        ),
        onSendProgress: (count, total) {
          if (total <= 0) return;
          IsolateEventEmitter.emit(
            IsolateEvent.attachmentUploadProgress,
            {
              'chatGuid': chatGuid,
              'messageGuid': tempGuid,
              'attachmentGuid': attachmentGuid,
              'progress': count / total,
            },
          );
        },
      );

      final uploadData = uploadResponse.data?['data'];
      // Server >= v1.9.8 returns `path`; older servers return `hash`.
      final uploadId = uploadData is Map ? (uploadData['path'] ?? uploadData['hash'])?.toString() : null;
      if (uploadId == null) {
        throw StateError('Attachment upload for $fileName returned no path/hash: ${uploadResponse.data}');
      }

      final part = parts.firstWhere(
        (p) => p['attachmentTempGuid'] == attachmentGuid,
        orElse: () => throw StateError('No multipart part references uploaded attachment $attachmentGuid'),
      );
      part['attachment'] = uploadId;
      part.remove('attachmentTempGuid');
    }

    final response = await HttpSvc.message.sendMultipart(
      chatGuid,
      tempGuid,
      parts,
      effectId: effectId,
      subject: subject,
      selectedMessageGuid: selectedMessageGuid,
      partIndex: partIndex,
      ddScan: ddScan,
    );
    return response.data as Map<String, dynamic>;
  }

  /// Sends an attachment via HTTP.
  ///
  /// Reads the file from [filePath] inside the isolate and constructs
  /// [FormData] locally, avoiding cross-isolate byte transfer.
  static Future<Map<String, dynamic>> sendAttachmentMessage(dynamic data) async {
    final map = data as Map<String, dynamic>;
    final chatGuid = map['chatGuid'] as String;
    final tempGuid = map['tempGuid'] as String;
    final filePath = map['filePath'] as String;
    final fileName = map['fileName'] as String;
    final fileSize = map['fileSize'] as int;
    final method = map['method'] as String?;
    final effectId = map['effectId'] as String?;
    final subject = map['subject'] as String?;
    final selectedMessageGuid = map['selectedMessageGuid'] as String?;
    final partIndex = map['partIndex'] as int?;
    final isAudioMessage = map['isAudioMessage'] as bool? ?? false;

    final response = await HttpSvc.message.sendAttachment(
      chatGuid,
      tempGuid,
      PlatformFile(
        name: fileName,
        path: filePath,
        size: fileSize,
      ),
      method: method,
      effectId: effectId,
      subject: subject,
      selectedMessageGuid: selectedMessageGuid,
      partIndex: partIndex,
      isAudioMessage: isAudioMessage,
      onSendProgress: (count, total) {
        if (total <= 0) return;
        IsolateEventEmitter.emit(
          IsolateEvent.attachmentUploadProgress,
          {
            'chatGuid': chatGuid,
            'messageGuid': tempGuid,
            // Legacy single-attachment sends share one GUID between message
            // and attachment (see send_animation.dart).
            'attachmentGuid': tempGuid,
            'progress': count / total,
          },
        );
      },
    );
    return response.data as Map<String, dynamic>;
  }
}
