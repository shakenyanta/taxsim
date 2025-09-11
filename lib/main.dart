import 'package:charset_converter/charset_converter.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:window_size/window_size.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setWindowFrame(const Rect.fromLTWH(100, 100, 800, 400)); // ウィンドウサイズのみ指定
  runApp(ExampleApp());
}

class ExampleApp extends StatefulWidget {
  @override
  _ExampleAppState createState() => _ExampleAppState();
}

extension IntToString on int {
  String toHex() => '0x${toRadixString(16)}';
  String toPadded([int width = 3]) => toString().padLeft(width, '0');
  String toTransport() {
    switch (this) {
      case SerialPortTransport.usb:
        return 'USB';
      case SerialPortTransport.bluetooth:
        return 'Bluetooth';
      case SerialPortTransport.native:
        return 'Native';
      default:
        return 'Unknown';
    }
  }
}

class _ExampleAppState extends State<ExampleApp> {
  List<String> selectedFunctionList = [];
  List<bool> isOpenList = [];
  var availablePorts = [];
  String? selectedPort;
  List<Color> portStatusColor = []; // ポート状態の色リスト
  List<String> portStatus = [];     // ポート状態の文字列リスト
  late final _timer;
  int elapsedSeconds = 0; // タイマー用の変数追加

  @override
  void initState() {
    super.initState();
    initPorts();
  // 1秒ごとにタイマー変数を更新（状態更新はしない）
    _timer = Stream.periodic(Duration(seconds: 1)).listen((_) {
      setState(() {
        elapsedSeconds += 1;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void initPorts() {
    setState(() {
      availablePorts = SerialPort.availablePorts..sort();
      if (availablePorts.isNotEmpty) {
        selectedPort = availablePorts.first;
      }
  portStatus = List.filled(availablePorts.length, 'クローズ');
  isOpenList = List.filled(availablePorts.length, false); // 初期値はすべてCLOSE
  selectedFunctionList = List.filled(availablePorts.length, '---'); // ComboBox初期値
    });
    updatePortStatus();
  }

  // ポートの状態をまとめて更新
  Future<void> updatePortStatus() async {
    List<String> newStatus = [];
    List<Color> newColor = [];
    for (final address in availablePorts) {
      try {
        final port = SerialPort(address);
        if (!port.isOpen && port.openReadWrite()){
          await Future.delayed(Duration(milliseconds: 100)); // 100ms待機
          port.close();
          port.dispose();
          newStatus.add('利用可');
          newColor.add(Colors.grey);
        } else {
          newStatus.add('利用不可');
          newColor.add(Colors.red);
        }
      } catch (e) {
        print('[$address] open error: $e');
        newStatus.add('利用不可');
        newColor.add(Colors.red);
      }
    }
    setState(() {
      portStatus = newStatus;
      portStatusColor = newColor;
    });
  }

  // Shift-JISデコード関数
  Future<String> decodeShiftJIS(String sjisStr) async {
    // String をバイト配列化（本来はShift-JISバイト列が必要）
    List<int> bytes = sjisStr.codeUnits;
    return await CharsetConverter.decode("shift_jis", Uint8List.fromList(bytes));
  }

  Future<String> getPortDetail(String address) async {
    final port = SerialPort(address);

  // descriptionをShift-JISデコード
    String description = port.description ?? '';
    if (description.isNotEmpty) {
      description = await decodeShiftJIS(description);
  // ()などの余分な文字を削除
      description = description.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    }

    return '$address / $description / ${port.transport.toTransport()}';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text(''),
        ),
        body: FutureBuilder<List<List<String>>>(
          future: Future.wait(
            availablePorts.map((address) async {
              final detail = (await getPortDetail(address)).split(' / ');
              return detail;
            }).toList(),
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data!;
            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DataTable(
                    headingRowHeight: 24, // ヘッダー行の高さ（デフォルトは56）
                    dataRowMinHeight: 24, // 最小行高さ（デフォルトは 36）
                    dataRowMaxHeight: 28, // 最大行高さ（必要に応じて）
                    showCheckboxColumn: false,
                    columns: const [
                      DataColumn(label: Text('COMポート')),
                      DataColumn(label: Text('説明')),
                    ],
                    rows: [
                      for (int i = 0; i < rows.length; i++)
                        DataRow(
                          selected: selectedPort == availablePorts[i],
                          onSelectChanged: (selected) {
                            setState(() {
                              selectedPort = availablePorts[i];
                            });
                          },
                          cells: [
                            DataCell(
                              Row(
                                children: [
                                  Text(rows[i][0], style: TextStyle(fontWeight: FontWeight.normal)),
                                  SizedBox(width: 4),
                                  Builder(
                                    builder: (context) {
                                      final isRed = portStatusColor.length > i && portStatusColor[i] == Colors.red;
                                      String btnLabel;
                                      Color btnBg;
                                      Color btnFg;
                                      if (isRed) {
                                        btnLabel = 'NOT';
                                        btnBg = Colors.red;
                                        btnFg = Colors.white;
                                      } else if (isOpenList.length > i && isOpenList[i]) {
                                        btnLabel = 'OPEN';
                                        btnBg = const Color.fromARGB(248, 56, 250, 82);
                                        btnFg = Colors.white;
                                      } else {
                                        btnLabel = 'CLOSE';
                                        btnBg = portStatusColor.length > i ? portStatusColor[i] : Colors.grey;
                                        btnFg = Colors.white;
                                      }
                                      return ElevatedButton(
                                        onPressed: () {
                                          setState(() {
                                            isOpenList[i] = !isOpenList[i];
                                          });
                                        },
                                        child: Text(btnLabel, style: TextStyle(fontSize: 12)),
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: Size(40, 24),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                                          backgroundColor: btnBg,
                                          foregroundColor: btnFg,
                                        ),
                                      );
                                    },
                                  ),
                                  SizedBox(width: 4),
                                  DropdownButton2<String>(
                                    value: selectedFunctionList.length > i ? selectedFunctionList[i] : '---',
                                    items: <String>['---','JTX', 'MOV', 'CentX', 'DiDi', 'Uber', 'SEIKO', 'PT-750']
                                        .map((String value) => DropdownMenuItem<String>(
                                              value: value,
                                              child: Container(
                                                height: 18,
                                                alignment: Alignment.centerLeft,
                                                child: Text(value, style: TextStyle(fontSize: 12)),
                                              ),
                                            ))
                                        .toList(),
                                    onChanged: ((portStatusColor.length > i && portStatusColor[i] == Colors.red) || (isOpenList.length > i && isOpenList[i]))
                                      ? null
                                      : (String? newValue) {
                                          if (newValue != null) {
                                            setState(() {
                                              selectedFunctionList[i] = newValue;
                                            });
                                          }
                                        },
                                    //dropdownMaxHeight: 400.0, // 400px分表示
                                  ),
                                ],
                              ),
                            ),
                            DataCell(Text(rows[i].length > 1 ? rows[i][1] : '', style: TextStyle(fontWeight: FontWeight.normal))),
                          ],
                        ),
                    ],
                  ),
                  // ...他のウィジェットを追加する場合はここに記述...
                ],
              ),
            );
          },
        ),
  // floatingActionButton（リフレッシュボタン）を削除
      ),
    );
  }
}