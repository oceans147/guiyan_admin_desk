import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../models/device_info.dart';
import '../services/api_service.dart';
import '../state/workspace_controller.dart';
import '../widgets/camera/audio_config_tab.dart';
import '../widgets/camera/device_info_tab.dart';
import '../widgets/camera/image_config_tab.dart';
import '../widgets/camera/osd_config_tab.dart';
import '../widgets/camera/video_config_tab.dart';

/// 摄像头配置页:子设备列表点击设备名称进入。
/// ← web-admin-ui views/device/cameraconfig/index.vue(/device/camera 路由),
/// URL 参数 deviceId / deviceSn / deviceType(=bindType) / parentDeviceId 全部保留,
/// deviceType 供「同步图像配置」接口使用。
class CameraConfigScreen extends StatefulWidget {
  const CameraConfigScreen({
    super.key,
    required this.deviceId,
    required this.deviceSn,
    required this.deviceType,
    required this.parentDeviceId,
  });

  final String deviceId;
  final String deviceSn;

  /// 路由参数 deviceType(web 端实际传 devicePoolBind.bindType)。
  final int? deviceType;
  final String parentDeviceId;

  @override
  State<CameraConfigScreen> createState() => _CameraConfigScreenState();
}

class _CameraConfigScreenState extends State<CameraConfigScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  DeviceInfo? _self; // 从子设备列表中按 id 匹配,取 mac 名/球桌名

  @override
  void initState() {
    super.initState();
    // web 端默认打开「图像配置」tab(activeName='2')
    _tabs = TabController(length: 5, vsync: this, initialIndex: 1);
    _loadHeader();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// 头部 mac/球桌名:listNoPageInfo 中按 id 匹配。← getDeviceInfo()
  Future<void> _loadHeader() async {
    final res =
        await context.read<WorkspaceController>().loadSubDevices(widget.parentDeviceId);
    if (!mounted) return;
    setState(() {
      for (final d in res.items) {
        if (d.id == widget.deviceId) {
          _self = d;
          break;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2d2d30),
        foregroundColor: Colors.white,
        title: Text(_self?.deviceSubName ?? 'mac:${widget.deviceSn}',
            style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: '返回子设备列表',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        // 右侧视频面板占窗口约 60%,让画面更大;上下限保证左侧表单可用
        final rightWidth = (constraints.maxWidth * 0.6).clamp(420.0, 960.0);
        return Row(
          children: [
            Expanded(
              child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '球桌名:${_self?.bindRemark ?? '-'}'
                          '    SN:${widget.deviceSn}'
                          '    类型:${widget.deviceType ?? '-'}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: Colors.lightBlue,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.lightBlue,
                  labelStyle: const TextStyle(fontSize: 13),
                  tabs: const [
                    Tab(text: '设备信息'),
                    Tab(text: '图像配置'),
                    Tab(text: '音频配置'),
                    Tab(text: '视频配置'),
                    Tab(text: 'OSD配置'),
                  ],
                ),
                Expanded(
                  child: ColoredBox(
                    color: const Color(0xFF1e1e1e),
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        DeviceInfoTab(
                            deviceId: widget.deviceId,
                            parentDeviceId: widget.parentDeviceId),
                        ImageConfigTab(
                            deviceId: widget.deviceId,
                            parentDeviceId: widget.parentDeviceId,
                            deviceType: widget.deviceType?.toString() ?? ''),
                        AudioConfigTab(
                            deviceId: widget.deviceId,
                            parentDeviceId: widget.parentDeviceId),
                        VideoConfigTab(
                            deviceId: widget.deviceId,
                            parentDeviceId: widget.parentDeviceId),
                        OsdConfigTab(
                            deviceId: widget.deviceId,
                            parentDeviceId: widget.parentDeviceId),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
            const VerticalDivider(width: 1, color: Color(0xFF3c3c3c)),
            SizedBox(
              width: rightWidth,
              child: _StreamPanel(
                  deviceId: widget.deviceId,
                  parentDeviceId: widget.parentDeviceId),
            ),
          ],
        );
      }),
    );
  }
}

/// 拉流面板:获取 artc/rtmp/hls 地址 + 复制 + RTMP 播放(libmpv),
/// 每 10s streamPing 保活。← openStream()/getStream()/streamPing()。
/// 注:artc 协议需阿里云播放器(License 绑定网页域名),本页仅支持 rtmp 直接播放。
class _StreamPanel extends StatefulWidget {
  const _StreamPanel(
      {required this.deviceId, required this.parentDeviceId});
  final String deviceId;
  final String parentDeviceId;

  @override
  State<_StreamPanel> createState() => _StreamPanelState();
}

class _StreamPanelState extends State<_StreamPanel> {
  bool _loading = true;
  String? _error;
  String _uuid = '';
  Map<String, dynamic> _pull = {};
  Timer? _pingTimer;

  // ---- RTMP 播放器(media_kit / libmpv) ----
  Player? _player;
  VideoController? _controller;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  /// 播放 rtmp 拉流地址。← web 端「开始播放」按钮
  Future<void> _playRtmp() async {
    final url = _pull['rtmpUrl']?.toString() ?? '';
    if (url.isEmpty || _playing) return;
    MediaKit.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(
        // 直播流:限制缓冲,降低延迟
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    // 按平台差异化配置解码与渲染:
    // - macOS:TextureHW(OpenGL)渲染路径在新系统/新版 Flutter 上会 abort
    //   或黑屏有声,改走 TextureSW(CPU 渲染)+软解,链路最稳
    // - Windows/Linux:默认 GPU 渲染 + auto 硬解,保持性能
    final controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        hwdec: Platform.isMacOS ? 'no' : null,
        enableHardwareAcceleration: !Platform.isMacOS,
      ),
    );
    setState(() {
      _player = player;
      _controller = controller;
      _playing = true;
    });
    // 诊断:轨道选择与解码参数。若 video 轨道已选中且 videoParams 有分辨率,
    // 说明 mpv 已在解码视频,问题出在渲染层;反之是流/解码器问题。
    player.stream.tracks.listen((t) => debugPrint(
        '[RTMP播放] 可用轨道: video=${t.video.map((e) => e.id).toList()}'
        ' audio=${t.audio.map((e) => e.id).toList()}'));
    player.stream.track.listen((t) => debugPrint(
        '[RTMP播放] 已选轨道: video=${t.video.id} audio=${t.audio.id}'));
    player.stream.videoParams.listen((p) => debugPrint(
        '[RTMP播放] 解码: ${p.w}x${p.h} pixfmt=${p.pixelformat} '
        'hwpixfmt=${p.hwPixelformat}'));
    // 监听播放错误:出错时回收播放器并提示
    player.stream.error.listen((e) {
      if (!mounted || !_playing) return;
      _stopPlay();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('播放失败:$e'),
        backgroundColor: Colors.redAccent,
      ));
    });
    await player.open(Media(url), play: true);
  }

  Future<void> _stopPlay() async {
    final player = _player;
    setState(() {
      _playing = false;
      _player = null;
      _controller = null;
    });
    if (player == null) return;
    await player.stop();
    await player.dispose();
  }

  ApiService get _api => context.read<ApiService>();

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getStreamUrlV2(
        deviceId: widget.deviceId, parentDeviceId: widget.parentDeviceId);
    final outer = res.data;
    if (!mounted) return;
    if (outer is Map && outer['code']?.toString() == '200') {
      Object? decoded = outer['data'];
      if (decoded is String && decoded.isNotEmpty) decoded = jsonDecode(decoded);
      final d = decoded;
      if (d is Map) {
        setState(() {
          _loading = false;
          _uuid = d['uuid']?.toString() ?? '';
          _pull = d['pullStreamUrl'] is Map
              ? Map<String, dynamic>.from(d['pullStreamUrl'] as Map)
              : {};
        });
        _startPing();
        return;
      }
    }
    setState(() {
      _loading = false;
      _error = outer is Map
          ? outer['msg']?.toString() ?? '获取拉流地址失败'
          : res.error ?? '获取拉流地址失败';
    });
  }

  /// 流心跳:每 10s 一次,保持拉流会话。← streamPing()
  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _api.streamPing(
          deviceId: widget.deviceId, parentDeviceId: widget.parentDeviceId);
    });
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已复制'), duration: Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('拉流地址获取失败：$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
          TextButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试')),
        ]),
      );
    }
    final entries = [
      ('artc', _pull['artcUrl']?.toString() ?? ''),
      ('rtmp', _pull['rtmpUrl']?.toString() ?? ''),
      ('hls', _pull['hlsUrl']?.toString() ?? ''),
    ].where((e) => e.$2.isNotEmpty).toList();
    final rtmpUrl = _pull['rtmpUrl']?.toString() ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('视频播放',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.icon(
              onPressed: (_playing || rtmpUrl.isEmpty) ? null : _playRtmp,
              style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('开始播放'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _playing ? _stopPlay : null,
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.stop, size: 16),
              label: const Text('停止播放'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            color: Colors.black,
            // ListView 会给子项无限高约束,media_kit_video 2.x 的 Video
            // 内部 Stack(fit: expand) 在此环境下布局崩溃(表现为只有声音
            // 没有画面),必须用 AspectRatio 收窄为确定高度
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _controller == null
                  ? const Center(
                      child: Text('点击「开始播放」拉取 RTMP 流',
                          style:
                              TextStyle(fontSize: 11, color: Colors.white38)),
                    )
                  : Video(
                      controller: _controller!,
                      controls: MaterialDesktopVideoControls,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(color: Color(0xFF3c3c3c)),
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 4),
          child: Text('拉流地址',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        if (_uuid.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text('会话 uuid:$_uuid(10s 心跳保活中)',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ),
        for (final (proto, url) in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(proto.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.lightBlue,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      tooltip: '复制',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy, size: 14),
                      onPressed: () => _copy(url),
                    ),
                  ],
                ),
                SelectableText(url,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        const Divider(color: Color(0xFF3c3c3c)),
        const Text(
          '说明:页内播放器支持 rtmp 拉流;artc 协议需阿里云播放器(License 绑定网页域名),可在 VLC/IINA 中打开 hls 地址。',
          style: TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }
}
