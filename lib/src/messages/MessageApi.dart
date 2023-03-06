import 'package:xmpp_stone/src/data/Jid.dart';
import 'package:xmpp_stone/src/elements/encryption/EncryptElement.dart';
import 'package:xmpp_stone/src/elements/stanzas/MessageStanza.dart';
import 'package:xmpp_stone/src/messages/MessageParams.dart';

abstract class MessageApi {
  Future<MessageStanza> sendMessage(Jid to, String text,
      {MessageParams additional});
  Future<MessageStanza> sendSecureMessage(Jid to, EncryptElement encryptElement,
      {MessageParams additional});
  Future<MessageStanza> pinMessage(Jid to, String messageId, bool isPinned,
      {MessageParams additional});
  Future<MessageStanza> quoteMessage(
    Jid to, 
    String messageId,
    String body,
    String quoteText,
    String userId,
    String username,
    String? messageType,
    String? expts,
    {MessageParams additional}
  );

  Future<MessageStanza> recallMessage(Jid jid, 
    List<String> messageId,
    String userId,
      {MessageParams additional});
}