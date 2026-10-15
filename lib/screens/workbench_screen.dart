import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/token_store.dart';
import '../state/auth_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/connection_dialogs.dart';
import '../widgets/device_panel.dart';
import '../widgets/file_manager_panel.dart';
import '../widgets/terminal_panel.dart';
import 'login_screen.dart';

/// 主界面三栏 + 顶/状态栏,← #app。
class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  double _leftWidth = 240;
  double _rightWidth = 400;
  static const _leftMin = 180.0, _leftMax = 520.0;
  static const _rightMin = 260.0, _rightMax = 760.0;

  StreamSubscription<String>? _reloginSub;
  late final TokenStore _tokenStore;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WorkspaceController>();
    _tokenStore = context.read<TokenStore>();
    final (conn, file) = _tokenStore.getPanelWidths();
    _leftWidth = conn.toDouble();
    _rightWidth = file.toDouble();
    // 设备接口 401 / 不可访问 → 退回登录页
    _reloginSub = ws.onRelogin.listen((reason) {
      if (!mounted) return;
      context.read<AuthController>().requireRelogin(reason);
      for (final t in ws.tabs.toList()) {
        ws.closeTab(t);
      }
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    });
  }

  @override
  void dispose() {
    _tokenStore.savePanelWidths(_leftWidth.round(), _rightWidth.round());
    _reloginSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final active = ws.activeTab;
    final on = active?.connected == true;

    return Scaffold(
      body: Column(
        children: [
          _topBar(ws, on),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: _leftWidth, child: const DevicePanel()),
                _splitter((dx) => setState(
                    () => _leftWidth = (_leftWidth + dx).clamp(_leftMin, _leftMax))),
                Expanded(child: const TerminalPanel()),
                _splitter((dx) => setState(
                    () => _rightWidth = (_rightWidth - dx).clamp(_rightMin, _rightMax))),
                SizedBox(width: _rightWidth, child: const FileManagerPanel()),
              ],
            ),
          ),
          _statusBar(ws),
        ],
      ),
    );
  }

  Widget _topBar(WorkspaceController ws, bool connected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF2d2d30),
      child: Row(
        children: [
          const Text('⚡', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          const Text('轨眼设备管理系统',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          const Text('设备管理 · 远程终端 · 文件传输',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const Spacer(),
          Icon(Icons.circle, size: 10, color: connected ? Colors.green : Colors.red),
          const SizedBox(width: 6),
          Text(connected ? '已连接 · ${ws.activeTab?.title}' : '未连接',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () => showConnectionEditor(context, ws, null),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('新建连接'),
          ),
          TextButton.icon(
            onPressed: () => showConnectionManager(context, ws),
            icon: const Icon(Icons.settings_ethernet, size: 16),
            label: const Text('连接管理'),
          ),
          TextButton(
            onPressed: connected ? ws.disconnectActive : null,
            child: const Text('断开'),
          ),
        ],
      ),
    );
  }

  Widget _statusBar(WorkspaceController ws) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF007acc),
      child: Row(
        children: [
          Expanded(
            child: Text(ws.statusMsg,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white)),
          ),
          SizedBox(
            width: 160,
            child: LinearProgressIndicator(value: ws.progress, minHeight: 4),
          ),
        ],
      ),
    );
  }

  Widget _splitter(ValueChanged<double> onDrag) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (e) => onDrag(e.delta.dx),
        child: Container(width: 4, color: const Color(0xFF3c3c3c)),
      ),
    );
  }
}
