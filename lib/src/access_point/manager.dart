import 'dart:async';
import 'dart:convert';

import 'package:console/console.dart';
import 'package:intl/intl.dart';
import 'package:xmpp_stone/src/access_point/communication_config.dart';
import 'package:xmpp_stone/src/access_point/manager_message_params.dart';
import 'package:xmpp_stone/src/access_point/manager_query_archive_params.dart';
import 'package:xmpp_stone/src/data/Jid.dart';
import 'package:xmpp_stone/src/elements/encryption/EncryptElement.dart';
import 'package:xmpp_stone/src/elements/stanzas/IqStanza.dart';
import 'package:xmpp_stone/src/elements/stanzas/MessageStanza.dart';
import 'package:xmpp_stone/src/elements/stanzas/PresenceStanza.dart';
import 'package:xmpp_stone/src/extensions/advanced_messaging_processing/AmpManager.dart';
import 'package:xmpp_stone/src/extensions/chat_states/ChatStateDecoration.dart';
import 'package:xmpp_stone/src/extensions/last_activity/LastActivityData.dart';
import 'package:xmpp_stone/src/extensions/last_activity/LastActivityManager.dart';
import 'package:xmpp_stone/src/extensions/message_delivery/ReceiptInterface.dart';
import 'package:xmpp_stone/src/extensions/multi_user_chat/MultiUserChatData.dart';
import 'package:xmpp_stone/src/extensions/multi_user_chat/MultiUserChatParams.dart';
import 'package:xmpp_stone/src/extensions/omemo/OMEMOData.dart';
import 'package:xmpp_stone/src/extensions/omemo/OMEMOManager.dart';
import 'package:xmpp_stone/src/extensions/omemo/OMEMOManagerApi.dart';
import 'package:xmpp_stone/src/extensions/ping/PingManager.dart';
import 'package:xmpp_stone/src/extensions/vcard_temp/VCard.dart';
import 'package:xmpp_stone/src/features/message_archive/MessageArchiveData.dart';
import 'package:xmpp_stone/src/features/message_archive/MessageArchiveManager.dart';
import 'package:xmpp_stone/src/logger/Log.dart';
import 'package:xmpp_stone/src/messages/MessageHandler.dart';
import 'package:xmpp_stone/src/messages/MessageParams.dart';
import 'package:xmpp_stone/src/response/BaseResponse.dart';
import 'package:xmpp_stone/src/response/ResponseListener.dart';
import 'package:xmpp_stone/src/roster/RosterManager.dart';
import 'package:xmpp_stone/xmpp_stone.dart' as xmpp;

import 'personal.dart';

final String TAG = 'manager::general';

enum MessageDelivery { UNKNOWN, DIRECT, STORED, ONLINE }

enum ListenerType {
  unknown,
  onReady,
  onLog,
  onPresence,
  onMessage,
  onMessage_Encrypted,
  onMessage_Custom,
  onMessage_Sent,
  onMessage_Delivered_Direct,
  onMessage_Delivered_Stored,
  onMessage_Delivered_Client,
  onMessage_Read_Client,
  onMessage_Carbon,
  onMessage_Delayed,
  onMessage_ChatState,
  onMessage_GroupInvitation, // Protocol
}

class XMPPClientManager {
  String LOG_TAG = 'XMPPClientManager';
  String? host;
  String? mucDomain = '';
  int port = 5222;
  int? responseTimeoutMs;
  int? writeQueueMs;
  int? totalReconnections;
  int? reconnectionTimeout;
  String? customScheme;
  String? wsPath;
  String? resource;
  String? publicKey;
  String? privateKey;
  List<String>? wsProtocols;
  late XMPPClientPersonal personal;
  Function(XMPPClientManager _context)? _onReady;
  Function(String timestamp, String logMessage)? _onLog;
  Function(XMPPMessageParams message, ListenerType listenerType)? _onMessage;
  Function(xmpp.SubscriptionEvent event)? _onPresenceSubscription;
  Function(xmpp.PresenceData event)? _onPresence;
  Function(xmpp.XmppConnectionState state)? _onState;
  Function()? _onPing;
  Function(xmpp.MessageArchiveResult)? _onArchiveRetrieved;
  Function(List<xmpp.Buddy>)? _onRosterList;
  Function(xmpp.BaseResponse)? _responseListener;
  xmpp.Connection? _connection;

  xmpp.Connection? get connection => _connection;
  late MessageHandler _messageHandler;
  late PingManager _pingHandler;
  late MessageArchiveManager _messageArchiveHandler;
  late LastActivityManager _lastActivityManager;
  late OMEMOManagerApi _omemoManager;
  late RosterManager _rosterManager;
  late xmpp.PresenceManager _presenceManager;
  late ConnectionManagerStateChangedListener _connectionStateListener;
  late ConnectionResponseListener _connectionResponseListener;
  late bool _logXmpp;

  StreamSubscription? messageListener;
  StreamSubscription? _rosterList;

