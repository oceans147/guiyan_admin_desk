import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_info.dart';
import '../services/api_service.dart';
import '../state/workspace_controller.dart';
import 'camera_config_screen.dart';

/// 球房子设备列表页:点击左侧设备名称/“子设备”按钮整页切换进入。
/// ← web-admin-ui views/device/subDevice/index.vue(含扫描/密码/直播配置/账号配置/查看详情)。
class SubDeviceListScreen extends StatefulWidget {
  const SubDeviceListScreen(
      {super.key, required this.parentId, required this.parentName});
  final String parentId;
  final String parentName;

  @override
  State<SubDeviceListScreen> createState() => _SubDeviceListScreenState();
}

class _SubDeviceListScreenState extends State<SubDeviceListScreen> {
  bool _loading = true;
  String? _error;
  List<DeviceInfo> _items = [];

  final _keywordCtrl = TextEditingController();
  String _keyword = '';
  String _typeFilter = ''; // '' 全部;'1' 垂拍;'3' 斜拍

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  ApiService get _api => context.read<ApiService>();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res =
        await context.read<WorkspaceController>().loadSubDevices(widget.parentId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = res.error;
      _items = res.items;
    });
  }

  List<DeviceInfo> get _filtered => _items.where((d) {
        if (_typeFilter.isNotEmpty && d.bindType?.toString() != _typeFilter) {
          return false;
        }
        if (_keyword.isNotEmpty) {
          final hay = [
            d.id,
            d.deviceName,
            d.bindRemark,
            d.tableCameraName,
            d.deviceIp,
            d.deviceModel,
          ].whereType<String>().join(' ').toLowerCase();
          if (!hay.contains(_keyword.toLowerCase())) return false;
        }
        return true;
      }).toList();

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.redAccent : null,
      duration: const Duration(seconds: 2),
    ));
  }

  // ================= 顶部操作 =================

  /// 重新扫描:成功后延时 2s 刷新列表。← scan()
  Future<void> _scan() async {
    _toast('正在下发扫描指令…');
    final res = await _api.scanSubDevices(widget.parentId);
    final u = _unwrap(res);
    if (u.code == 200) {
      _toast('扫描成功');
      Timer(const Duration(seconds: 2), () {
        if (mounted) _load();
      });
    } else {
      _toast(u.msg.isEmpty ? '扫描失败' : u.msg, error: true);
    }
  }

  Future<void> _scanOther() async {
    final res = await _api.scanOtherCameras(widget.parentId);
    final u = _unwrap(res);
    _toast(u.code == 200 ? '扫描成功' : (u.msg.isEmpty ? '扫描失败' : u.msg),
        error: u.code != 200);
  }

  Future<void> _showSetPasswordDialog() async {
    final pwd = await showDialog<String>(
      context: context,
      builder: (_) => const _PromptDialog(
        title: '统一密码设置',
        label: '设备密码',
        initial: 'zrkj.12.34',
      ),
    );
    if (pwd == null || pwd.isEmpty) return;
    final res =
        await _api.batchSetPassword(parentId: widget.parentId, password: pwd);
    final u = _unwrap(res);
    if (!mounted) return;
    _toast(u.code == 200 ? '修改成功' : (u.msg.isEmpty ? '修改失败' : u.msg),
        error: u.code != 200);
  }

  /// 直播配置:先查当前模式,再选择提交。← liveConfig()/submitLiveConfig()
  Future<void> _showLiveConfigDialog() async {
    int current = 0;
    final pre = await _api.getLiveType(widget.parentId);
    final u = _unwrap(pre);
    final d = u.data;
    try {
      if (d is String && d.isNotEmpty) {
        current = num.tryParse(
                (jsonDecode(d) as Map)['liveType']?.toString() ?? '')?.toInt() ??
            0;
      } else if (d is Map) {
        current = num.tryParse(d['liveType']?.toString() ?? '')?.toInt() ?? 0;
      }
    } catch (_) {}
    if (!mounted) return;
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => _LiveTypeDialog(initial: current),
    );
    if (picked == null) return;
    final res = await _api.setLiveType(widget.parentId, picked);
    final r = _unwrap(res);
    if (!mounted) return;
    _toast(r.code == 200 ? '设置成功' : (r.msg.isEmpty ? '设置失败' : r.msg),
        error: r.code != 200);
  }

  // ================= 行操作 =================

  /// 账号配置:查询已有配置 → 编辑 → 新增/更新。← handleUserConfig()/submitFormBasic()
  Future<void> _showAccountDialog(DeviceInfo row) async {
    final id = row.id;
    if (id == null) return;
    Map<String, dynamic> raw = {};
    final res = await _api.cameraAccountInfo(id);
    final u = _unwrap(res);
    if (u.code == 200 && u.data is Map) {
      raw = (u.data as Map).cast<String, dynamic>();
    }
    final user = (raw['user']?.toString().isNotEmpty == true)
        ? raw['user'].toString()
        : 'admin';
    final password = (raw['password']?.toString().isNotEmpty == true)
        ? raw['password'].toString()
        : 'xsxc.12.34';
    if (!mounted) return;
    final form = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AccountDialog(user: user, password: password),
    );
    if (form == null) return;
    final body = {...raw, 'deviceId': id, ...form};
    final saved = body['id'] != null
        ? await _api.updateDeviceInfo(body)
        : await _api.addDeviceInfo(body);
    final r = _unwrap(saved);
    if (!mounted) return;
    _toast(r.code == 200 ? '保存成功' : (r.msg.isEmpty ? '保存失败' : r.msg),
        error: r.code != 200);
  }

  /// 点击设备名称 → 摄像头配置页。← subDevice handleRowClick 跳 /device/camera
  void _openCamera(DeviceInfo row) {
    final id = row.id;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该设备缺少 id，无法打开配置页')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CameraConfigScreen(
        deviceId: id,
        deviceSn: row.deviceSn ?? row.deviceName ?? '',
        // 注意:web 端路由参数名叫 deviceType,实际传的是 devicePoolBind.bindType
        deviceType: row.bindType,
        parentDeviceId: widget.parentId,
      ),
    ));
  }

  /// 查看详情。← handleUpdate()
  Future<void> _showDetailDialog(DeviceInfo row) async {
    final id = row.id;
    if (id == null) return;
    showDialog(
      context: context,
      builder: (_) => _DetailDialog(
        api: _api,
        deviceId: id,
        parentDeviceId: widget.parentId,
      ),
    );
  }

  ({int code, String msg, Object? data}) _unwrap(ApiResult res) {
    final d = res.data;
    if (d is Map) {
      return (
        code: num.tryParse(d['code']?.toString() ?? '')?.toInt() ?? -1,
        msg: d['msg']?.toString() ?? '',
        data: d['data'],
      );
    }
    return (code: -1, msg: res.error ?? '请求失败', data: null);
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2d2d30),
        foregroundColor: Colors.white,
        title: Text('${widget.parentName} · 子设备',
            style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _filterBar(),
          _actionBar(),
          const Divider(height: 1, color: Color(0xFF3c3c3c)),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('摄像头类型', style: TextStyle(fontSize: 12)),
          SizedBox(
            width: 160,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _typeFilter,
                isExpanded: true,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                dropdownColor: const Color(0xFF2d2d30),
                hint: const Text('请选择摄像头类型'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('全部')),
                  DropdownMenuItem(value: '1', child: Text('垂拍摄像头')),
                  DropdownMenuItem(value: '3', child: Text('斜拍摄像头')),
                ],
                onChanged: (v) => setState(() => _typeFilter = v ?? ''),
              ),
            ),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _keywordCtrl,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '搜索名称 / 备注 / IP / 主键',
                prefixIcon: Icon(Icons.search, size: 16),
              ),
              onSubmitted: (v) => setState(() => _keyword = v.trim()),
            ),
          ),
          FilledButton.icon(
            onPressed: () =>
                setState(() => _keyword = _keywordCtrl.text.trim()),
            icon: const Icon(Icons.search, size: 15),
            label: const Text('搜索'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          OutlinedButton.icon(
            onPressed: () {
              _keywordCtrl.clear();
              setState(() {
                _keyword = '';
                _typeFilter = '';
              });
            },
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('重置'),
            style:
                OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  Widget _actionBar() {
    Widget btn(String label, IconData icon, Color color, VoidCallback onTap) {
      return FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          btn('重新扫描', Icons.radar, Colors.blue, _scan),
          btn('其他摄像头扫描', Icons.search, Colors.orange, _scanOther),
          btn('一键设置密码', Icons.key, Colors.redAccent, _showSetPasswordDialog),
          btn('直播配置', Icons.video_camera_front, Colors.green,
              _showLiveConfigDialog),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败：$_error',
                style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final rows = _filtered;
    if (rows.isEmpty) {
      return const Center(
          child: Text('暂无子设备', style: TextStyle(color: Colors.grey)));
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 48,
                columnSpacing: 24,
                headingTextStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold),
                dataTextStyle: const TextStyle(fontSize: 12),
                columns: const [
                  DataColumn(label: Text('主键')),
                  DataColumn(label: Text('设备名称')),
                  DataColumn(label: Text('备注')),
                  DataColumn(label: Text('门店摄像头名称')),
                  DataColumn(label: Text('设备IP地址')),
                  DataColumn(label: Text('是否开台')),
                  DataColumn(label: Text('设备型号')),
                  DataColumn(label: Text('摄像头类型')),
                  DataColumn(label: Text('设备分类')),
                  DataColumn(label: Text('设备状态')),
                  DataColumn(label: Text('创建时间')),
                  DataColumn(label: Text('修改时间')),
                  DataColumn(label: Text('操作')),
                ],
                rows: rows.map(_row).toList(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text('共 ${rows.length} 台',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        ),
      ],
    );
  }

  DataRow _row(DeviceInfo d) {
    return DataRow(cells: [
      DataCell(Text(d.id ?? '-')),
      DataCell(InkWell(
        onTap: () => _openCamera(d),
        child: Text(d.deviceName ?? '-',
            style: const TextStyle(color: Colors.lightBlue)),
      )),
      DataCell(Text(d.bindRemark ?? '-')),
      DataCell(Text(d.tableCameraName ?? d.poolTableName ?? '-')),
      DataCell(Text(d.deviceIp ?? '-')),
      DataCell(_isOpenTag(d.isOpen)),
      DataCell(Text(d.deviceModel ?? '-')),
      DataCell(_typeTag(d.cameraTypeText)),
      DataCell(_simpleTag(d.deviceTypeText)),
      DataCell(_statusTag(d)),
      DataCell(Text(d.created ?? '-',
          style: const TextStyle(fontSize: 11, color: Colors.grey))),
      DataCell(Text(d.updated ?? '-',
          style: const TextStyle(fontSize: 11, color: Colors.grey))),
      DataCell(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => _showAccountDialog(d),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('账号配置', style: TextStyle(fontSize: 11)),
          ),
          TextButton(
            onPressed: () => _showDetailDialog(d),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('查看详情', style: TextStyle(fontSize: 11)),
          ),
        ],
      )),
    ]);
  }

  Widget _isOpenTag(bool? isOpen) {
    if (isOpen == null) return _simpleTag('未知');
    return isOpen ? _tag('开启', Colors.green) : _tag('关闭', Colors.orange);
  }

  Widget _typeTag(String? text) {
    if (text == null) return const Text('-', style: TextStyle(color: Colors.grey));
    final color = switch (text) {
      '垂拍摄像头' => Colors.green,
      '屏显设备绑定' => Colors.orange,
      _ => Colors.blueGrey,
    };
    return _tag(text, color);
  }

  Widget _simpleTag(String? text) {
    if (text == null) return const Text('-', style: TextStyle(color: Colors.grey));
    final color = switch (text) {
      'MINI主机' => Colors.green,
      '摄像头' => Colors.orange,
      _ => Colors.blueGrey,
    };
    return _tag(text, color);
  }

  Widget _statusTag(DeviceInfo d) {
    if (d.status == null) return _simpleTag('未知');
    return d.isOnline ? _tag('在线', Colors.green) : _tag('离线', Colors.grey);
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

/// 通用单行输入对话框(一键设置密码用)。
class _PromptDialog extends StatefulWidget {
  const _PromptDialog(
      {required this.title, required this.label, this.initial = ''});
  final String title;
  final String label;
  final String initial;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: const Text('确定')),
      ],
    );
  }
}

