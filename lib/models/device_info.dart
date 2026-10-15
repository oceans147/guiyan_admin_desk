/// 设备记录(接口返回的一条 device),对应 renderer.js 中的 device row。
class DeviceInfo {
  final Map<String, dynamic> raw;

  const DeviceInfo(this.raw);

  String? get deviceName =>
      _str('deviceName') ??
      _str('name') ??
      _str('deviceNickName') ??
      _str('deviceCode') ??
      _str('code');

  String? get storeName =>
      _str('storeName') ??
      _str('store') ??
      _str('shopName') ??
      _str('deptName');

  String? get id => _str('id');

  /// 设备状态:1 离线,0 在线(接口可能返回数字或字符串)。
  int? get status => num.tryParse(raw['status']?.toString() ?? '')?.toInt();

  bool get isOnline => status == 0;

  /// 设备分类:1 MINI主机,2 摄像头,3 其他。
  int? get deviceType =>
      num.tryParse(raw['deviceType']?.toString() ?? '')?.toInt();

  String? get deviceTypeText {
    switch (deviceType) {
      case 1:
        return 'MINI主机';
      case 2:
        return '摄像头';
      case 3:
        return '其他';
      default:
        return null;
    }
  }

  String? get deviceSn => _str('deviceSn');

  String? get created => _str('created');

  String? get updated => _str('updated');

  String? get deviceIp => _str('deviceIp');

  String? get deviceModel => _str('deviceModel');

  String? get deviceMac => _str('deviceMac');

  /// 门店摄像头名称:在 tableMapResponse.tableList 中按 MAC 匹配条目的 deviceName。
  String? get tableCameraName {
    final t = raw['tableMapResponse'];
    if (t is! Map) return null;
    final list = t['tableList'];
    if (list is! List) return null;
    final mac = deviceMac;
    for (final e in list.whereType<Map>()) {
      if (mac != null && e['mac']?.toString() == mac) {
        return e['deviceName']?.toString();
      }
    }
    return null;
  }

  /// 绑定的球桌映射名(tableMapResponse.poolTableName)。
  String? get poolTableName {
    final t = raw['tableMapResponse'];
    return t is Map ? t['poolTableName']?.toString() : null;
  }

  /// 绑定备注(devicePoolBind.remark),如“1号球桌垂直摄像头”。
  String? get bindRemark {
    final b = raw['devicePoolBind'];
    return b is Map ? b['remark']?.toString() : null;
  }

  /// 设备子名称(devicePoolBind.deviceSubName),摄像头配置页头部 mac 显示用。
  String? get deviceSubName {
    final b = raw['devicePoolBind'];
    return b is Map ? b['deviceSubName']?.toString() : null;
  }

  /// 是否开台(tableMapResponse.isOpen);无球桌映射时返回 null。
  bool? get isOpen {
    final t = raw['tableMapResponse'];
    if (t is Map && t.containsKey('isOpen')) return t['isOpen'] == true;
    return null;
  }

  /// 绑定类型(devicePoolBind.bindType):1 垂拍摄像头,3 斜拍摄像头。
  int? get bindType {
    final b = raw['devicePoolBind'];
    if (b is Map) return num.tryParse(b['bindType']?.toString() ?? '')?.toInt();
    return null;
  }

  String? get cameraTypeText {
    switch (bindType) {
      case 1:
        return '垂拍摄像头';
      case 2:
        return '屏显设备绑定';
      case 3:
        return '斜拍摄像头';
      default:
        return null;
    }
  }

  String? _str(String k) {
    final v = raw[k];
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  String get uniqueKey => id ?? deviceName ?? raw.toString();
}