  XMPPClientManager(
    jid,
    password, {
    void Function(XMPPClientManager _context)? onReady,
    void Function(String _timestamp, String _message)? onLog,
    void Function(XMPPMessageParams message, ListenerType listenerType)?
        onMessage,
    void Function(xmpp.SubscriptionEvent event)? onPresenceSubscription,
    void Function(xmpp.PresenceData event)? onPresence,
    void Function(xmpp.XmppConnectionState state)? onState,
    void Function()? onPing,
    void Function(xmpp.MessageArchiveResult)? onArchiveRetrieved,
    void Function(List<xmpp.Buddy>)? onRosterList,
    Function(xmpp.BaseResponse)? responseListener,
    String? host,
    int port = 5222,
    String? this.mucDomain,
    String? resource,
    String? wsPath,
    String? customScheme,
    String? publicKey,
    String? privateKey,
    int totalReconnections =3,
    int reconnectionTimeout = 1000,
    int writeQueueMs = 200,
    int responseTimeoutMs = 30000,
    bool logXmpp = false,
    List<String>? wsProtocols,
  }) {
    personal = XMPPClientPersonal(jid, password);
    LOG_TAG = '$LOG_TAG/$jid';
    _onReady = onReady;
    _onLog = onLog;
    _logXmpp = logXmpp;
    _onMessage = onMessage;
    _onPresence = onPresence;
    _onState = onState;
    _onPing = onPing;
    _onArchiveRetrieved = onArchiveRetrieved;
    _onPresenceSubscription = onPresenceSubscription;
    _onRosterList = onRosterList;
    _responseListener = responseListener;
    this.host = host;
    this.port = port;
    this.wsPath = wsPath;
    this.customScheme = customScheme;
    this.wsProtocols = wsProtocols;
    this.resource = resource;
    this.publicKey = publicKey;
    this.privateKey = privateKey;
    this.totalReconnections = totalReconnections;
    this.reconnectionTimeout = reconnectionTimeout;
    this.writeQueueMs = writeQueueMs;
    this.responseTimeoutMs = responseTimeoutMs;
  }

  XMPPClientManager createSession() {
    Log.logLevel = LogLevel.DEBUG;
    Log.logXmpp = _logXmpp;
    var jid = xmpp.Jid.fromFullJid(personal.jid);
    Log.d(LOG_TAG, 'Connecting to $host');
    var account = xmpp.XmppAccountSettings(
      personal.jid,
      jid.local,
      jid.domain,
      personal.password,
      port,
      mucDomain: mucDomain,
      host: host,
      resource: resource ?? jid.resource,
      wsPath: wsPath,
      wsProtocols: wsProtocols,
      customScheme: customScheme,
      publicKey:publicKey,
      privateKey: privateKey,
      totalReconnections: totalReconnections,
      reconnectionTimeout:reconnectionTimeout,
      responseTimeoutMs:responseTimeoutMs,
      writeQueueMs:writeQueueMs,
    );

    _connection = xmpp.Connection(account);
    _connection!.connect();
    _listenConnection();
    onLog('Start connecting');
    return this;
  }

  Future close() async {
    _connection!.forceClose();
    _connectionStateListener.close();
    _connectionResponseListener.close();
  }

  void reconnect() {
    _connection!.reconnectionManager!.handleReconnection(reset: true);
  }

  xmpp.XmppConnectionState getState() {
    return _connection!.state;
  }

  // Initialized managers
  void onReady() {
    onLog('Connected');
    _messageHandler = xmpp.MessageHandler.getInstance(_connection);
    _pingHandler = xmpp.PingManager.getInstance(_connection!);
    _pingHandler.listen(ClientPingListener(onPingReceived: (IqStanza stanza) {
      if (_onPing != null) {
        _onPing!();
      }
    }));
    _messageArchiveHandler = xmpp.MessageArchiveManager.getInstance(_connection!);
    _messageArchiveHandler.listen(
        ClientMAMListener(onResultFinished: (MessageArchiveResult result) {
      if (_onArchiveRetrieved != null) {
        _onArchiveRetrieved!(result);
      }
    }));
    // Last activity - XEP0012
    _lastActivityManager = xmpp.LastActivityManager.getInstance(_connection!);
    // Omemo
    _omemoManager = OMEMOManager.getInstance(_connection!);
    // Roster manager
    _rosterManager = xmpp.RosterManager.getInstance(_connection);
    // Presence Manager
    _presenceManager = xmpp.PresenceManager.getInstance(_connection);

    _rosterList = _rosterManager.rosterStream.listen((rosterList) {
      if (_onRosterList != null) {
        _onRosterList!(rosterList);
      }
    });
    _onReady!(this);
  }

  void onState(xmpp.XmppConnectionState state) {
    if (_onState != null) {
      _onState!(state);
    }
  }

  void onLog(String message) {
    _onLog!(DateFormat('yyyy-MM-dd kk:mm').format(DateTime.now()), message);
    Log.i(LOG_TAG, message);
  }

