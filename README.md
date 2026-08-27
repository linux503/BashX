# BashX

简单的 macOS 菜单栏工具，参考 ClashX 的基础能力：

- 添加 / 更新 Clash 订阅（YAML / Base64 YAML）
- 节点列表、搜索、按延迟排序
- TCP 测速
- 选择节点并写出 `config.yaml`
- 可选启动本机 `mihomo` / `clash-meta` / `clash`

## 功能

- 订阅更新（Clash YAML / Base64 `ss://`）
- 节点测速、面板选择
- **系统代理一键开关**（`networksetup` → mixed-port）
- **TUN 模式**（写入配置；开启时启动内核会要管理员权限）
- **BashX 智能规则 v6**（国内直连 / 广告拦截 / 国外代理；[规则说明](docs/rules.md)）
- **规则编辑**（面板「规则」页，保存后热重载/重启）
- **菜单栏快速切节点**（按延迟展示前 N 个）

## 环境

- macOS 14+
- Xcode 15+
- 可选：`brew install mihomo`

## 生成工程并编译

```bash
cd /Users/a503/Downloads/Mac-soft/BashX
xcodegen generate
xcodebuild -scheme BashX -configuration Debug -derivedDataPath build
open build/Build/Products/Debug/BashX.app
```

## 使用

1. 菜单栏 → 打开面板 → 添加订阅 → 更新 → 测速
2. **系统代理：开**（会自动尝试启动内核）
3. 或开 **TUN**（会弹管理员密码）
4. 菜单栏「节点：xxx」可快速切换
5. 面板「规则」页可改规则；点「BashX 智能规则 v6」可恢复默认分流

配置目录：`~/Library/Application Support/BashX/`

## 规则

- 文档：[docs/rules.md](docs/rules.md)
- 源文件：[Resources/rules/bashx-smart-rules.txt](Resources/rules/bashx-smart-rules.txt)
- 导出：`bash scripts/export_rules.sh` → `dist/rules/`
- 在线（GitHub 发布后）：`https://cdn.jsdelivr.net/gh/BashX/BashX@main/Resources/rules/bashx-smart-rules.txt`

## iOS

完整客户端（订阅 / 节点 / 测速 / VPN）见 **[docs/ios.md](docs/ios.md)**。

## 说明

- 测速为 TCP / 代理延迟，不是完整网页测速
- TUN 依赖 mihomo，开启时通常需要管理员权限
- 默认规则：国内直连，国外走代理；支持规则 / 全局 / 直连三种模式
- 性能：切节点走 API 热切换；测速默认并发 8；菜单只展示约 12 个节点
