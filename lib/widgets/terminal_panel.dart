import 'package:flutter/material.dart';
import 'package:kterm/kterm.dart';
import 'package:provider/provider.dart';

import '../state/tab_session.dart';
import '../state/workspace_controller.dart';

/// 中间终端面板:多标签会话(kterm 渲染)+ 清屏。← #pane-term
class TerminalPanel extends StatelessWidget {
  const TerminalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final active = ws.activeTab;

    return Container(
      color: Colors.black,
      child: Column(
        children: [
          _head(context, ws),
          if (ws.tabs.isNotEmpty) _tabBar(ws),
          Expanded(
            child: active == null
                ? const Center(
                    child: Text(
                      '未打开终端：点击左侧设备条目的「shell终端」新建标签（支持多个）',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : _TermView(key: ValueKey(active.id), session: active),
          ),
        ],
      ),
    );
  }

  Widget _head(BuildContext context, WorkspaceController ws) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF2d2d30),
      child: Row(
        children: [
          const Text('终端 Shell',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          TextButton(
            onPressed: () => ws.activeTab?.clear(),
            child: const Text('清屏'),
          ),
        ],
      ),
    );
  }

  Widget _tabBar(WorkspaceController ws) {
    return Container(
      color: const Color(0xFF252526),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: ws.tabs.map((t) {
            final active = ws.activeTab?.id == t.id;
            return InkWell(
              onTap: () => ws.activateTab(t),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: active ? Colors.black : const Color(0xFF2d2d30),
                child: Row(
                  children: [
                    Icon(Icons.circle,
                        size: 8,
                        color: t.connected ? Colors.green : Colors.grey),
                    const SizedBox(width: 6),
                    Text(t.title, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => ws.closeTab(t),
                      child: const Icon(Icons.close, size: 14),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _TermView extends StatefulWidget {
  const _TermView({super.key, required this.session});
  final TabSession session;

  @override
  State<_TermView> createState() => _TermViewState();
}

class _TermViewState extends State<_TermView> {
  final TerminalController _controller = TerminalController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      widget.session.terminal,
      controller: _controller,
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 14, fontFamily: 'monospace'),
      autofocus: true,
      // 桌面端(Windows/Linux/macOS)用物理键盘事件收输入:
      // kterm 默认走 IME/TextInputConnection 通道(为移动端软键盘设计),
      // 在 Windows/Linux 桌面下这条通道常收不到字符,导致终端无法输入。
      // 置 true 后改用 Focus.onKeyEvent + requestFocus,桌面键盘才稳定。
      hardwareKeyboardOnly: true,
      cursorType: TerminalCursorType.block,
    );
  }
}