  // 我的虚拟名片
  Future<VCard> vCardRead() async {
    var vCardManager = xmpp.VCardManager(_connection!);
    final vCard = await vCardManager.getSelfVCard();
    personal.profile = vCard;
    onLog('Your info' + vCard.buildXmlString());
      return vCard;
  }
  //更新虚拟名片
  void vCardUpdate(xmpp.VCard Function(xmpp.VCard vCardToUpdate) _onUpdate) {
    var vCardManager = xmpp.VCardManager(_connection!);
    vCardManager.getSelfVCard().then((vCard) {
      onLog('manager.vCardUpdate::my info ${vCard.buildXmlString()}');
          // Update vcard information
      var _vCardUpdated = _onUpdate(vCard);

      onLog(
          'manager.vCardUpdate::my updated info ${_vCardUpdated.buildXmlString()}');
      vCardManager.updateSelfVCard(_vCardUpdated).then((updatedAckVCard) {
        personal.profile = _vCardUpdated;
        onLog('manager.vCardUpdate::my updated info - Updated info success');
      });
    });
  }

  // 更新出席和状态
  void presenceSend(PresenceShowElement presenceShowElement,
      {String? description}) {
    var presenceData = xmpp.PresenceData(
        presenceShowElement, description, xmpp.Jid.fromFullJid(personal.jid),
        priority: presenceShowElement == PresenceShowElement.chat ? 1 : 0);
    _presenceManager.sendPresence(presenceData);
  }
  //查询用户的出席情况
  Future<PresenceStanza> presenceFrom(receiver) {
    var jid = xmpp.Jid.fromFullJid(receiver);
    return _presenceManager.askDirectPresence(jid);
  }
  //订阅用户的出席情况
  void presenceSubscribe(String receiver) {
    var jid = xmpp.Jid.fromFullJid(receiver);
    _presenceManager.subscribe(jid);
  }
  //拒绝用户订阅我的出席情况
  void presenceReject(String receiver) {
    var jid = xmpp.Jid.fromFullJid(receiver);
    _presenceManager.declineSubscription(jid);
  }
  //接受用户订阅我的出席情况
  void presenceAccept(String receiver) {
    var jid = xmpp.Jid.fromFullJid(receiver);
    _presenceManager.acceptSubscription(jid);
  }

  // 联系人的虚拟名片
  Future<xmpp.VCard> vCardFrom(receiver) {
    var receiverJid = xmpp.Jid.fromFullJid(receiver);
    var vCardManager = xmpp.VCardManager(_connection!);
    return vCardManager.getVCardFor(receiverJid);
  }

  // 我的联系人列表
  Future<List<xmpp.Buddy>> rosterList() {
    var completer = Completer<List<xmpp.Buddy>>();

    StreamSubscription? _rosterList = null;
    _rosterList = _rosterManager.rosterStream.listen((rosterList) {
      completer.complete(rosterList);
      _rosterList!.cancel();
    });
    _rosterManager.queryForRoster().then((result) {});
    return completer.future;
  }

  // 添加联系人
  Future<List<xmpp.Buddy>> rosterAdd(receiver) {
    var completer = Completer<List<xmpp.Buddy>>();
    var receiverJid = xmpp.Jid.fromFullJid(receiver);

    var rosterManager = xmpp.RosterManager.getInstance(_connection);
    rosterManager.addRosterItem(xmpp.Buddy(receiverJid)).then((result) {
      if (result.success) {
        onLog('Add roster successfully');
        // Refresh the list
        rosterList().then((rosterList) {
          completer.complete(rosterList);
        });
      } else {
        onLog('add roster error');
      }
    });
    return completer.future;
  }
  //移除联系人
  Future<List<xmpp.Buddy>> rosterRemove(receiver) {
    var completer = Completer<List<xmpp.Buddy>>();
    var receiverJid = xmpp.Jid.fromFullJid(receiver);

    var rosterManager = xmpp.RosterManager.getInstance(_connection);
    rosterManager.removeRosterItem(xmpp.Buddy(receiverJid)).then((result) {
      if (result.success) {
        onLog('Remove roster successfully');
        // Refresh the list
        rosterList().then((rosterList) {
          completer.complete(rosterList);
        });
      } else {
        onLog('remove roster error');
      }
    });
    return completer.future;
  }

