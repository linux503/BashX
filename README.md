# BashX

> **免责声明：本仓库仅供技术测试使用，不提供任何形式的商业服务或技术支持。**

macOS 菜单栏代理客户端（mihomo / Clash Meta）。

## 下载

最新版：**[BashX v0.1.42](https://github.com/linux503/BashX/releases/download/v0.1.42/BashX-0.1.42.dmg)**

所有版本：[Releases](https://github.com/linux503/BashX/releases)

## 安装

1. 下载 DMG，将 BashX 拖入「应用程序」
2. 若提示「已损坏」，在 DMG 内运行「首次打开」脚本

## 要求

- macOS 13+ (Ventura)

## 使用

1. 菜单栏打开面板 → 添加订阅 → 更新 → 测速
2. 开启系统代理或 TUN 模式
3. 配置目录：`~/Library/Application Support/BashX/`

## v0.1.42 更新

- Telegram 专用策略组 `TELEGRAM`：按 api.telegram.org 测速，避免 AUTO 乱跳节点导致发消息转圈
- 智能规则 v13：TG 域名 / DC 网段 / 进程 / GEOIP·GEOSITE 统一走 TELEGRAM
- 进程匹配 `strict`，连接 keep-alive 更积极
