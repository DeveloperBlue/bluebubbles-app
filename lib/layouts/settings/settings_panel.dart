import 'dart:convert';
import 'dart:ui';

// import 'package:bluebubble_messages/qr_code_scanner.dart';
import 'package:bluebubble_messages/managers/settings_manager.dart';
import 'package:bluebubble_messages/settings.dart';
import 'package:bluebubble_messages/socket_manager.dart';
import 'package:flutter/cupertino.dart';

import '../../helpers/hex_color.dart';
import 'package:flutter/material.dart';

import '../setup/qr_code_scanner.dart';

class SettingsPanel extends StatefulWidget {
  // final Settings settings;
  // final Function saveSettings;

  SettingsPanel({Key key}) : super(key: key);

  @override
  _SettingsPanelState createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  Settings _settingsCopy;

  @override
  void initState() {
    super.initState();
    _settingsCopy = SettingsManager().settings;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Theme.of(context).backgroundColor,
      appBar: PreferredSize(
        preferredSize: Size(MediaQuery.of(context).size.width, 80),
        child: ClipRRect(
          child: BackdropFilter(
            child: AppBar(
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              backgroundColor: Theme.of(context).accentColor.withOpacity(0.5),
            ),
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          ),
        ),
      ),
      body: CustomScrollView(
        physics: AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: <Widget>[
          SliverPadding(
            padding: EdgeInsets.only(top: 130),
          ),
          SliverList(
            delegate: SliverChildListDelegate(
              <Widget>[
                SettingsTile(
                    title: "Connection Status",
                    subTitle: _settingsCopy.connected
                        ? "Connected -> Tap to Refresh"
                        : "Disconnected -> Tap to Refresh",
                    trailing: _settingsCopy.connected
                        ? Icon(Icons.fiber_manual_record,
                            color: HexColor('32CD32'))
                        : Icon(Icons.fiber_manual_record,
                            color: HexColor('DC143C')),
                    onTap: () {
                      _settingsCopy.connected =
                          SettingsManager().settings.connected;
                      setState(() {});
                    }),
                SettingsTile(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        TextEditingController _controller =
                            TextEditingController(
                          text: "https://.ngrok.io",
                        );
                        _controller.selection =
                            TextSelection.fromPosition(TextPosition(offset: 8));

                        return AlertDialog(
                          title: Text(
                            "Server address:",
                            style: Theme.of(context).textTheme.bodyText1,
                          ),
                          content: Container(
                            child: TextField(
                              autofocus: true,
                              controller: _controller,
                              // autofocus: true,
                              scrollPhysics: BouncingScrollPhysics(),
                              style: Theme.of(context).textTheme.bodyText1,
                              keyboardType: TextInputType.multiline,
                              maxLines: null,
                              decoration: InputDecoration(
                                contentPadding:
                                    EdgeInsets.only(top: 5, bottom: 5),
                                // border: InputBorder.none,
                                // border: OutlineInputBorder(),
                                // hintText: 'https://<some-id>.ngrok.com',
                                hintStyle:
                                    Theme.of(context).textTheme.subtitle1,
                              ),
                            ),
                          ),
                          backgroundColor: HexColor('26262a'),
                          actions: <Widget>[
                            FlatButton(
                              child: Text("Ok"),
                              onPressed: () {
                                _settingsCopy.serverAddress = _controller.text;
                                // Singleton().saveSettings(_settingsCopy);
                                Navigator.of(context).pop();
                              },
                            ),
                            FlatButton(
                              child: Text("Cancel"),
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                  title: "Connection Address",
                  subTitle: _settingsCopy.serverAddress,
                  trailing: Icon(Icons.edit, color: HexColor('26262a')),
                ),
                SettingsTile(
                  title: "Re-configure with MacOS Server",
                  trailing: Icon(Icons.camera, color: HexColor('26262a')),
                  onTap: () async {
                    var fcmData;
                    try {
                      fcmData = jsonDecode(
                        await Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (BuildContext context) {
                              return QRCodeScanner();
                            },
                          ),
                        ),
                      );
                    } catch (e) {
                      return;
                    }
                    if (fcmData != null) {
                      _settingsCopy.fcmAuthData = {
                        "project_id": fcmData[2],
                        "storage_bucket": fcmData[3],
                        "api_key": fcmData[4],
                        "firebase_url": fcmData[5],
                        "client_id": fcmData[6],
                        "application_id": fcmData[7],
                      };
                      _settingsCopy.guidAuthKey = fcmData[0];
                      _settingsCopy.serverAddress = fcmData[1];
                      // Singleton().saveSettings(_settingsCopy);
                    }
                  },
                ),
                SettingsSlider(
                  startingVal: _settingsCopy.chunkSize.toDouble(),
                  update: (int val) {
                    _settingsCopy.chunkSize = val;
                  },
                ),
                SettingsTile(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text(
                            "Are you sure?",
                            style: Theme.of(context).textTheme.bodyText1,
                          ),
                          backgroundColor: HexColor('26262a'),
                          actions: <Widget>[
                            FlatButton(
                              child: Text("Yes"),
                              onPressed: () {
                                // SocketManager().deleteDB().then((value) {
                                //   SocketManager().notify();
                                // });
                              },
                            ),
                            FlatButton(
                              child: Text("Cancel"),
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                  title: "Reset DB",
                ),
                SettingsOptions(
                  onChanged: (BrightnessSetting val) {
                    _settingsCopy.brightnessSetting = val;
                    SettingsManager().setTheme(_settingsCopy);
                  },
                  initialVal: _settingsCopy.brightnessSetting,
                )
              ],
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate(
              <Widget>[],
            ),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    // if (_settingsCopy != Singleton().settings) {
    debugPrint("saving settings");
    SettingsManager().saveSettings(_settingsCopy, connectToSocket: true);
    // }
    super.dispose();
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile(
      {Key key, this.onTap, this.title, this.trailing, this.subTitle})
      : super(key: key);

  final Function onTap;
  final String subTitle;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).backgroundColor,
      child: InkWell(
        onTap: this.onTap,
        child: Column(
          children: <Widget>[
            ListTile(
              title: Text(
                this.title,
                style: Theme.of(context).textTheme.bodyText1,
              ),
              trailing: this.trailing,
              subtitle: subTitle != null
                  ? Text(
                      subTitle,
                      style: Theme.of(context).textTheme.subtitle1,
                    )
                  : null,
            ),
            Divider(
              color: Theme.of(context).accentColor.withOpacity(0.5),
              thickness: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsOptions extends StatefulWidget {
  SettingsOptions({Key key, this.onChanged, this.initialVal}) : super(key: key);
  final Function(BrightnessSetting) onChanged;
  final BrightnessSetting initialVal;

  @override
  _SettingsOptionsState createState() => _SettingsOptionsState();
}

class _SettingsOptionsState extends State<SettingsOptions> {
  BrightnessSetting initialVal;

  @override
  void initState() {
    super.initState();
    initialVal = widget.initialVal;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: DropdownButton(
        dropdownColor: Theme.of(context).accentColor,
        icon: Icon(
          Icons.arrow_drop_down,
          color: Theme.of(context).textTheme.bodyText1.color,
        ),
        value: initialVal,
        items: BrightnessSetting.values
            .map<DropdownMenuItem<BrightnessSetting>>((e) {
          return DropdownMenuItem(
            value: e,
            child: Text(
              Settings.brightnessSettingToString(e),
              style: Theme.of(context).textTheme.bodyText1,
            ),
          );
        }).toList(),
        onChanged: (BrightnessSetting val) {
          widget.onChanged(val);
          setState(() {
            initialVal = val;
          });
        },
      ),
    );
  }
}

class SettingsSlider extends StatefulWidget {
  SettingsSlider({this.startingVal, this.update, Key key}) : super(key: key);

  final double startingVal;
  final Function update;

  @override
  _SettingsSliderState createState() => _SettingsSliderState();
}

class _SettingsSliderState extends State<SettingsSlider> {
  double currentVal = 512;
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    debugPrint(widget.startingVal.toString());
    if (widget.startingVal > 1 && widget.startingVal < 5000) {
      currentVal = widget.startingVal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        ListTile(
          title: Text(
            "Attachment Chunk Size",
            style: Theme.of(context).textTheme.bodyText1,
          ),
          subtitle: Slider(
            value: currentVal,
            onChanged: (double value) {
              debugPrint(value.toString());
              setState(() {
                currentVal = value;
                widget.update(currentVal.floor());
              });
            },
            label: currentVal < 1000
                ? "${(currentVal * 1024 / 1000).floor()}kb"
                : "${(currentVal * 1024 * 0.000001).floor()}mb",
            divisions: 30,
            min: 1,
            max: 3000,
          ),
        ),
        Divider(
          color: Theme.of(context).accentColor.withOpacity(0.5),
          thickness: 1,
        ),
      ],
    );
  }
}
