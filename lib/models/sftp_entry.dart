/// 远程文件条目,对应 ssh-manager.js list() 返回的 item。
class SftpEntry {
  final String name;
  final int size;
  final bool isDir;
  final bool isLink;
  final int mtimeMs;

  const SftpEntry({
    required this.name,
    required this.size,
    required this.isDir,
    required this.isLink,
    this.mtimeMs = 0,
  });
}
