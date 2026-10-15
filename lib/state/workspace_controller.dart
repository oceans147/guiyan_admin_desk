import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/device_info.dart';
import '../models/sftp_entry.dart';
import '../models/ssh_connection.dart';
import '../services/api_service.dart';
import '../services/config_store.dart';
import 'tab_session.dart';

/// 主界面状态:设备列表 / 多标签会话 / 文件浏览 / 传输,
/// ← renderer.js 的全局 state + 主界面逻辑。
class WorkspaceController extends ChangeNotifier {
  final ConfigStore configStore;
  final ApiService api;

  WorkspaceController({required this.configStore, required this.api});

  // ---- 连接配置 ----
  List<SSHConnection> connections = [];

  // ---- 多标签会话 ----
  final List<TabSession> tabs = [];
  TabSession? _active;
  TabSession? get activeTab => _active;

  // ---- 设备列表 ----
  List<DeviceInfo> devices = [];
  int pageNum = 1;
  final int pageSize = 10;
  int total = 0;
  String deviceNameFilter = '';
  String storeNameFilter = '';
  bool devicesLoading = false;
  DeviceInfo? selectedDevice;

  // ---- 底部状态栏 ----
  String statusMsg = '就绪';
  double progress = 0;

  final _reloginCtl = StreamController<String>.broadcast();
  Stream<String> get onRelogin => _reloginCtl.stream;

  void bootstrap() {
    connections = configStore.list();
    loadDevices();
    notifyListeners();
  }

  // ================= 设备 =================
  Future<void> loadDevices({
    int? page,
    String? deviceName,
    String? storeName,
  }) async {
    if (page != null) pageNum = page;
    if (deviceName != null) deviceNameFilter = deviceName;
    if (storeName != null) storeNameFilter = storeName;
    devicesLoading = true;
    notifyListeners();

    final res = await api.deviceList(
      pageNum: pageNum,
      pageSize: pageSize,
      deviceType: 1,
      deviceName: deviceNameFilter,
      storeName: storeNameFilter,
    );
    devicesLoading = false;

    if (res.unauthorized) {
      _reloginCtl.add('登录已失效，请重新登录');
      notifyListeners();
      return;
    }
    if (!res.ok) {
      _reloginCtl.add('无法访问设备接口：${res.error}');
      notifyListeners();
      return;
    }

    final d = (res.data is Map) ? res.data as Map : const {};
    final inner = d['data'];
    final box = (inner is Map && inner.isNotEmpty) ? inner : d;
    final rows = box['records'] ??
        box['rows'] ??
        box['list'] ??
        d['rows'] ??
        (d['data'] is List ? d['data'] : []) ??
        const [];
    final list = rows is List ? rows : const [];
    devices = list
        .whereType<Map>()
        .map((e) => DeviceInfo(e.cast<String, dynamic>()))
        .toList();
    total =
        num.tryParse((box['total'] ?? d['total'] ?? list.length).toString())
                ?.toInt() ??
            devices.length;
    if (total == 0) total = devices.length;
    notifyListeners();
  }

  void selectDevice(DeviceInfo r) {
    selectedDevice = r;
    statusMsg = '已选设备：${r.deviceName ?? r.uniqueKey}';
    notifyListeners();
  }

  /// 拉取某球房（父设备）的子设备列表。← listNoPageInfo
  Future<({List<DeviceInfo> items, String? error})> loadSubDevices(
      String parentDeviceId) async {
    final res = await api.subDeviceList(parentDeviceId);
    if (res.unauthorized) {
      _reloginCtl.add('登录已失效，请重新登录');
      notifyListeners();
      return (items: const <DeviceInfo>[], error: '登录已失效');
    }
    if (!res.ok) {
      return (items: const <DeviceInfo>[], error: res.error ?? '子设备接口请求失败');
    }
    final d = (res.data is Map) ? res.data as Map : const {};
    final rows = d['data'];
    final list = rows is List
        ? rows
            .whereType<Map>()
            .map((e) => DeviceInfo(e.cast<String, dynamic>()))
            .toList()
        : <DeviceInfo>[];
    return (items: list, error: null);
  }

  /// 点击“shell终端”按钮 → 建 frp 隧道直连。← connectDevice()
  Future<void> connectDevice(DeviceInfo r) async {
    final name = r.deviceName;
    if (name == null) {
      statusMsg = '设备记录缺少 deviceName，无法连接';
      notifyListeners();
      return;
    }
    await openSession(SSHConnection.forDevice(name));
  }

  // ================= 会话标签 =================
  Future<void> openSession(SSHConnection c) async {
    // 访问端鉴权 ← authorizeAccess()
    if (c.frpDomain.isNotEmpty) {
      final a = await api.authorizeAccess(c.frpDomain);
      if (!a.allow) {
        statusMsg = '访问未授权：${a.reason ?? '鉴权失败'}';
        notifyListeners();
        return;
      }
    }

    final id = 's-${DateTime.now().microsecondsSinceEpoch}';
    final tab = TabSession(id: id, title: c.displayTitle, config: c);
    tabs.add(tab);
    _active = tab;
    statusMsg = '正在连接 ${c.host}:${c.port} …';
    notifyListeners();

    try {
      await tab.open();
      statusMsg = '已连接：${tab.title}';
      await loadFilesFor(tab, tab.currentPath);
    } catch (e) {
      tabs.remove(tab);
      await tab.dispose();
      _active = tabs.isNotEmpty ? tabs.last : null;
      statusMsg = '连接失败：$e';
      notifyListeners();
    }
  }