  // 获取群聊消息
  Future<DiscoverRoomResponse> getRoom(String roomName) {
    var mucManager = xmpp.MultiUserChatManager(_connection!);
    var roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? "")) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return mucManager.discoverRoom(roomJid);
  }

  //获取群聊配置
  Future<GetRoomConfigResponse> getReservedRoomConfig(String roomName) {
    var mucManager = xmpp.MultiUserChatManager(_connection!);
    var roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? "")) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return mucManager.requestReservedRoomConfig(roomJid);
  }

  // 设置群聊配置
  Future<SetRoomConfigResponse> setRoomConfig(String roomName,
      GroupChatroomParams config, List<RoomConfigField> roomConfigFields) {
    var mucManager = xmpp.MultiUserChatManager(_connection!);
    var roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? "")) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return mucManager.setRoomConfig(
        roomJid,
        MultiUserChatCreateParams(
            config: config,
            options: XmppCommunicationConfig(shallWaitStanza: false),
            roomConfigFields: roomConfigFields));
  }

  // 创建群聊
  Future<CreateRoomResponse> createInstantRoom(
      String roomName, GroupChatroomParams config) {
    var mucManager = xmpp.MultiUserChatManager(_connection!);
    var roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? "")) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return mucManager.createRoom(roomJid);
  }

  // 加入群聊
  Future<JoinRoomResponse> join(
      String roomName, JoinGroupChatroomParams config) {
    var mucManager = xmpp.MultiUserChatManager(_connection!);
    var roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? "")) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return mucManager.joinRoom(roomJid, config);
  }

  //接受邀请
  Future<AcceptRoomResponse> acceptInvitation(
      String roomName, AcceptGroupChatroomInvitationParams params) {
    var mucManager = xmpp.MultiUserChatManager(_connection!);
    var roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? "")) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return mucManager.acceptRoomInvitation(roomJid, params);
  }

  // 获取群聊成员
  Future<GetUsersResponse> getMembers(String roomName) async {
    var mucManager = xmpp.MultiUserChatManager(_connection!);
    var roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? "")) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }

    return await mucManager.getMembers(roomJid);
  }

  // 获取群聊群主
  Future<GetUsersResponse> getOwners(String roomName) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? "")) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }

    return await mucManager.getOwners(roomJid);
  }

  // 获取群聊管理员
  Future<GetUsersResponse> getAdmins(String roomName) async {
    var mucManager = xmpp.MultiUserChatManager(_connection!);
    var roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? "")) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }

    return await mucManager.getAdmins(roomJid);
  }

  // 邀请成员到群聊
  Future<void> inviteMemberToGroup(
      String roomName, Iterable<String> memberJids) {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }

    mucManager.inviteMembers(roomJid, memberJids);
    return Future.value();
  }

  // 同步添加成员到群聊
  Future<AddUsersResponse> addMembersInGroup(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.ADD,
        userRole: UserRole.member,
        isAsync: false);
    // return await mucManager.addMembers(roomJid,memberJids);
  }
  //异步添加多个成员到群聊
  Future<AddUsersResponse> addMembersInGroupAsync(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.ADD,
        userRole: UserRole.member,
        isAsync: true);
    // return await mucManager.addMembersAsync(roomJid,memberJids);
  }

  // 同步添加群聊管理员
  Future<AddUsersResponse> addAdminsInGroup(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.ADD,
        userRole: UserRole.admin,
        isAsync: false);
    // return await mucManager.addAdmins(roomJid, memberJids);
  }
  // 异步添加群聊管理员
  Future<AddUsersResponse> addAdminsInGroupAsync(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.ADD,
        userRole: UserRole.admin,
        isAsync: true);
    // return await mucManager.addAdminsAsync(roomJid, memberJids);
  }

  // 同步添加群主
  Future<AddUsersResponse> addOwnersInGroup(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.ADD,
        userRole: UserRole.owner,
        isAsync: false);
    // return await mucManager.addAdmins(roomJid, memberJids);
  }
  // 异步添加群主
  Future<AddUsersResponse> addOwnersInGroupAsync(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.ADD,
        userRole: UserRole.owner,
        isAsync: true);
    // return await mucManager.addAdminsAsync(roomJid, memberJids);
  }

  // 同步批量移除成员
  Future<AddUsersResponse> removeMembersInGroup(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.REMOVE,
        userRole: UserRole.member,
        isAsync: false);
    // return await mucManager.addAdminsAsync(roomJid, memberJids);
  }
  // 异步批量移除成员
  Future<AddUsersResponse> removeMembersInGroupAsync(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.REMOVE,
        userRole: UserRole.member,
        isAsync: true);
    // return await mucManager.addAdminsAsync(roomJid, memberJids);
  }

  // 同步批量移除管理员
  Future<AddUsersResponse> removeAdminsInGroup(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.REMOVE,
        userRole: UserRole.admin,
        isAsync: false);
    // return await mucManager.addAdminsAsync(roomJid, memberJids);
  }

  // 异步批量移除管理员
  Future<AddUsersResponse> removeAdminsInGroupAsync(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.REMOVE,
        userRole: UserRole.admin,
        isAsync: true);
    // return await mucManager.addAdminsAsync(roomJid, memberJids);
  }

  //同步移除群主
  Future<AddUsersResponse> removeOwnersInGroup(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.REMOVE,
        userRole: UserRole.owner,
        isAsync: false);
    // return await mucManager.addAdminsAsync(roomJid, memberJids);
  }

  //异步移除群主
  Future<AddUsersResponse> removeOwnersInGroupAsync(
      String roomName, Iterable<String> memberJids) async {
    final mucManager = xmpp.MultiUserChatManager(_connection!);
    xmpp.Jid roomJid = xmpp.Jid.fromFullJid(roomName);
    if (!roomName.contains(mucDomain ?? '')) {
      roomJid = xmpp.Jid(roomName, mucDomain, '');
    }
    return await mucManager.addRemoveMemberInRoom(
        groupJid: roomJid,
        memberJids: memberJids,
        actionType: ActionType.REMOVE,
        userRole: UserRole.owner,
        isAsync: true);
    // return await mucManager.addAdminsAsync(roomJid, memberJids);
  }

  // 发送单聊消息
  Future<xmpp.MessageStanza> sendMessage(
    String message,
    String receiver,
    bool isCustom, {
    required MessageParams additional,
    void Function(MessageStanza)? onStanzaCreated,
  }) {
    return _messageHandler.sendMessage(
      xmpp.Jid.fromFullJid(receiver),
      message,
      isCustom,
      additional: additional,
      onStanzaCreated: onStanzaCreated,
    );
  }

  // 发送系统消息
  Future<xmpp.MessageStanza> sendSystemMessage(
    String message,
    String receiver, {
    required MessageParams additional,
    void Function(MessageStanza)? onStanzaCreated,
  }) {
    return _messageHandler.sendSystemMessage(
      xmpp.Jid.fromFullJid(receiver),
      message,
      additional: additional,
      onStanzaCreated: onStanzaCreated,
    );
  }
  //发送加密消息
  Future<xmpp.MessageStanza> sendSecureMessage(
      EncryptElement encryptBody, String receiver,
      {MessageParams additional = const MessageParams(
          millisecondTs: 0,
          customString: '',
          messageId: '',
          receipt: ReceiptRequestType.RECEIVED,
          messageType: MessageStanzaType.CHAT,
          chatStateType: ChatStateType.None,
          ampMessageType: AmpMessageType.None,
          options: XmppCommunicationConfig(shallWaitStanza: false),
          hasEncryptedBody: true)}) {
    return _messageHandler.sendSecureMessage(
      xmpp.Jid.fromFullJid(receiver),
      encryptBody,
      additional: additional,
    );
  }
  //发送聊天状态
  Future<xmpp.MessageStanza> sendState(String receiver,
      MessageStanzaType messageType, ChatStateType chatStateType) {
    return _messageHandler.sendState(
        xmpp.Jid.fromFullJid(receiver), messageType, chatStateType);
  }
  //发送消息送达回执
  Future<xmpp.MessageStanza> sendDeliveryAck(xmpp.MessageStanza message) {
    return _messageHandler.sendMessage(message.fromJid, '', false,
        additional: MessageParams(
            receipt: xmpp.ReceiptRequestType.RECEIVED,
            messageId: message.id!,
            millisecondTs: 0,
            customString: '',
            chatStateType: ChatStateType.None,
            messageType: MessageStanzaType.CHAT,
            ampMessageType: AmpMessageType.None,
            options: XmppCommunicationConfig(shallWaitStanza: false),
            hasEncryptedBody: false));
  }

  /// Archive related methods

  void queryArchiveByTime(ManagerQueryArchiveParams queryParams) {
    _messageArchiveHandler.queryByTime(
        start: queryParams.start,
        end: queryParams.end,
        jid: Jid.fromFullJid(queryParams.jid ?? ""),
        id: queryParams.id,
        includeGroup: queryParams.includeGroup);
  }

  void queryArchiveById(ManagerQueryArchiveParams queryParams) {
    _messageArchiveHandler.queryById(
        beforeId: queryParams.beforeId,
        afterId: queryParams.afterId,
        jid: (queryParams.jid != '' && queryParams.jid != null)
            ? Jid.fromFullJid(queryParams.jid ?? "")
            : null,
        id: queryParams.id,
        includeGroup: queryParams.includeGroup);
  }

  /// 用户最后活跃
  Future<LastActivityResponse> askLastActivity(final String userJid) async {
    return await _lastActivityManager.askLastActivity(Jid.fromFullJid(userJid));
  }

  // OMEMO Method
  Future<OMEMOGetDevicesResponse> fetchDevices(
      xmpp.OMEMOGetDevicesParams params) async {
    final omemoManager = OMEMOManager.getInstance(_connection!);
    return await omemoManager.fetchDevices(params);
  }

  Future<OMEMOPublishDeviceResponse> publishDevices(
      xmpp.OMEMOPublishDeviceParams params) async {
    final omemoManager = OMEMOManager.getInstance(_connection!);
    return await omemoManager.publishDevice(params);
  }

  Future<OMEMOPublishBundleResponse> publishBundle(
      xmpp.OMEMOPublishBundleParams params) async {
    final omemoManager = OMEMOManager.getInstance(_connection!);
    return await omemoManager.publishBundle(params);
  }

  Future<OMEMOGetBundleResponse> fetchBundle(
      xmpp.OMEMOGetBundleParams params) async {
    final omemoManager = OMEMOManager.getInstance(_connection!);
    return await omemoManager.fetchBundle(params);
  }

  Future<OMEMOEnvelopePlainTextResponse> fetchEnvelopeMessage(
      xmpp.OMEMOEnvelopePlainTextParams params) async {
    final omemoManager = OMEMOManager.getInstance(_connection!);
    return await omemoManager.envelopePlainContent(params);
  }

  Future<OMEMOEnvelopePlainTextParseResponse> fetchEnvelopeMessageFromXml(
      xmpp.OMEMOEnvelopeParsePlainTextParams params) async {
    final omemoManager = OMEMOManager.getInstance(_connection!);
    return await omemoManager.parseEnvelopePlainContent(params);
  }

  Future<OMEMOEnvelopeEncryptionResponse> fetchEncryptionEnvelopeMessage(
      xmpp.OMEMOEnvelopeEncryptionParams params) async {
    final omemoManager = OMEMOManager.getInstance(_connection!);
    return await omemoManager.envelopeEncryptionContent(params);
  }

  // 发送群聊信息更新，比如：主体、头像、禁言、标记已读/未读
  Future<xmpp.MessageStanza> sendMUCInfoMessage(
    String receiver, {
    String? subject,
    String? coverUrl,
    String? membersAddedEncoded,
    String? membersRemovedEncoded,
    bool? isMuted,
    bool? isMarkRead,
    bool? isMarkUnRead,
    MessageParams additional = const MessageParams(
      millisecondTs: 0,
      customString: '',
      messageId: '',
      receipt: ReceiptRequestType.RECEIVED,
      messageType: MessageStanzaType.GROUPCHAT,
      chatStateType: ChatStateType.None,
      ampMessageType: AmpMessageType.None,
      options: XmppCommunicationConfig(shallWaitStanza: false),
      hasEncryptedBody: false,
    ),
  }) {
    return _messageHandler.sendMUCInfoMessage(
      xmpp.Jid.fromFullJid(receiver),
      subject: subject,
      coverUrl: coverUrl,
      membersAddedEncoded: membersAddedEncoded,
      membersRemovedEncoded: membersRemovedEncoded,
      isMarkRead: isMarkRead,
      isMarkUnRead: isMarkUnRead,
      isMuted: isMuted,
      additional: additional,
    );
  }

  // 修改成员角色
  Future<xmpp.MessageStanza> changeMemberRole(
    String receiver, {
    required String userJid,
    required String role,
    MessageParams additional = const MessageParams(
      millisecondTs: 0,
      customString: '',
      messageId: '',
      receipt: ReceiptRequestType.RECEIVED,
      messageType: MessageStanzaType.CHAT,
      chatStateType: ChatStateType.None,
      ampMessageType: AmpMessageType.None,
      options: XmppCommunicationConfig(shallWaitStanza: false),
      hasEncryptedBody: false,
    ),
  }) {
    return _messageHandler.changeMemberRole(
      xmpp.Jid.fromFullJid(receiver),
      userJid: userJid,
      role: role,
      additional: additional,
    );
  }

  // (取消)置顶消息
  Future<xmpp.MessageStanza> pinMessage(
      String receiver, String messageId, bool isPinned,
      {MessageParams additional = const MessageParams(
          millisecondTs: 0,
          customString: '',
          messageId: '',
          receipt: ReceiptRequestType.RECEIVED,
          messageType: MessageStanzaType.CHAT,
          chatStateType: ChatStateType.None,
          ampMessageType: AmpMessageType.None,
          options: XmppCommunicationConfig(shallWaitStanza: false),
          hasEncryptedBody: false)}) {
    return _messageHandler.pinMessage(
        xmpp.Jid.fromFullJid(receiver), messageId, isPinned,
        additional: additional);
  }

  // 消息回应
  Future<xmpp.MessageStanza> reactMessage(
    String receiver,
    String messageId,
    String text,
    String reaction, {
    bool isClear = false,
    MessageParams additional = const MessageParams(
        millisecondTs: 0,
        customString: '',
        messageId: '',
        receipt: ReceiptRequestType.RECEIVED,
        messageType: MessageStanzaType.CHAT,
        chatStateType: ChatStateType.None,
        ampMessageType: AmpMessageType.None,
        options: XmppCommunicationConfig(shallWaitStanza: false),
        hasEncryptedBody: false),
    void Function(MessageStanza)? onStanzaCreated,
  }) {
    return _messageHandler.reactMessage(
      xmpp.Jid.fromFullJid(receiver),
      messageId,
      text,
      reaction,
      additional: additional,
      isClear: isClear,
      onStanzaCreated: onStanzaCreated,
    );
  }

  // 编辑消息
  Future<xmpp.MessageStanza> editMessage(
    String receiver,
    String messageId,
    String text,
    String editContent, {
    MessageParams additional = const MessageParams(
        millisecondTs: 0,
        customString: '',
        messageId: '',
        receipt: ReceiptRequestType.RECEIVED,
        messageType: MessageStanzaType.CHAT,
        chatStateType: ChatStateType.None,
        ampMessageType: AmpMessageType.None,
        options: XmppCommunicationConfig(shallWaitStanza: false),
        hasEncryptedBody: false),
    void Function(MessageStanza)? onStanzaCreated,
  }) {
    return _messageHandler.editMessage(
      xmpp.Jid.fromFullJid(receiver),
      messageId,
      text,
      editContent,
      additional: additional,
      onStanzaCreated: onStanzaCreated,
    );
  }
  //消息已读
  Future<xmpp.MessageStanza> readMessage(
      String receiver, {
        String text = '',
        required String userId, required String messageId,
        MessageParams additional = const MessageParams(
            millisecondTs: 0,
            customString: '',
            messageId: '',
            receipt: ReceiptRequestType.RECEIVED,
            messageType: MessageStanzaType.CHAT,
            chatStateType: ChatStateType.None,
            ampMessageType: AmpMessageType.None,
            options: XmppCommunicationConfig(shallWaitStanza: false),
            hasEncryptedBody: false),
        void Function(MessageStanza)? onStanzaCreated,
      }) {
    return _messageHandler.readMessage(
      to: xmpp.Jid.fromFullJid(receiver),
      userId: userId,
      messageId: messageId,
      text: text,
      additional: additional,
      onStanzaCreated: onStanzaCreated,
    );
  }


  // (取消)置顶对话
  Future<xmpp.MessageStanza> pinChat(
    String receiver,
    bool isPinned, {
    MessageParams additional = const MessageParams(
        millisecondTs: 0,
        customString: '',
        messageId: '',
        receipt: ReceiptRequestType.RECEIVED,
        messageType: MessageStanzaType.CHAT,
        chatStateType: ChatStateType.None,
        ampMessageType: AmpMessageType.None,
        options: XmppCommunicationConfig(shallWaitStanza: false),
        hasEncryptedBody: false),
  }) {
    return _messageHandler.pinChat(
      xmpp.Jid.fromFullJid(receiver),
      isPinned,
      additional: additional,
    );
  }

  // 引用消息
  Future<xmpp.MessageStanza> quoteMessage(
    String receiver,
    String messageId,
    String body,
    String quoteText,
    String userId,
    String username,
    String? messageType,
    String? expts, {
    MessageParams additional = const MessageParams(
        millisecondTs: 0,
        customString: '',
        messageId: '',
        receipt: ReceiptRequestType.RECEIVED,
        messageType: MessageStanzaType.CHAT,
        chatStateType: ChatStateType.None,
        ampMessageType: AmpMessageType.None,
        options: XmppCommunicationConfig(shallWaitStanza: false),
        hasEncryptedBody: false),
    void Function(MessageStanza)? onStanzaCreated,
  }) {
    return _messageHandler.quoteMessage(
      xmpp.Jid.fromFullJid(receiver),
      messageId,
      body,
      quoteText,
      userId,
      username,
      messageType,
      expts,
      additional: additional,
      onStanzaCreated: onStanzaCreated,
    );
  }

  // 撤回消息
  Future<xmpp.MessageStanza> recallMessage(
      String receiver, List<String> messageIds, String fromUserId,
      {MessageParams additional = const MessageParams(
          millisecondTs: 0,
          customString: '',
          messageId: '',
          receipt: ReceiptRequestType.RECEIVED,
          messageType: MessageStanzaType.CHAT,
          chatStateType: ChatStateType.None,
          ampMessageType: AmpMessageType.None,
          options: XmppCommunicationConfig(shallWaitStanza: false),
          hasEncryptedBody: false)}) {
    return _messageHandler.recallMessage(
        xmpp.Jid.fromFullJid(receiver), messageIds, fromUserId,
        additional: additional);
  }

  /// Listeners

  void listens() {
    _listenMessage();
    _listenPresence();
  }

  void _listenMessage() {
    Log.d(LOG_TAG, 'Start listening');
    if (messageListener != null) {
      messageListener!.cancel();
    }
    messageListener =
        _messageHandler.messagesStream.listen((xmpp.MessageStanza? message) {
      var _messageParentWrapped = XMPPMessageParams(message: message);
      var _messageWrapped = _messageParentWrapped;

      if (_messageParentWrapped.isArchive) {
        Log.i(LOG_TAG, 'Archive Message parsing from ${message!.id}');
        _messageWrapped = XMPPMessageParams(
            message: _messageParentWrapped.message!.getArchiveMessage());
      }

      if (_messageWrapped.isCarbon) {
        _onMessage!(_messageWrapped, ListenerType.onMessage_Carbon);
        Log.i(
            LOG_TAG, 'New `ListenerType.onMessage_Carbon` from ${message!.id}');
      }
      if (_messageWrapped.isDelay) {
        _onMessage!(_messageWrapped, ListenerType.onMessage_Delayed);
        Log.i(LOG_TAG,
            'New `ListenerType.onMessage_Delayed` from ${message!.id}');
      }
      if (_messageWrapped.isAckDeliveryDirect) {
        _onMessage!(_messageWrapped, ListenerType.onMessage_Delivered_Direct);
        Log.i(LOG_TAG,
            'New `ListenerType.onMessage_Delivered_Direct` from ${message!.id}');
      }
      if (_messageWrapped.isAckDeliveryStored) {
        _onMessage!(_messageWrapped, ListenerType.onMessage_Delivered_Stored);
        Log.i(LOG_TAG,
            'New `ListenerType.onMessage_Delivered_Stored` from ${message!.id}');
      }
      if (_messageWrapped.isAckDeliveryClient) {
        _onMessage!(_messageWrapped, ListenerType.onMessage_Delivered_Client);
        Log.i(LOG_TAG,
            'New `ListenerType.onMessage_Delivered_Client` from ${message!.id}');
      }
      if (_messageWrapped.isAckReadClient) {
        _onMessage!(_messageWrapped, ListenerType.onMessage_Read_Client);
        Log.i(LOG_TAG,
            'New `ListenerType.onMessage_Read_Client` from ${message!.id}');
      }
      if (_messageWrapped.isGroupInvitationMessage) {
        _onMessage!(_messageWrapped, ListenerType.onMessage_GroupInvitation);
        Log.i(LOG_TAG,
            'New `ListenerType.onMessage_GroupInvitation` from ${message!.id}');
      }
      if (_messageWrapped.isOnlyMessage) {
        if (_messageWrapped.isMessageCustom) {
          _onMessage!(_messageWrapped, ListenerType.onMessage_Custom);
          Log.i(LOG_TAG,
              'New `ListenerType.onMessage_Custom` with Archive: ${_messageParentWrapped.isArchive.toString()} from ${message!.id}');
        }
        if (_messageWrapped.isMessage) {
          _onMessage!(_messageWrapped, ListenerType.onMessage);
          Log.i(LOG_TAG,
              'New `ListenerType.onMessage` with Archive: ${_messageParentWrapped.isArchive.toString()} from ${message!.id}');
        }
        if (_messageWrapped.isEncrypted) {
          _onMessage!(_messageWrapped, ListenerType.onMessage_Encrypted);
          Log.i(LOG_TAG,
              'New `ListenerType.onMessage_Encrypted` with Archive: ${_messageParentWrapped.isArchive.toString()} from ${message!.id}');
        }
      }

      if (_messageParentWrapped.isChatState) {
        _onMessage!(_messageWrapped, ListenerType.onMessage_ChatState);
        Log.i(LOG_TAG,
            'New `ListenerType.onMessage_ChatState` with State: ${_messageParentWrapped.isArchive.toString()} from ${message!.id}');
      }

      // Send receipt if request
      // if (_messageWrapped.isRequestingReceipt) {
      //   sendDeliveryAck(message!);
      // }
    });
  }

  void _listenConnection() {
    xmpp.MessagesListener messagesListener = ClientMessagesListener();
    _connectionStateListener = ConnectionManagerStateChangedListener(
        _connection, messagesListener, this);
    _connectionResponseListener = ConnectionResponseListener(_connection, this);
  }

  void _listenPresence() {
    var presenceManager = xmpp.PresenceManager.getInstance(_connection);
    presenceManager.presenceStream.listen((presenceTypeEvent) {
      _onPresence!(presenceTypeEvent);
      onLog('Presence status: ' +
          presenceTypeEvent.jid!.fullJid! +
          ': ' +
          presenceTypeEvent.showElement.toString());
    });
    presenceManager.subscriptionStream.listen((streamEvent) {
      if (_onPresenceSubscription != null) {
        _onPresenceSubscription!(streamEvent);
      }
    });
  }
}

