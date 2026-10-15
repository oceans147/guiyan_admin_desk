import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 渲染自检页:以 --dart-define=VIDEO_SELFTEST=1 启动时替代正常界面,
/// 自动播放已知良好的公网测试视频,用于判断 media_kit 在当前环境的
/// 视频渲染链路是否工作(区分“渲染层问题”与“具体流问题”)。
/// 可用 --dart-define=VIDEO_URL=xxx 指定要测试的地址(如 VLC 能打开的 rtmp 地址)。
class VideoRenderSelfTest extends StatefulWidget {
  const VideoRenderSelfTest({super.key});

  @override
  State<VideoRenderSelfTest> createState() => _VideoRenderSelfTestState();
}

class _VideoRenderSelfTestState extends State<VideoRenderSelfTest> {
  static const _defaultUrl =
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4';
  // --dart-define=VIDEO_URL 可覆盖为待测地址(rtmp/hls 等)
  static const _customUrl = String.fromEnvironment('VIDEO_URL');
  String get _testUrl => _customUrl.isNotEmpty ? _customUrl : _defaultUrl;

  late final Player _player = Player();
  // 与正式播放页一致:macOS 走 TextureSW(CPU 渲染),避免 TextureHW
  // 的 OpenGL 路径在本机 abort/黑屏
  late final VideoController _controller = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      hwdec: Platform.isMacOS ? 'no' : null,
      enableHardwareAcceleration: !Platform.isMacOS,
    ),
  );
  String _status = 'opening...';
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[自检] 打开地址: $_testUrl');
    _player.stream.videoParams.listen((p) {
      debugPrint('[自检] 解码: ${p.w}x${p.h} pixfmt=${p.pixelformat}');
      setState(() => _status = '解码: ${p.w}x${p.h} pixfmt=${p.pixelformat}');
    });
    _player.stream.playing.listen((v) => setState(() => _playing = v));
    _player.stream.error.listen((e) {
      debugPrint('[自检] 错误: $e');
      setState(() => _status = '错误: $e');
    });
    _player.stream.completed.listen((c) {
      if (c) setState(() => _status = '播放完成(渲染链路正常)');
    });
    _player.open(Media(_testUrl), play: true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('VIDEO_SELFTEST',
                style: TextStyle(
                    color: Colors.yellow, fontWeight: FontWeight.bold)),
            Text('$_status | playing=$_playing',
                style: const TextStyle(color: Colors.white)),
            SizedBox(
              width: 640,
              height: 360,
              child: Video(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}
