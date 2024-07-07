import 'package:xmpp_stone/src/data/Jid.dart';

class XmppAccountSettings {
  String name;
  String? username;
  String? domain;
  String? resource = '';
  String password;
  String? host;
  String? mucDomain = '';
  String? customScheme;
  String? publicKey;
  String? privateKey;
  int port;
  int? totalReconnections;
  int? reconnectionTimeout;
  int? responseTimeoutMs;
  int? writeQueueMs;
  bool ackEnabled = true;
  String? wsPath;
  List<String>? wsProtocols;

  XmppAccountSettings(
    this.name,
    this.username,
    this.domain,
    this.password,
    this.port, {
    this.host,
    this.resource,
    this.mucDomain,
    this.wsPath,
    this.wsProtocols,
    this.customScheme,
    this.publicKey,
    this.privateKey,
    this.totalReconnections,
    this.reconnectionTimeout,
    this.responseTimeoutMs,
    this.writeQueueMs
  });

  Jid get fullJid => Jid(username, domain, resource);

  static XmppAccountSettings fromJid(String jid, String password) {
    var fullJid = Jid.fromFullJid(jid);
    return XmppAccountSettings(
        jid, fullJid.local, fullJid.domain, password, 5222);
  }
}
