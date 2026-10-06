# 机制与排查

完整现场问题和 Windows 原型记录见 [踩坑记录与解决方法](PITFALLS.zh-CN.md)；本页解释当前入口实现。

## 为什么两个 VPN 配置

入口第一次通过 VpnService 建立 `7.7.7.1/32` 的 TUN，第二次建立使用不同地址 `198.18.7.1/32` 的 TUN，保留两个 ParcelFileDescriptor。

在实测 Xiaomi / Android 16 上，旧 TUN 变为 DOWN 但保留 7 地址及本地路由，活动 VPN 的入站过滤对应第二个地址。其他热点客户端可访问监听所有本地 IPv4 地址的 WheelPlay HTTP 服务；入口没有读取/转发 TUN 数据，也不对视频重新编码。

每个配置只给本应用 UID 添加单个 /32 路由，没有默认路由或 DNS。本应用没有 INTERNET 权限。7.7.7.1 是已分配公网空间，本项目仅临时用作设备本地别名，不能宣称拥有或控制该公网地址。未连接相应热点、未确认入口运行时，不应把它当可用入口测试。

上述接口保留和过滤行为是设备实测现象，不是 [VpnService.Builder.establish](https://developer.android.com/reference/android/net/VpnService.Builder#establish()) 承诺的本地别名能力。系统更新、其他设备实现或过滤策略都可能使它失效。

## 生命周期

- 用户明确启动；VpnService 授权由系统界面完成。
- 前台服务类型 specialUse，持续通知可停止；服务返回 START_NOT_STICKY，无开机自启。
- 再次点启动时不积累更多接口。
- 停止、授权撤销、异常和销毁均尝试关闭两个描述符。
- 仅 stopSelf 不足以清理仍被系统绑定的 VPN 服务，所以先直接关闭描述符。
- VERIFY_TIMEOUT 为已有授权时使用的 15 秒诊断入口；正常使用没有定时自动停止。不得借诊断绕过用户 VPN 授权。

## 检查命令

先通过 USB 授权 ADB，以下只读命令不需要 root：

```powershell
adb devices -l
adb shell ip -brief addr
adb shell ip -4 route show table local
adb shell dumpsys activity services local.carplay.localentry
```

多设备时为每条命令加 `-s 你的设备序列号`。运行时应能观察到 7.7.7.1/32、198.18.7.1/32 和前台服务。仅有地址不等于外部可达；必须从已接入热点的另一台设备或实际车机验证网页、画面与触控。

不要公开完整 dumpsys、logcat、应用偏好 XML 或配对日志：它们可能包含无线凭据、设备名称、地址和认证内容。

## 故障排查

| 现象 | 检查与处理 |
| --- | --- |
| Wi-Fi 接入后立刻断开 | 系统热点设备数量上限、阻止名单、客户端名额；本次上限 1 导致系统主动踢掉客户端 |
| 车机提示无法联网 | Android SIM 移动数据能否上网、热点是否共享；不要换回已验证离线的 DIRECT 组重复尝试 |
| 原内网网页也打不开 | 热点是否仍开、浏览器和接收端是否同网、WheelPlay 是否正常监听；先恢复原服务 |
| 原网页正常、7 网页失败 | 本地入口是否运行、系统是否结束服务、两个地址是否保留；停止入口再手动启动并重新验证 |
| 首页正常但黑屏 | 接收端 CarPlay 是否有画面、是否点击启动显示、其他浏览器是否占用会话；检查 JPEG/WebRTC 实际选项 |
| 连接 iPhone 卡住 | 热点凭据是否一致、iPhone 是否取得地址、蓝牙控制是否正常；只改一项后复测，避免同时清配对/改密码/换版本 |
| 尺寸变化后断开 | 关闭自适应浏览器尺寸，恢复接收会话；固定凭据不能阻止组重建 |
| 卡顿 | 分别记录模式、FPS/RTT、信号、丢包、温度和电池策略；FPS/RTT 不等于端到端延迟 |
| 重启后不可访问 | 先解锁手机，按热点 → WheelPlay → 本地入口 → 车机顺序手动恢复 |
| 音频仍从 Android 播放 | 单独测试 iPhone 到 Tesla 蓝牙输出与 iOS 路由；本项目没有实现自动音频切换 |
