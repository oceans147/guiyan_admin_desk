import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kterm/kterm.dart';

import '../models/sftp_entry.dart';
import '../models/ssh_connection.dart';
import '../services/ssh_session.dart';

/// 单个终端会话标签,← renderer.js 里的一个 tab(终端 + 其文件浏览状态)。
class TabSession extends ChangeNotifier {
  final String id;
  final String title;
  final SSHConnection config;

  final Terminal terminal = Terminal(maxLines: 5000);
  final SshSession ssh = SshSession();

  bool connected = false;
  String currentPath = '~';
  String homePath = '~';
  List<SftpEntry> files = [];
  SftpEntry? selectedFile;

  StreamSubscription<String>? _outSub;
  StreamSubscription<void>? _closeSub;

  TabSession({required this.id, required this.title, required this.config}) {
    // 用户按键 → 远程 shell ← term.onData
    terminal.onOutput = (data) => ssh.writeInput(data);
    // 尺寸变化 → 通知远程 ← term.onResize
    terminal.onResize = (w, h, pw, ph) => ssh.resize(w, h);
  }

  Future<String> open() async {
    final home = await ssh.connect(config: config);
    _outSub = ssh.outputText.listen((t) => terminal.write(t));
    _closeSub = ssh.onClosed.listen((_) {
      connected = false;
      files = [];
      selectedFile = null;
      terminal.write('\r\n\u001b[31m[连接已断开]\u001b[0m\r\n');
      notifyListeners();
    });
    connected = true;
    currentPath = home;
    homePath = home;
    notifyListeners();
    return home;
  }

  void clear() => terminal.write('\u001b[2J\u001b[H');

  void applyFileList(String path, List<SftpEntry> items) {
    currentPath = path;
    files = items;
    selectedFile = null;
    notifyListeners();
  }

  void select(SftpEntry? f) {
    selectedFile = f;
    notifyListeners();
  }

  String childPath(String name) => ssh.childPath(currentPath, name);

  void disconnect() {
    ssh.disconnect();
    connected = false;
    files = [];
    selectedFile = null;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _outSub?.cancel();
    await _closeSub?.cancel();
    await ssh.dispose();
    super.dispose();
  }
}
