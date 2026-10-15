import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_info.dart';
import '../screens/sub_device_list_screen.dart';
import '../state/workspace_controller.dart';

/// 左侧设备面板:搜索 + 列表 + 分页;点击“shell终端”建隧道直连。← #view-device
class DevicePanel extends StatefulWidget {
  const DevicePanel({super.key});

  @override
  State<DevicePanel> createState() => _DevicePanelState();
}

class _DevicePanelState extends State<DevicePanel> {
  final _nameCtrl = TextEditingController();
  final _storeCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _storeCtrl.dispose();
    super.dispose();
  }

  /// 按当前输入搜索(点「搜索」按钮或输入框回车)
  void _search() {
    context.read<WorkspaceController>().loadDevices(
        page: 1,
        deviceName: _nameCtrl.text.trim(),
        storeName: _storeCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final pages = (ws.total / ws.pageSize).ceil().clamp(1, 1 << 30);

    return Container(
      color: const Color(0xFF252526),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('设备',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: _nameCtrl,
                        onSubmitted: (_) => _search(),
                        decoration: const InputDecoration(
                            labelText: '设备名称', isDense: true))),
                const SizedBox(width: 4),
                Expanded(
                    child: TextField(
                        controller: _storeCtrl,
                        onSubmitted: (_) => _search(),
                        decoration: const InputDecoration(
                            labelText: '门店名称', isDense: true))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                FilledButton(
                  onPressed: _search,
                  child: const Text('搜索'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    _nameCtrl.clear();
                    _storeCtrl.clear();
                    ws.loadDevices(page: 1, deviceName: '', storeName: '');
                  },
                  child: const Text('重置'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ws.devicesLoading
                ? const Center(child: CircularProgressIndicator())
                : (ws.devices.isEmpty
                    ? const Center(
                        child:
                            Text('暂无设备', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: ws.devices.length,
                        itemBuilder: (_, i) => _tile(ws, ws.devices[i]),
                      )),
          ),
          _pager(ws, pages),
        ],
      ),
    );
  }

  Widget _tile(WorkspaceController ws, DeviceInfo d) {
    final selected = ws.selectedDevice?.uniqueKey == d.uniqueKey;
    return InkWell(
      onTap: () => ws.selectDevice(d),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: selected ? const Color(0xFF37374d) : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Tooltip(
                  message: d.isOnline
                      ? '在线'
                      : (d.status == null ? '状态未知' : '离线'),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: d.isOnline
                          ? Colors.green
                          : (d.status == null ? Colors.grey : Colors.redAccent),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  // 设备名称蓝色链接样式,点击跳转子设备页。← handleRowClick
                  child: InkWell(
                    onTap: () => _openSubDevices(d),
                    child: Text(d.deviceName ?? '(未命名设备)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.lightBlue)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Text(d.storeName ?? '-',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            // 按钮单独一行,不占用名称/门店行空间
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => ws.connectDevice(d),
                    icon: const Icon(Icons.terminal, size: 13),
                    label: const Text('shell终端',
                        style: TextStyle(fontSize: 11)),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _openSubDevices(d),
                    icon: const Icon(Icons.device_hub, size: 13),
                    label: const Text('子设备',
                        style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 跳转子设备列表页。← /device/sub?parentDeviceId=id
  void _openSubDevices(DeviceInfo d) {
    final id = d.id;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该设备缺少 id，无法查询子设备')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SubDeviceListScreen(
        parentId: id,
        parentName: d.deviceName ?? id,
      ),
    ));
  }

  Widget _pager(WorkspaceController ws, int pages) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: ws.pageNum > 1
                ? () => ws.loadDevices(page: ws.pageNum - 1)
                : null,
          ),
          Text('第 ${ws.pageNum}/$pages 页',
              style: const TextStyle(fontSize: 12)),
          const Spacer(),
          Text('共 ${ws.total} 条',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: ws.pageNum < pages
                ? () => ws.loadDevices(page: ws.pageNum + 1)
                : null,
          ),
        ],
      ),
    );
  }
}