/// 直播模式选择:0 仅仅斜拍 / 1 全部切换。
class _LiveTypeDialog extends StatefulWidget {
  const _LiveTypeDialog({required this.initial});
  final int initial;

  @override
  State<_LiveTypeDialog> createState() => _LiveTypeDialogState();
}

class _LiveTypeDialogState extends State<_LiveTypeDialog> {
  late int _type = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('直播配置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioGroup<int>(
            groupValue: _type,
            onChanged: (v) => setState(() => _type = v ?? 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(children: [
                  Radio(value: 0),
                  Text('仅仅斜拍'),
                ]),
                const Row(children: [
                  Radio(value: 1),
                  Text('全部切换'),
                ]),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _type),
            child: const Text('确定')),
      ],
    );
  }
}

/// 账号配置编辑对话框。
class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.user, required this.password});
  final String user;
  final String password;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _user =
      TextEditingController(text: widget.user);
  late final TextEditingController _pwd =
      TextEditingController(text: widget.password);

  @override
  void dispose() {
    _user.dispose();
    _pwd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('账号配置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: _user,
              decoration: const InputDecoration(labelText: '账号')),
          const SizedBox(height: 10),
          TextField(
              controller: _pwd,
              decoration: const InputDecoration(labelText: '密码')),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(
                context, {'user': _user.text.trim(), 'password': _pwd.text}),
            child: const Text('确定')),
      ],
    );
  }
}

