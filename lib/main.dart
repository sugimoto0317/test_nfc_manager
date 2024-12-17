import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';

void main() {
  runApp(MaterialApp(
    home: LicenseReaderScreen(),
  ));
}

class LicenseReaderScreen extends StatefulWidget {
  @override
  _LicenseReaderScreenState createState() => _LicenseReaderScreenState();
}

class _LicenseReaderScreenState extends State<LicenseReaderScreen> {
  String _output = "NFCセッションを開始してください";

  void _startNfcSession() async {
    setState(() => _output = "NFCを待機中...");

    // NFCセッション開始
    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          // IsoDep インターフェースを取得
          final isoDep = IsoDep.from(tag);
          if (isoDep == null) {
            throw Exception("ISO-DEPに対応していないタグです");
          }

          // APDUコマンドを送信
          final selectFileCommand = Uint8List.fromList([0x00, 0xA4, 0x02, 0x0C, 0x02, 0x2F, 0x01]); // 公開領域のファイルID選択
          final selectResponse = await isoDep.transceive(data: selectFileCommand);
          _checkSuccess(selectResponse, "ファイル選択");

          final readDataCommand = Uint8List.fromList([0x00, 0xB0, 0x00, 0x00, 0x11]); // 32バイト分のデータ読み取り
          final readResponse = await isoDep.transceive(data: readDataCommand);
          _checkSuccess(readResponse, "データ読み取り");

          // データ解析
          final parsedData = _parseLicenseData(readResponse);
          setState(() => _output = parsedData);
        } catch (e) {
          setState(() => _output = "エラー: ${e.toString()}");
        } finally {
          NfcManager.instance.stopSession();
        }
      },
    );
  }

  void _checkSuccess(Uint8List response, String step) {
    if (response.length < 2 || response[response.length - 2] != 0x90 || response[response.length - 1] != 0x00) {
      throw Exception("$step に失敗しました: ${response.sublist(response.length - 2)}");
    }
  }

  String _parseLicenseData(Uint8List data) {
    if (data.length < 13) {
      return "データが不正です";
    }

    // ステータスコードが0x90であることを確認
    if (data[data.length - 2] != 0x90 || data[data.length - 1] != 0x00) {
      return "データ読み取りに失敗しました";
    }

    // カード発行者データの長さを取得（2バイト目）
    final cardPublisherDataLength = data[1];
    final cardPublisherData = data.sublist(2, 2 + cardPublisherDataLength);

    // 仕様書バージョン（最初の3バイトはShift-JISでデコード）
    final version = _decodeSjis(cardPublisherData.sublist(0, 3));

    // 交付年月日（YYMMDDを16進数形式で取得）
    final publishDate = cardPublisherData.sublist(4, 7).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');

    // 有効期限（YYMMDDを16進数形式で取得）
    final effectiveDate = cardPublisherData.sublist(8, 11).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');

    // 解析結果を表示
    return '''
      ---
      カード発行者データ 読み取り成功
      仕様書バージョン: $version
      発行年月日: $publishDate
      有効期限: $effectiveDate
    ''';
  }

  String _decodeSjis(List<int> bytes) {
    return String.fromCharCodes(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("運転免許証 ICチップ読み取り")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _startNfcSession,
              child: Text("NFCセッション開始"),
            ),
            SizedBox(height: 20),
            Text(
              _output,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
