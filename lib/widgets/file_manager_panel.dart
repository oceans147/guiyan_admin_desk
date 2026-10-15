import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sftp_entry.dart';
import '../state/tab_session.dart';
import '../state/workspace_controller.dart';

/// 右侧文件管理面板:面包屑 + 文件表 + 上传/下载/新建/重命名/删除。← #pane-file
class FileManagerPanel extends StatelessWidget {
  const FileManagerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final tab = ws.activeTab;
    final connected = tab?.connected == true;

    return Container(
      color: const Color(0xFF252526),
      child: Column(
        children: [
          _head(context, ws, tab, connected),
          _PathBar(ws: ws, tab: tab, connected: connected),
          Expanded(
            child: !connected
                ? const Center(
                    child: Text('未连接：双击左侧设备建立会话后可浏览文件',
                        style: TextStyle(color: Colors.grey)),
                  )
                : _table(context, ws, tab!),
          ),
        ],
      ),
    );
  }

  Widget _head(
      BuildContext context, WorkspaceController ws, TabSession? tab, bool connected) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
      child: Row(
        children: [
          const Text('文件',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          IconButton(
            tooltip: '上传到当前目录',
            icon: const Icon(Icons.upload_file, size: 18),
            onPressed: connected ? () => _upload(context, ws) : null,
          ),
          IconButton(
            tooltip: '下载选中项',
            icon: const Icon(Icons.download, size: 18),
            onPressed: (connected && tab?.selectedFile != null)
                ? () => _download(context, ws, tab!)
                : null,
          ),
          IconButton(
            tooltip: '新建目录',
            icon: const Icon(Icons.create_new_folder, size: 18),
            onPressed: connected ? () => _mkdir(context, ws) : null,
          ),
          IconButton(
            tooltip: '重命名选中项',
            icon: const Icon(Icons.drive_file_rename_outline, size: 18),
            onPressed: (connected && tab?.selectedFile != null)
                ? () => _rename(context, ws, tab!)
                : null,
          ),
          IconButton(
            tooltip: '删除选中项',
            icon: const Icon(Icons.delete, size: 18),
            onPressed: (connected && tab?.selectedFile != null)
                ? () => _delete(context, ws, tab!)
                : null,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: connected ? ws.refresh : null,
          ),
        ],
      ),
    );
  }

  Widget _table(
      BuildContext context, WorkspaceController ws, TabSession tab) {
    if (tab.files.isEmpty) {
      return const Center(
          child: Text('空目录', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: tab.files.length,
      itemBuilder: (_, i) {
        final f = tab.files[i];
        final selected = tab.selectedFile?.name == f.name;
        return InkWell(
          onTap: () => ws.selectFile(f),
          onDoubleTap: () => _open(context, ws, tab, f),
          child: Container(
            color: selected ? const Color(0xFF37374d) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  f.isDir
                      ? Icons.folder
                      : (f.isLink ? Icons.link : Icons.description),
                  size: 16,
                  color: f.isDir ? Colors.amber : Colors.blueGrey,
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(f.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12))),
                SizedBox(
                  width: 72,
                  child: Text(f.isDir ? '-' : _fmtSize(f.size),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  /// 双击：目录进入，文件下载。
  void _open(
      BuildContext context, WorkspaceController ws, TabSession tab, SftpEntry f) {
    if (f.isDir) {
      ws.loadFilesFor(tab, tab.childPath(f.name));
    } else {
      _download(context, ws, tab, entry: f);
    }
  }

  Future<void> _upload(BuildContext context, WorkspaceController ws) async {
    final result = await FilePicker.pickFiles(dialogTitle: '选择要上传的文件');
    if (result.isEmpty) return;
    final paths = result.map((e) => e.path).whereType<String>().toList();
    if (paths.isEmpty) return;
    await ws.uploadFiles(paths);
  }

  Future<void> _download(BuildContext context, WorkspaceController ws,
      TabSession tab, {SftpEntry? entry}) async {
    final f = entry ?? tab.selectedFile;
    if (f == null) return;
    final dir = await FilePicker.getDirectoryPath(dialogTitle: '选择保存位置');
    if (dir == null) return;
    final sep = dir.endsWith('/') || dir.endsWith(r'\') ? '' : '/';
    if (f.isDir) {
      await ws.downloadEntry(f, localTarget: '$dir$sep${f.name}', isDir: true);
    } else {
      await ws.downloadEntry(f, localTarget: '$dir$sep${f.name}');
    }
  }

  Future<void> _mkdir(BuildContext context, WorkspaceController ws) async {
    final name = await _promptText(context, '新建目录', hint: '目录名');
    if (name != null && name.isNotEmpty) await ws.mkdir(name);
  }

  Future<void> _rename(
      BuildContext context, WorkspaceController ws, TabSession tab) async {
    final cur = tab.selectedFile?.name;
    if (cur == null) return;
    final name = await _promptText(context, '重命名', initial: cur);
    if (name != null && name.isNotEmpty) await ws.renameSelected(name);
  }

  Future<void> _delete(
      BuildContext context, WorkspaceController ws, TabSession tab) async {
    final f = tab.selectedFile;
    if (f == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除 ${f.isDir ? '目录' : '文件'}「${f.name}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) await ws.deleteSelected();
  }

  Future<String?> _promptText(BuildContext context, String title,
      {String? initial, String? hint}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }
}

/// 路径输入栏:可直接输入远程路径回车跳转,支持 ~ / 相对路径;附带上一级按钮。
class _PathBar extends StatefulWidget {
  const _PathBar(
      {required this.ws, required this.tab, required this.connected});
  final WorkspaceController ws;
  final TabSession? tab;
  final bool connected;

  @override
  State<_PathBar> createState() => _PathBarState();
}

class _PathBarState extends State<_PathBar> {
  final TextEditingController _ctrl = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _go(String raw) {
    final t = widget.tab;
    if (t == null || !widget.connected) return;
    final input = raw.trim();
    if (input.isEmpty) {
      _ctrl.text = t.currentPath;
      return;
    }
    String path;
    if (input == '~') {
      path = t.homePath;
    } else if (input.startsWith('~/') || input.startsWith(r'~\')) {
      path = '${t.homePath}/${input.substring(2)}';
    } else if (input.startsWith('/')) {
      path = input;
    } else {
      path = t.childPath(input);
    }
    widget.ws.loadFilesFor(t, path);
  }

  void _up() {
    final t = widget.tab;
    if (t == null || !widget.connected) return;
    final cur = t.currentPath;
    if (cur == '/' || cur.isEmpty) return;
    final idx = cur.lastIndexOf('/');
    widget.ws.loadFilesFor(t, idx <= 0 ? '/' : cur.substring(0, idx));
  }

  @override
  Widget build(BuildContext context) {
    // 非编辑状态时跟随当前目录刷新
    if (!_editing && widget.tab?.currentPath != null) {
      final p = widget.tab!.currentPath;
      if (_ctrl.text != p) _ctrl.text = p;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一级',
            icon: const Icon(Icons.arrow_upward, size: 16),
            onPressed: widget.connected ? _up : null,
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              enabled: widget.connected,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '输入路径后回车跳转，如 /var/log 或 ~/tmp',
              ),
              onTap: () => _editing = true,
              onChanged: (_) => _editing = true,
              onSubmitted: (v) {
                _editing = false;
                _go(v);
              },
            ),
          ),
          IconButton(
            tooltip: '跳转',
            icon: const Icon(Icons.send, size: 16),
            onPressed:
                widget.connected ? () => _go(_ctrl.text) : null,
          ),
        ],
      ),
    );
  }
}
