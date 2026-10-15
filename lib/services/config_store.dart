import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/ssh_connection.dart';

/// 连接配置持久化,← electron/config-store.js。
/// 使用应用支持目录下的一个 JSON 文件,跨平台可用。
class ConfigStore {
  static const _fileName = 'frp-shell-connections.json';

  File? _file;
  List<SSHConnection> _connections = [];

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    _file = File('${dir.path}${Platform.pathSeparator}$_fileName');
    await _load();
  }

  Future<void> _load() async {
    final f = _file;
    if (f == null) return;
    try {
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final list = (j['connections'] as List?) ?? const [];
        _connections = list
            .map((e) => SSHConnection.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _connections = [];
    }
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    final body = jsonEncode({
      'connections': _connections.map((c) => c.toJson()).toList(),
    });
    await f.writeAsString(body);
  }

  List<SSHConnection> list() => List.of(_connections);

  SSHConnection? get(String id) {
    for (final c in _connections) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<SSHConnection> upsert(SSHConnection conn) async {
    if (conn.id.isEmpty) {
      conn.id =
          'c_${DateTime.now().millisecondsSinceEpoch}_${conn.host.hashCode.toRadixString(36)}';
    }
    final idx = _connections.indexWhere((c) => c.id == conn.id);
    if (idx >= 0) {
      _connections[idx] = conn;
    } else {
      _connections.add(conn);
    }
    await _save();
    return conn;
  }

  Future<void> remove(String id) async {
    _connections.removeWhere((c) => c.id == id);
    await _save();
  }
}