  void activateTab(TabSession t) {
    _active = t;
    if (t.connected && t.files.isEmpty) loadFilesFor(t, t.currentPath);
    notifyListeners();
  }

  Future<void> closeTab(TabSession t) async {
    final idx = tabs.indexOf(t);
    tabs.remove(t);
    t.disconnect();
    await t.dispose();
    if (_active == t) {
      _active = idx < tabs.length
          ? tabs[idx]
          : (tabs.isNotEmpty ? tabs.last : null);
    }
    notifyListeners();
  }

  void disconnectActive() {
    _active?.disconnect();
    statusMsg = '已断开连接';
    notifyListeners();
  }

  // ================= 文件管理(作用于活动标签) =================
  Future<void> loadFilesFor(TabSession tab, String path) async {
    if (!tab.connected) return;
    statusMsg = '读取目录：$path';
    notifyListeners();
    try {
      final items = await tab.ssh.list(path);
      tab.applyFileList(path, items);
      statusMsg = '就绪 · ${items.length} 项';
    } catch (e) {
      statusMsg = '读取失败：$e';
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    final t = _active;
    if (t != null) await loadFilesFor(t, t.currentPath);
  }

  void selectFile(SftpEntry? f) => _active?.select(f);

  Future<void> mkdir(String name) async {
    final t = _active;
    if (t == null || !t.connected || name.isEmpty) return;
    try {
      await t.ssh.mkdir(t.childPath(name));
      await loadFilesFor(t, t.currentPath);
    } catch (e) {
      statusMsg = '创建失败：$e';
      notifyListeners();
    }
  }

  Future<void> renameSelected(String newName) async {
    final t = _active;
    final f = t?.selectedFile;
    if (t == null || f == null || newName.isEmpty || newName == f.name) return;
    try {
      await t.ssh.rename(t.childPath(f.name), t.childPath(newName));
      await loadFilesFor(t, t.currentPath);
    } catch (e) {
      statusMsg = '重命名失败：$e';
      notifyListeners();
    }
  }

  Future<void> deleteSelected() async {
    final t = _active;
    final f = t?.selectedFile;
    if (t == null || f == null) return;
    try {
      final p = t.childPath(f.name);
      if (f.isDir) {
        await t.ssh.removeDir(p);
      } else {
        await t.ssh.removeFile(p);
      }
      await loadFilesFor(t, t.currentPath);
    } catch (e) {
      statusMsg = '删除失败：$e';
      notifyListeners();
    }
  }

  /// 上传:选择本地文件后逐个上传到当前目录。← transfer:upload
  Future<void> uploadFiles(List<String> localPaths) async {
    final t = _active;
    if (t == null || !t.connected) return;
    var failed = 0;
    for (final lp in localPaths) {
      final name = lp.split(RegExp(r'[\\/]')).last;
      try {
        await t.ssh.upload(lp, t.childPath(name), (done, tot) {
          _setProgress('上传 $name', done, tot);
        });
      } catch (_) {
        failed++;
      }
    }
    statusMsg = failed > 0 ? '上传完成，失败 $failed 个' : '上传完成';
    await loadFilesFor(t, t.currentPath);
  }

  /// 下载(文件到 savePath / 目录到 localDir)。← transfer:download
  Future<void> downloadEntry(
    SftpEntry f, {
    required String localTarget,
    bool isDir = false,
  }) async {
    final t = _active;
    if (t == null || !t.connected) return;
    final rp = t.childPath(f.name);
    try {
      if (isDir) {
        await t.ssh.downloadDirRecursive(rp, localTarget,
            (done, tot) => _setProgress('下载目录 ${f.name}', done, tot));
      } else {
        await t.ssh.download(
            rp, localTarget, (done, tot) => _setProgress('下载 ${f.name}', done, tot));
      }
      progress = 1;
      statusMsg = '传输完成';
    } catch (e) {
      statusMsg = '传输失败：$e';
    }
    notifyListeners();
  }

  void _setProgress(String label, int done, int totalBytes) {
    progress = totalBytes > 0 ? done / totalBytes : 0;
    statusMsg = '$label ${(progress * 100).round()}%';
    notifyListeners();
  }

  // ================= 连接配置管理 =================
  Future<void> saveConnection(SSHConnection c) async {
    await configStore.upsert(c);
    connections = configStore.list();
    notifyListeners();
  }

  Future<void> deleteConnection(String id) async {
    await configStore.remove(id);
    connections = configStore.list();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in tabs) {
      t.dispose();
    }
    _reloginCtl.close();
    super.dispose();
  }
}
