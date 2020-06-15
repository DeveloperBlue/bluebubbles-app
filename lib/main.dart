import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bluebubble_messages/helpers/utils.dart';
import 'package:bluebubble_messages/managers/contact_manager.dart';
import 'package:bluebubble_messages/managers/life_cycle_manager.dart';
import 'package:bluebubble_messages/managers/method_channel_interface.dart';
import 'package:bluebubble_messages/managers/navigator_manager.dart';
import 'package:bluebubble_messages/managers/notification_manager.dart';
import 'package:bluebubble_messages/managers/settings_manager.dart';
import 'package:bluebubble_messages/repository/database.dart';
import 'package:bluebubble_messages/repository/models/chat.dart';
import 'package:bluebubble_messages/layouts/setup/setup_view.dart';
import 'package:cupertino_back_gesture/cupertino_back_gesture.dart';
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import './layouts/conversation_list/conversation_list.dart';
import 'layouts/conversation_view/new_chat_creator.dart';
import 'settings.dart';
import 'socket_manager.dart';

// void main() => runApp(Main());
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DBProvider.db.initDB();
  initializeDateFormatting('fr_FR', null).then((_) => runApp(Main()));
}

class Main extends StatelessWidget with WidgetsBindingObserver {
  const Main({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BackGestureWidthTheme(
      backGestureWidth: BackGestureWidth.fraction(0.2),
      child: MaterialApp(
        title: 'BlueBubbles',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          // accentColor: Colors.white,
          splashFactory: InkRipple.splashFactory,
          pageTransitionsTheme: PageTransitionsTheme(
            builders: {
              TargetPlatform.android:
                  CupertinoPageTransitionsBuilderCustomBackGestureWidth(),
              TargetPlatform.iOS:
                  CupertinoPageTransitionsBuilderCustomBackGestureWidth(),
            },
          ),
        ),
        navigatorKey: NavigatorManager().navigatorKey,
        home: Home(),
      ),
    );
  }
}

class Home extends StatefulWidget {
  Home({Key key}) : super(key: key);

  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    SettingsManager().init();
    MethodChannelInterface().init(context);
    ReceiveSharingIntent.getInitialMedia().then((List<SharedMediaFile> value) {
      List<File> attachments = <File>[];
      value.forEach((element) {
        attachments.add(File(element.path));
      });
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => NewChatCreator(
              attachments: attachments,
              isCreator: true,
            ),
          ),
          (route) => route.isFirst);
    });
    ReceiveSharingIntent.getInitialText().then((String text) {
      debugPrint("got text " + text);
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => NewChatCreator(
              existingText: text,
              isCreator: true,
            ),
          ),
          (route) => route.isFirst);
    });
    NotificationManager().createNotificationChannel();
    SchedulerBinding.instance
        .addPostFrameCallback((_) => SettingsManager().getSavedSettings());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      LifeCycleManager().close();
    } else if (state == AppLifecycleState.resumed) {
      LifeCycleManager().opened();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder(
        stream: SocketManager().finishedSetup.stream,
        builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
          if (snapshot.hasData) {
            if (snapshot.data) {
              ContactManager().getContacts();
              return ConversationList();
            } else {
              return SetupView();
            }
          } else {
            return Container();
          }
        },
      ),
    );
  }
}