class ConnectionResponseListener implements ResponseListener {
  xmpp.Connection? _connection;
  late XMPPClientManager _context;

  StreamSubscription<BaseResponse>? subscription;

  ConnectionResponseListener(
      xmpp.Connection? connection, XMPPClientManager context) {
    _connection = connection;
    subscription = _connection!.responseStream.listen(onResponse);
    _context = context;
  }

  @override
  void onResponse(BaseResponse response) {
    if (_context._responseListener != null) {
      _context._responseListener!(response);
    }
  }

  void close() {
    subscription!.cancel();
  }
}

class ConnectionManagerStateChangedListener
    implements xmpp.ConnectionStateChangedListener {
  xmpp.Connection? _connection;
  late XMPPClientManager _context;

  StreamSubscription<xmpp.XmppConnectionState>? subscription;

  ConnectionManagerStateChangedListener(xmpp.Connection? connection,
      xmpp.MessagesListener messagesListener, XMPPClientManager context) {
    _connection = connection;
    subscription =
        _connection!.connectionStateStream.listen(onConnectionStateChanged);
    _context = context;
  }

  void close() {
    subscription!.cancel();
  }

  @override
  void onConnectionStateChanged(xmpp.XmppConnectionState state) {
    if (state == xmpp.XmppConnectionState.Ready) {
      Log.i(_context.LOG_TAG, 'Connected');
      _context.onReady();
    } else if (state == xmpp.XmppConnectionState.Closed) {
      Log.i(_context.LOG_TAG, 'Disconnected');
      _context._connection!.connect();
    } else if (state == xmpp.XmppConnectionState.ForcefullyClosed) {
      Log.i(_context.LOG_TAG, 'ForcefullyClosed');

      _connection!.reconnectionManager!.handleReconnection(reset: false);
    }
    _context.onState(state);
  }

  void onPresence(xmpp.PresenceData event) {
    Log.i(
        _context.LOG_TAG,
        'presence Event from ' +
            event.jid!.fullJid! +
            ' PRESENCE: ' +
            event.showElement.toString());
  }
}

Stream<String> getConsoleStream() {
  return Console.adapter.byteStream().map((bytes) {
    var str = ascii.decode(bytes);
    str = str.substring(0, str.length - 1);
    return str;
  });
}

class ClientMessagesListener implements xmpp.MessagesListener {
  @override
  void onNewMessage(xmpp.MessageStanza? message) {
    if (message!.body != null) {
      Log.i(
          TAG,
          format(
              'New Message from {color.blue}${message.fromJid!.userAtDomain}{color.end} message: {color.red}${message.body}{color.end}'));
    }
  }
}

class ClientPingListener implements xmpp.PingListener {
  final Function onPingReceived;

  const ClientPingListener({required this.onPingReceived});

  @override
  void onPing(IqStanza? iqStanza) {
    onPingReceived(iqStanza);
  }
}

class ClientMAMListener implements xmpp.MessageArchiveListener {
  final Function onResultFinished;

  const ClientMAMListener({required this.onResultFinished});

  @override
  void onFinish(MessageArchiveResult? iqStanza) {
    onResultFinished(iqStanza);
  }
}
