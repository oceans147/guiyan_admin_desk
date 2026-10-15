import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import 'cam_fields.dart';

/// 设备信息 Tab。← cameraconfig/index.vue tab name=1(getCameraInfo/setCameraInfo)
class DeviceInfoTab extends StatefulWidget {
  const DeviceInfoTab(
      {super.key, required this.deviceId, required this.parentDeviceId});
  final String deviceId;
  final String parentDeviceId;

  @override
  State<DeviceInfoTab> createState() => _DeviceInfoTabState();
}

class _DeviceInfoTabState extends State<DeviceInfoTab> {
  Map<String, dynamic> _form = {};
  Map<String, dynamic>? _network; // getNetwork → data.NetworkInterface
  bool _loading = true;
  bool _auto = true; // IP 自动获取
  String? _error;
  bool _busy = false;

  final _nameCtrl = TextEditingController();
  final _teleCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _teleCtrl.dispose();
    super.dispose();
  }

  ApiService get _api => context.read<ApiService>();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getCameraInfo(
        deviceId: widget.deviceId, parentDeviceId: widget.parentDeviceId);
    final r = decodeScene(res);
    // 同步查询网络配置(IP 获取方式)
    final netRes = await _api.getNetwork(
        deviceId: widget.deviceId, parentDeviceId: widget.parentDeviceId);
    final net = decodeScene(netRes);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.error;
      _form = r.data;
      _nameCtrl.text = pathStr(_form, 'DeviceName');
      _teleCtrl.text = pathStr(_form, 'TelecontrolID');
      final ni = net.data['NetworkInterface'];
      _network = ni is Map ? ni.cast<String, dynamic>() : null;
      final t = _network == null
          ? null
          : pathGet(_network!, 'IPAddress.AddressingType');
      if (t != null) _auto = t.toString() == 'dynamic';
    });
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.redAccent : null,
      duration: const Duration(seconds: 2),
    ));
  }

  /// 提交前把可编辑输入回写 form。
  Map<String, dynamic> _collect() {
    final f = Map<String, dynamic>.from(_form);
    f['DeviceName'] = _nameCtrl.text;
    final tele = int.tryParse(_teleCtrl.text);
    if (tele != null) f['TelecontrolID'] = tele;
    return f;
  }

  Future<void> _submit(
      Future<ApiResult> Function(Map<String, dynamic> body) call,
      String okMsg) async {
    setState(() => _busy = true);
    final res = await call(_collect());
    if (!mounted) return;
    setState(() => _busy = false);
    if (sceneSetOk(res)) {
      _toast(okMsg);
      _load();
    } else {
      final r = decodeScene(res);
      _toast(r.error ?? '操作失败', error: true);
    }
  }

  Future<void> _onSave() => _submit(
      (b) => _api.setCameraInfo(
          deviceId: widget.deviceId,
          parentDeviceId: widget.parentDeviceId,
          body: b),
      '修改成功');

  Future<void> _onTimeSync() => _submit(
      (b) => _api.setTimeInfo(
          deviceId: widget.deviceId,
          parentDeviceId: widget.parentDeviceId,
          body: b),
      '时间校正成功');

  Future<void> _onReboot() => _submit(
      (b) => _api.rebootCamera(
          deviceId: widget.deviceId,
          parentDeviceId: widget.parentDeviceId,
          body: b),
      '重启指令已下发');

  /// IP 自动获取开关 → setNetwork。← autoChange()
  Future<void> _onAutoChange(bool v) async {
    final net = _network;
    if (net == null) return;
    setState(() {
      _auto = v;
      _busy = true;
    });
    final body = Map<String, dynamic>.from(net);
    pathSet(body, 'IPAddress.AddressingType', v ? 'dynamic' : 'static');
    final res = await _api.setNetwork(
        deviceId: widget.deviceId,
        parentDeviceId: widget.parentDeviceId,
        body: body);
    if (!mounted) return;
    setState(() => _busy = false);
    final r = decodeScene(res);
    if (r.code == 200) {
      _toast('设置成功');
    } else {
      _toast(r.error ?? '设置失败', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('加载失败：$_error', style: const TextStyle(color: Colors.redAccent)),
          TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试')),
        ]),
      );
    }
    final disabled = [
      ('设备型号', pathStr(_form, 'Model')),
      ('设备序列号', pathStr(_form, 'SerialNumber')),
      ('设备mac地址', pathStr(_form, 'MacAddress')),
      ('主控版本', pathStr(_form, 'FirmwareVersion')),
      ('编码版本', pathStr(_form, 'EncoderVersion')),
      ('主控版本属性', pathStr(_form, 'FirmwareVersionInfo')),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CamInputField(label: '设备名称', controller: _nameCtrl),
            CamInputField(
                label: '设备编号', controller: _teleCtrl, numeric: true),
            for (final (label, value) in disabled)
              CamField(
                  label: label,
                  child: Text(value.isEmpty ? '-' : value,
                      style: const TextStyle(fontSize: 12, color: Colors.grey))),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                    onPressed: _busy ? null : _onSave,
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child: const Text('保存')),
                const SizedBox(width: 10),
                FilledButton(
                    onPressed: _busy ? null : _onTimeSync,
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child: const Text('时间校正')),
                const SizedBox(width: 10),
                FilledButton(
                    onPressed: _busy ? null : _onReboot,
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.redAccent),
                    child: const Text('重启设备')),
              ],
            ),
            const SizedBox(height: 16),
            CamField(
              label: 'IP自动获取',
              child: Switch(
                value: _auto,
                activeThumbColor: Colors.green,
                onChanged: _network == null || _busy ? null : _onAutoChange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
