# BashX

> **免责声明：本仓库仅供技术测试使用，不提供任何形式的商业服务或技术支持。**

macOS 菜单栏代理客户端（mihomo / Clash Meta）。

## 下载

最新版：[Releases](https://github.com/linux503/BashX/releases)

## 功能

- 订阅更新（Clash YAML / Base64 `ss://`）
- 节点测速、面板选择
- **系统代理一键开关**（`networksetup` → mixed-port）
- **TUN 模式**（写入配置；开启时启动内核会要管理员权限）
- **BashX 智能规则**（国内直连 / 广告拦截 / 国外代理；[规则说明](docs/rules.md)）
- **规则编辑**（面板「规则」页，保存后热重载/重启）
- **菜单栏快速切节点**（按延迟展示前 10 个）

## 环境

- macOS 13+ (Ventura 13.7.8 及以上)
- Xcode 15+
- 可选：`brew install mihomo`

## 生成工程并编译

```bash
cd BashX
xcodegen generate
xcodebuild -scheme BashX -configuration Debug -derivedDataPath build
open build/Build/Products/Debug/BashX.app
```

## 使用

1. 菜单栏 → 打开面板 → 添加订阅 → 更新 → 测速
2. **系统代理：开**（会自动尝试启动内核）
3. 或开 **TUN**（会弹管理员密码）
4. 菜单栏「节点：xxx」可快速切换
5. 面板「规则」页可改规则

配置目录：`~/Library/Application Support/BashX/`

## 规则

- 文档：[docs/rules.md](docs/rules.md)
- 源文件：[Resources/rules/bashx-smart-rules.txt](Resources/rules/bashx-smart-rules.txt)
- 导出：`bash scripts/export_rules.sh` → `dist/rules/`

## iOS

完整客户端（订阅 / 节点 / 测速 / VPN）见 **[docs/ios.md](docs/ios.md)**。

## 说明

- 测速为 TCP / 代理延迟，不是完整网页测速
- TUN 依赖 mihomo，开启时通常需要管理员权限
- 默认规则：国内直连，国外走代理；支持规则 / 全局 / 直连三种模式
