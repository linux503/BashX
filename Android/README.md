# BashX Android（Galaxy Z Fold 6）

Android 客户端，功能 / 设计 / 配置对齐 iOS：

- 首页连接、节点、订阅、设置
- 智能规则 v15、DNS、测速、策略组
- `mixed-port 17890` / `controller 127.0.0.1:19090` / TUN `198.18.0.1/16`
- 外屏：底栏单栏（约 6.3" 封面屏）
- 内屏：左侧导航 + 首页 | 节点/订阅/设置 双栏

## 编译

```bash
# 1) 内核 AAR（需要 Go + Android NDK）
bash scripts/build_mihomo_android.sh

# 2) App
cd Android
./gradlew :app:assembleDebug
```

APK：`Android/app/build/outputs/apk/debug/app-debug.apk`

用 Android Studio 打开 `Android/`，选 Fold 6 / `SM-F956` 真机或折叠屏模拟器安装。

未编译内核时，订阅 / 节点 / 测速 / 配置仍可用；点连接会提示先跑 `build_mihomo_android.sh`。
