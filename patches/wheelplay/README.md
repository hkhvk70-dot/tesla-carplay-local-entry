# WheelPlay 网络补丁

上游：<https://github.com/fython/wheelplay>

固定提交：`d8b3a828f478b3b3508917c2e978d3264b47b532`。

这两份补丁只包括网络源文件与对应测试，不包括 UI、素材、认证材料或本机构建参数。被修改的源文件沿用 GPL-3.0。

## 应用

PowerShell 7，在本项目仓库目录：

```powershell
git clone https://github.com/fython/wheelplay.git ../wheelplay-receiver
git -C ../wheelplay-receiver checkout --detach d8b3a828f478b3b3508917c2e978d3264b47b532
git -C ../wheelplay-receiver apply --check ../tesla-carplay-local-entry/patches/wheelplay/0001-manual-hotspot-ipv4.patch
git -C ../wheelplay-receiver apply ../tesla-carplay-local-entry/patches/wheelplay/0001-manual-hotspot-ipv4.patch
```

以上假定本仓库目录名为 `tesla-carplay-local-entry`。目录不同则调整补丁相对路径。

普通热点方案使用第一份补丁：只在 ManualHotspotManager 优先 IPv4，无合适地址时保持原有 IPv6 回退；Wi-Fi Direct 选址不变。

可选第二份补丁适用于此前 DIRECT 客户端保存网络的实验，**实车普通热点方案不需要它**：

```powershell
git -C ../wheelplay-receiver apply --check ../tesla-carplay-local-entry/patches/wheelplay/0002-stable-direct-credentials.patch
git -C ../wheelplay-receiver apply ../tesla-carplay-local-entry/patches/wheelplay/0002-stable-direct-credentials.patch
```

凭据在接收端应用私有存储中生成并保存，首次创建随机，不写入公开仓库或日志。已有配置不完整时返回错误，而不是悄悄轮换密码。Android 回退至系统默认建组时仍可能忽略自定义凭据；这不保证所有无线组永远保持名称。

## 构建和测试

依赖和完整构建过程以 [上游 README](https://github.com/fython/wheelplay/blob/d8b3a828f478b3b3508917c2e978d3264b47b532/README.md) 为准。上游使用 Gradle、NDK 与 CMake；本地入口的独立 SDK 构建脚本不能构建接收端。

```powershell
Push-Location ../wheelplay-receiver
try {
    ./gradlew.bat :shared:testDebugUnitTest :common:testDebugUnitTest :mobile:assembleDebug
} finally {
    Pop-Location
}
```

Linux 使用 `./gradlew`。认证配置需要自行合法提供；不要提交私钥、证书、签名密钥或把带这些材料的自用 APK 当成本项目发行物。

## 撤销

仅在补丁文件尚未另行修改时执行；先 --check 验证，再撤销。若打过第二份补丁先撤销它：

```powershell
git -C ../wheelplay-receiver apply --reverse --check ../tesla-carplay-local-entry/patches/wheelplay/0002-stable-direct-credentials.patch
git -C ../wheelplay-receiver apply --reverse ../tesla-carplay-local-entry/patches/wheelplay/0002-stable-direct-credentials.patch
git -C ../wheelplay-receiver apply --reverse --check ../tesla-carplay-local-entry/patches/wheelplay/0001-manual-hotspot-ipv4.patch
git -C ../wheelplay-receiver apply --reverse ../tesla-carplay-local-entry/patches/wheelplay/0001-manual-hotspot-ipv4.patch
```

只使用第一份补丁时，只执行最后两行。撤销源码不会自动替换手机 APK；重新构建/安装需遵守接收端签名规则，不能靠清除数据恢复签名兼容。
