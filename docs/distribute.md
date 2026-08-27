# 把 BashX 发给其他 Mac

## 为什么别人电脑打不开？

未使用 **Developer ID + 苹果公证** 时，macOS Gatekeeper 会把网上下载的 App 标成隔离，并提示「已损坏」或「无法验证开发者」。这是系统策略，不是 DMG 坏了。

## 现在怎么发（无 Developer ID）

1. 本机执行：`./scripts/build_dmg.sh`
2. 把 `dist/BashX-x.y.z.dmg` 发给对方（尽量用网盘 / AirDrop，少用微信压缩二次打包）
3. 对方：**右键** DMG 里的「一键解锁并打开」→ 打开 → 需要时再点「仍要打开」

## 一劳永逸（推荐）

你已有 Apple 开发者账号（本机已有 Mac App Store 证书），缺的是 **Developer ID Application**：

1. 打开 **Xcode → Settings → Accounts**
2. 选中团队 → **Manage Certificates…**
3. 点 **+** → **Developer ID Application**
4. 终端配置公证（Apple ID + App 专用密码）：

```bash
xcrun notarytool store-credentials BashX-Notary \
  --apple-id "你的AppleID" \
  --team-id "你的TeamID" \
  --password "app-specific-password"
```

5. 再打包：

```bash
NOTARY_PROFILE=BashX-Notary ./scripts/build_dmg.sh
```

有 Developer ID 且公证成功后，其他电脑一般可直接双击打开。
