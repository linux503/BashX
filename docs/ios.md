# BashX iOS

iOS 版完整客户端：订阅 / 节点 / TCP 测速 / VPN（Network Extension + Mihomo）。

## 前置条件

1. **付费 Apple 开发者账号**（免费账号无法真正使用 Network Extension）
2. Xcode 15+
3. Go（编译内核）：`brew install go`
4. **真机**（VPN 不能在模拟器完整跑通）

## 安装到手机

```bash
cd /Users/a503/Downloads/Mac-soft/BashX

# 1) 编译内核（已编译可跳过；约数分钟，产物 ~230MB）
chmod +x scripts/build_mihomo_ios.sh
./scripts/build_mihomo_ios.sh

# 2) 生成工程
xcodegen generate
open BashX.xcodeproj
```

在 Xcode 中：

1. 顶部 Scheme 选 **BashXiOS**，设备选你的 iPhone
2. 选中 target **BashXiOS** → Signing & Capabilities
   - Team：你的付费开发者账号
   - 确认 App Groups：`group.com.bashx.app`
3. 同样设置 target **PacketTunnel** 的 Team + App Groups
4. ⌘R 安装到手机
5. **仅当打不开、提示「未受信任的开发者」时**再信任：
   - 打开 **设置**，顶部搜索框搜「**VPN**」或「**设备管理**」
   - 进入 **通用 → VPN与设备管理**（有的系统只显示「设备管理」）
   - 在 **开发者 App** 里点你的开发者账号（如 `Apple Development: …`）
   - 点 **信任「…」** → 再点确认
   - 若列表是空的：说明已经信任过，或安装用的是已信任的 Team，直接回主屏打开 BashX 即可
6. 打开 BashX → 添加订阅 → 更新 → 选节点 → **连接 VPN**

## 功能

| 能力 | 状态 |
|------|------|
| 订阅更新 / 流量信息 | ✅ |
| 节点列表 / 分类 / TCP 测速 | ✅ |
| 规则 / 全局 / 直连 | ✅ |
| VPN 全局接管（Packet Tunnel） | ✅（需内核 + 付费账号） |

## Bundle

- App：`com.bashx.app.ios`
- Tunnel：`com.bashx.app.ios.PacketTunnel`
- App Group：`group.com.bashx.app`

配置写在 App Group 容器：`BashX/mihomo/config.yaml`。
