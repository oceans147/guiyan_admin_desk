import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/sftp_entry.dart';
import '../models/ssh_connection.dart';
import 'frp_tunnel.dart';

/// 传输进度回调:已传字节 / 总字节。
typedef ProgressCallback = void Function(int transferred, int total);

/// SSH 连接管理器,← electron/ssh-manager.js。
/// 一个实例对应一路远程会话:交互式 shell + SFTP 文件通道。
class SshSession {
  SSHClient? _client;
  SSHSession? _shell;
  SftpClient? _sftp;

  /// 单订阅控制器：监听者尚未接入时事件会内部缓冲，
  /// 避免连接刚建立时的 MOTD/首个提示符被 broadcast 流丢弃（否则终端首屏空白）。
  final _outCtl = StreamController<List<int>>();
  final _closedCtl = StreamController<void>.broadcast();

  /// 已按 UTF-8 增量解码的文本输出，直接喂给终端模拟器。
  /// 注意：单订阅流，只能 listen 一次。
  Stream<String> get outputText =>
      _outCtl.stream.transform(const Utf8Decoder(allowMalformed: true));

  Stream<void> get onClosed => _closedCtl.stream;

  bool get isConnected => _client != null;

  /// 建立连接并打开 shell,返回远程 home 目录。
  Future<String> connect({
    required SSHConnection config,
    int cols = 80,
    int rows = 24,
  }) async {
    // 1) 底层 socket:frp 隧道 or 直连
    final SSHSocket socket;
    if (config.frpDomain.isNotEmpty) {
      socket = await FrpTunnelSocket.connect(
        host: config.host,
        port: config.port,
        serverName: config.frpDomain,
      );
    } else {
      socket = await SSHSocket.connect(
        config.host,
        config.port,
        timeout: const Duration(seconds: 20),
      );
    }

    // 2) 认证:私钥优先,否则密码
    List<SSHIdentity>? identities;
    if (config.authType == AuthType.key) {
      var pem = config.privateKey;
      if (pem.isEmpty && config.privateKeyPath.isNotEmpty) {
        pem = await File(config.privateKeyPath).readAsString();
      }
      if (pem.isEmpty) throw StateError('未提供私钥内容');
      identities =
          SSHKeyPair.fromPem(pem, config.passphrase.isEmpty ? null : config.passphrase);
    }

    final client = SSHClient(
      socket,
      username: config.username,
      identities: identities,
      onPasswordRequest: () =>
          config.authType == AuthType.password ? config.password : '',
      handshakeTimeout: const Duration(seconds: 20),
      authTimeout: const Duration(seconds: 20),
    );
    _client = client;

    await client.authenticated;

    // 3) 交互式 shell
    final shell = await client.shell(
      pty: SSHPtyConfig(type: 'xterm-256color', width: cols, height: rows),
    );
    _shell = shell;
    shell.stdout.listen((d) => _outCtl.add(d), onError: (e) => _outCtl.addError(e));
    shell.stderr.listen((d) => _outCtl.add(d));
    shell.done.then((_) {
      _shell = null;
      if (!_closedCtl.isClosed) _closedCtl.add(null);
    });

    final home = await homeDir();
    return home;
  }

  /// 用户按键 → 远程 shell。
  void writeInput(String data) {
    _shell?.stdin.add(Uint8List.fromList(utf8.encode(data)));
  }

  /// 终端尺寸变化 → 通知远程(width=cols, height=rows)。
  void resize(int cols, int rows) {
    try {
      _shell?.resizeTerminal(cols, rows);
    } catch (_) {}
  }

  Future<String> homeDir() async {
    final c = _client;
    if (c == null) throw StateError('尚未连接');
    final out = await c.run('echo \$HOME');
    final s = utf8.decode(out, allowMalformed: true).trim();
    return s.isEmpty ? '~' : s;
  }

  Future<SftpClient> _ensureSftp() async {
    final c = _client;
    if (c == null) throw StateError('尚未连接');
    return _sftp ??= await c.sftp();
  }

  String _remoteJoin(String base, String sub) {
    if (sub.isEmpty) return base;
    if (sub.startsWith('/')) return sub;
    if (base == '~' || base.isEmpty) return '/$sub';
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$b/$sub';
  }

  String childPath(String base, String name) => _remoteJoin(base, name);

  /// 列目录(目录优先 + 名称排序)。← mgr.list()
  Future<List<SftpEntry>> list(String path) async {
    final sftp = await _ensureSftp();
    final entries = await sftp.listdir(path);
    final items = entries.map((e) {
      final a = e.attr;
      return SftpEntry(
        name: e.filename,
        size: a.size ?? 0,
        isDir: a.isDirectory,
        isLink: a.isSymbolicLink,
        mtimeMs: (a.modifyTime ?? 0) * 1000,
      );
    }).toList();
    items.sort((x, y) {
      if (x.isDir != y.isDir) return x.isDir ? -1 : 1;
      return x.name.toLowerCase().compareTo(y.name.toLowerCase());
    });
    return items;
  }

  Future<void> mkdir(String path) async => (await _ensureSftp()).mkdir(path);

  Future<void> removeFile(String path) async => (await _ensureSftp()).remove(path);

  Future<void> removeDir(String path) async => (await _ensureSftp()).rmdir(path);

  Future<void> rename(String a, String b) async => (await _ensureSftp()).rename(a, b);

  /// 上传单个文件(带进度)。← mgr.upload()
  Future<void> upload(
    String localPath,
    String remotePath,
    ProgressCallback onProgress,
  ) async {
    final sftp = await _ensureSftp();
    final file = File(localPath);
    final total = await file.length();
    final remote = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.truncate |
          SftpFileOpenMode.write,
    );
    try {
      final writer = remote.write(
        file.openRead().cast<Uint8List>(),
        onProgress: (written) => onProgress(written, total),
      );
      await writer.done;
    } finally {
      await remote.close();
    }
  }

  /// 下载单个文件(带进度)。← mgr.download()
  Future<void> download(
    String remotePath,
    String localPath,
    ProgressCallback onProgress,
  ) async {
    final sftp = await _ensureSftp();
    final stat = await sftp.stat(remotePath);
    final total = stat.size ?? 0;
    final lf = File(localPath);
    await lf.parent.create(recursive: true);
    final sink = lf.openWrite();
    try {
      await sftp.download(
        remotePath,
        sink,
        closeDestination: false,
        onProgress: (read) => onProgress(read, total),
      );
    } finally {
      await sink.close();
    }
  }

  /// 递归下载远程目录。← downloadRecursive()
  Future<void> downloadDirRecursive(
    String remoteDir,
    String localDir,
    ProgressCallback onProgress,
  ) async {
    await Directory(localDir).create(recursive: true);
    final items = await list(remoteDir);
    for (final it in items) {
      final rp = _remoteJoin(remoteDir, it.name);
      final lp = '$localDir${Platform.pathSeparator}${it.name}';
      if (it.isDir) {
        await downloadDirRecursive(rp, lp, onProgress);
      } else {
        await download(rp, lp, onProgress);
      }
    }
  }

  void disconnect() {
    try {
      _shell?.close();
    } catch (_) {}
    _shell = null;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    _sftp = null;
  }

  Future<void> dispose() async {
    disconnect();
    if (!_outCtl.isClosed) await _outCtl.close();
    if (!_closedCtl.isClosed) await _closedCtl.close();
  }
}
