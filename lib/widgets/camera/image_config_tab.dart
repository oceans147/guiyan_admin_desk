import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import 'cam_fields.dart';

/// 图像配置 Tab。← cameraconfig/index.vue tab name=2(getImageConfig/setImageConfig)
class ImageConfigTab extends StatefulWidget {
  const ImageConfigTab(
      {super.key,
      required this.deviceId,
      required this.parentDeviceId,
      required this.deviceType});

  final String deviceId;
  final String parentDeviceId;

  /// 路由参数 deviceType(实际是子设备的 bindType),「同步」接口用。
  final String deviceType;

  @override
  State<ImageConfigTab> createState() => _ImageConfigTabState();
}

class _ImageConfigTabState extends State<ImageConfigTab> {
  Map<String, dynamic> _form = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  ApiService get _api => context.read<ApiService>();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getImageConfig(
        deviceId: widget.deviceId, parentDeviceId: widget.parentDeviceId);
    final r = decodeScene(res);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.error;
      _form = r.data;
    });
  }

  void _set(String path, Object? v) => setState(() => pathSet(_form, path, v));

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.redAccent : null,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final res = await _api.setImageConfig(
        deviceId: widget.deviceId,
        parentDeviceId: widget.parentDeviceId,
        body: _form);
    if (!mounted) return;
    setState(() => _busy = false);
    if (sceneSetOk(res)) {
      _toast('修改成功');
      _load();
    } else {
      _toast(decodeScene(res).error ?? '修改失败', error: true);
    }
  }

  /// 同步图像配置到同类型摄像头。← syncImageConfig()
  Future<void> _sync() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('是否确认同步图像配置？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.batchSyncSetConfig(
        deviceId: widget.deviceId,
        parentDeviceId: widget.parentDeviceId,
        type: widget.deviceType);
    if (!mounted) return;
    final r = decodeScene(res);
    _toast(r.code == 200 ? '同步成功' : (r.error ?? '同步失败'), error: r.code != 200);
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

    final lightMode = pathStr(_form, 'SupplementLight.SupplementLightMode');
    final hlcOn = pathBool(_form, 'HLC.Enabled') ?? false;
    final wdrOpen = pathStr(_form, 'WDR.Mode') == 'open';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CamCollapse(title: '图像调节', children: [
              CamSliderField(
                  label: '亮度',
                  value: pathInt(_form, 'Color.BrightnessLevel'),
                  onChanged: (v) => _set('Color.BrightnessLevel', v)),
              CamSliderField(
                  label: '对比度',
                  value: pathInt(_form, 'Color.ContrastLevel'),
                  onChanged: (v) => _set('Color.ContrastLevel', v)),
              CamSliderField(
                  label: '饱和度',
                  value: pathInt(_form, 'Color.SaturationLevel'),
                  onChanged: (v) => _set('Color.SaturationLevel', v)),
              CamSliderField(
                  label: '锐度',
                  value: pathInt(_form, 'Sharpness.SharpnessLevel'),
                  onChanged: (v) => _set('Sharpness.SharpnessLevel', v)),
            ]),
            CamCollapse(title: '曝光', children: [
              CamField(
                label: '曝光时间',
                child: CamDropdown(
                  value: pathStr(_form, 'Shutter.ShutterLevel'),
                  items: camItems({
                    for (final s in [
                      '1/25', '1/50', '1/100', '1/150', '1/200', '1/250',
                      '1/500', '1/750', '1/1000', '1/2000', '1/4000',
                      '1/10000', '1/100000'
                    ])
                      s: s
                  }),
                  onChanged: (v) => _set('Shutter.ShutterLevel', v),
                ),
              ),
              CamSliderField(
                  label: '增益',
                  value: pathInt(_form, 'Gain.GainLevel'),
                  onChanged: (v) => _set('Gain.GainLevel', v)),
            ]),
            CamCollapse(title: '日夜转换', children: [
              CamField(
                label: '日夜转换',
                child: CamDropdown(
                  value: pathStr(_form, 'IrcutFilter.IrcutFilterType'),
                  items: camItems({
                    'day': '白天',
                    'night': '夜晚',
                    'auto': '自动',
                    'schedule': '定时转换'
                  }),
                  onChanged: (v) => _set('IrcutFilter.IrcutFilterType', v),
                ),
              ),
              CamField(
                label: '防补光过曝',
                child: CamBoolDropdown(
                  value: pathBool(_form, 'Exposure.OverexposeSuppress.Enabled'),
                  onChanged: (v) => _set('Exposure.OverexposeSuppress.Enabled', v),
                ),
              ),
              CamField(
                label: '补光模式',
                child: CamDropdown(
                  value: lightMode,
                  items: camItems({
                    'eventIntelligence': '智能补光',
                    'colorVuWhiteLight': '白光补光',
                    'irLight': '红外补光',
                    'close': '关闭'
                  }),
                  onChanged: (v) => _set('SupplementLight.SupplementLightMode', v),
                ),
              ),
              if (['eventIntelligence', 'colorVuWhiteLight', 'irLight']
                  .contains(lightMode))
                CamField(
                  label: '亮度调节模式',
                  child: CamDropdown(
                    value: pathStr(
                        _form, 'SupplementLight.MixedLightBrightnessRegulatMode'),
                    items: camItems({'auto': '自动', 'manual': '手动'}),
                    onChanged: (v) => _set(
                        'SupplementLight.MixedLightBrightnessRegulatMode', v),
                  ),
                ),
              if (lightMode == 'colorVuWhiteLight')
                CamSliderField(
                    label: '白光',
                    value: pathInt(_form, 'SupplementLight.WhiteLightBrightness'),
                    onChanged: (v) =>
                        _set('SupplementLight.WhiteLightBrightness', v)),
              if (lightMode == 'irLight')
                CamSliderField(
                    label: '红光',
                    value: pathInt(_form, 'SupplementLight.IRLightBrightness'),
                    onChanged: (v) => _set('SupplementLight.IRLightBrightness', v)),
              if (lightMode == 'eventIntelligence') ...[
                CamSliderField(
                    label: '白光',
                    value: pathInt(_form,
                        'SupplementLight.EventIntelligenceModeCfg.WhiteLightBrightness'),
                    onChanged: (v) => _set(
                        'SupplementLight.EventIntelligenceModeCfg.WhiteLightBrightness',
                        v)),
                CamSliderField(
                    label: '红外光',
                    value: pathInt(_form,
                        'SupplementLight.EventIntelligenceModeCfg.IrLightBrightness'),
                    onChanged: (v) => _set(
                        'SupplementLight.EventIntelligenceModeCfg.IrLightBrightness',
                        v)),
              ],
            ]),
            CamCollapse(title: '背光', children: [
              CamField(
                label: '背光补偿开启',
                child: CamBoolDropdown(
                  value: pathBool(_form, 'BLC.Enabled'),
                  trueLabel: '是',
                  falseLabel: '否',
                  onChanged: (v) => _set('BLC.Enabled', v),
                ),
              ),
              CamField(
                label: '背光补偿区域',
                child: CamDropdown(
                  value: pathStr(_form, 'BLC.BLCMode'),
                  items: camItems({
                    'UP': '上',
                    'DOWN': '下',
                    'LEFT': '左',
                    'RIGHT': '右',
                    'CENTER': '中心'
                  }),
                  onChanged: (v) => _set('BLC.BLCMode', v),
                ),
              ),
              CamField(
                label: '强光抑制',
                child: CamBoolDropdown(
                  value: pathBool(_form, 'HLC.Enabled'),
                  onChanged: (v) => _set('HLC.Enabled', v),
                ),
              ),
              if (hlcOn)
                CamSliderField(
                    label: '强光抑制等级',
                    value: pathInt(_form, 'HLC.HLCLevel'),
                    onChanged: (v) => _set('HLC.HLCLevel', v)),
            ]),
            CamCollapse(title: '白平衡', children: [
              CamField(
                label: '白平衡',
                child: CamDropdown(
                  value: pathStr(_form, 'WhiteBalance.WhiteBalanceStyle'),
                  items: camItems({
                    'naturallight': '自然光',
                    'auto1': '自动白平衡1',
                    'locked': '锁定白平衡',
                    'incandescentlight': '白炽灯',
                    'warmlight': '暖光灯',
                    'daylightLamp': '日光灯'
                  }),
                  onChanged: (v) => _set('WhiteBalance.WhiteBalanceStyle', v),
                ),
              ),
            ]),
            CamCollapse(title: '视频调整', children: [
              CamField(
                label: '镜像开启',
                child: CamBoolDropdown(
                  value: pathBool(_form, 'ImageFlip.Enabled'),
                  trueLabel: '是',
                  falseLabel: '否',
                  onChanged: (v) => _set('ImageFlip.Enabled', v),
                ),
              ),
              CamField(
                label: '镜像',
                child: CamDropdown(
                  value: pathStr(_form, 'ImageFlip.ImageFlipStyle'),
                  items: camItems({
                    'LEFTRIGHT': '左右',
                    'UPDOWN': '上下',
                    'CENTER': '中心'
                  }),
                  onChanged: (v) => _set('ImageFlip.ImageFlipStyle', v),
                ),
              ),
            ]),
            CamCollapse(title: '宽动态', children: [
              CamField(
                label: '宽动态模式',
                child: CamDropdown(
                  value: pathStr(_form, 'WDR.Mode'),
                  items: camItems({'open': '开启', 'close': '关闭'}),
                  onChanged: (v) => _set('WDR.Mode', v),
                ),
              ),
              if (wdrOpen)
                CamSliderField(
                    label: '宽动态等级',
                    min: 1,
                    value: pathInt(_form, 'WDR.WDRLevel'),
                    onChanged: (v) => _set('WDR.WDRLevel', v)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  child: const Text('设置')),
              const SizedBox(width: 10),
              FilledButton(
                  onPressed: _busy ? null : _sync,
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.green),
                  child: const Text('同步')),
            ]),
          ],
        ),
      ),
    );
  }
}