/// 设备详情对话框:基础信息 + box app 版本列表。← handleUpdate()
class _DetailDialog extends StatefulWidget {
  const _DetailDialog(
      {required this.api,
      required this.deviceId,
      required this.parentDeviceId});
  final ApiService api;
  final String deviceId;
  final String parentDeviceId;

  @override
  State<_DetailDialog> createState() => _DetailDialogState();
}

class _DetailDialogState extends State<_DetailDialog> {
  bool _loading = true;
  Map<String, dynamic> _device = {};
  final List<({String name, String version, String ip})> _apps = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await widget.api.deviceById(widget.deviceId);
    Map<String, dynamic> dev = {};
    if (res.ok && res.data is Map) {
      final d = (res.data as Map)['data'];
      if (d is Map) dev = d.cast<String, dynamic>();
    }
    final mac = dev['deviceMac']?.toString() ?? '';
    List<({String name, String version, String ip})> apps = [];
    if (mac.isNotEmpty) {
      try {
        final bv = await widget.api.boxVersionByMac(widget.parentDeviceId, mac);
        if (bv.ok && bv.data is Map) {
          final data = (bv.data as Map)['data'];
          if (data is Map) {
            final rawInfo = data['versionInfo'];
            final parsed = rawInfo is String ? jsonDecode(rawInfo) : rawInfo;
            if (parsed is Map) {
              final dataMap = parsed['data'];
              if (dataMap is Map) {
                for (final key in dataMap.keys) {
                  try {
                    final v = dataMap[key];
                    final inner = v is String ? jsonDecode(v) : v;
                    if (inner is Map && inner['version'] is Map) {
                      apps.add((
                        name: key.toString(),
                        version:
                            (inner['version']['version'] ?? '-').toString(),
                        ip: (inner['ip'] ?? '-').toString(),
                      ));
                    }
                  } catch (_) {}
                }
              }
            }
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _device = dev;
      _apps.addAll(apps);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设备信息'),
      content: SizedBox(
        width: 460,
        height: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in [
                      ('主键', _device['id']),
                      ('设备名称', _device['deviceName']),
                      ('设备序列号', _device['deviceSn']),
                      ('设备Mac地址', _device['deviceMac']),
                      ('设备IP地址', _device['deviceIp']),
                      ('设备型号', _device['deviceModel']),
                      ('创建时间', _device['created']),
                      ('修改时间', _device['updated']),
                    ].where((e) => e.$2 != null))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 100,
                              child: Text(e.$1,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                            ),
                            Expanded(
                                child: Text(e.$2.toString(),
                                    style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      ),
                    if (_apps.isNotEmpty) ...[
                      const Divider(height: 20),
                      const Text('App 版本',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      for (final a in _apps)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('${a.name}  ·  ${a.version}  ·  ${a.ip}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭')),
      ],
    );
  }
}
