import 'package:xmpp_stone/xmpp_stone.dart';

/// Inspired by this XEP-0422: https://xmpp.org/extensions/xep-0422.html

abstract class MarkReadInterface {
  MarkReadInterface addMarkRead(bool isRead);

  XmppElement? getMarkRead();
}