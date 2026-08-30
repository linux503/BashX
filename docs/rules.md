# BashX 分流规则

版本：**v19** · 更新：2026-08-28

## 策略说明

参考 [LingJingMaster/Shadowrocket-Rules](https://github.com/LingJingMaster/Shadowrocket-Rules)，结合 Clash/mihomo 策略组（Mac / iOS / Android 共用）：

| 优先级 | 服务 | 默认策略组 |
|--------|------|------------|
| 1 | LAN / 私网 | DIRECT |
| 2 | HTTPDNS 防泄露 | REJECT |
| 3 | 国内常用 / GEOSITE cn | DIRECT |
| 4 | Telegram | TELEGRAM / PROXY |
| 5 | Google / YouTube / Gemini | **GOOGLE** → 默认 **JP**（可选 HK / GOOGLE-AUTO） |
| 6 | AI（ChatGPT / Claude / Cursor 等） | **AI** → 偏好 **US** |
| 7 | GitHub / Microsoft | PROXY |
| 8 | 汇丰香港 | **HK** |
| 9 | 其他香港银行 | DIRECT |
| 10 | 券商（富途 / 长桥 / IBKR 等） | **HK** |
| 11 | Apple Push | PROXY |
| 12 | 其余 Apple / iCloud | DIRECT |
| 13 | 广告 | REJECT |
| 14 | GEOIP CN | DIRECT |
| 15 | 漏网之鱼 | PROXY / MATCH |

策略组：`JP` / `HK` / `US` / `TW`（url-test）、`GOOGLE`（select）、`GOOGLE-AUTO`、`AI` 及 `CURSOR` / `OPENAI` / `ANTHROPIC`。

App 内开启 **视频广告过滤** 时，会额外合并 `VideoAdBlock` 域名 REJECT。

## 下载 / 引用

| 用途 | 链接 |
|------|------|
| 纯文本规则 | [bashx-smart-rules.txt](../Resources/rules/bashx-smart-rules.txt) |
| 元数据 | [manifest.json](../Resources/rules/manifest.json) |
| 导出包 | `dist/rules/`（运行 `scripts/export_rules.sh`） |
| jsDelivr CDN | `https://cdn.jsdelivr.net/gh/BashX/BashX@main/Resources/rules/bashx-smart-rules.txt` |

Clash 订阅式引用示例：

```yaml
rules:
  - RULE-SET,https://cdn.jsdelivr.net/gh/BashX/BashX@main/Resources/rules/bashx-smart-rules.txt,PROXY
```

或面板 → **规则** → **应用智能规则 v19** / iOS「恢复智能规则」一键恢复。

## 本地路径

```
~/Library/Application Support/BashX/rules.txt
```

App 启动时会自动导出最新 bundled 规则到此文件。

## 完整规则列表（v6）

```
# BashX Smart Rules v6
# 参考 ACL4SSR / Clash Verge / ClashX Pro：国内直连 + 广告拦截 + 国外智能代理
# 视频域名广告见 VideoAdBlock（App 内可选合并）

# ========== LAN / 本地 ==========
DOMAIN-SUFFIX,local,REJECT
DOMAIN-SUFFIX,localhost,DIRECT
DOMAIN-SUFFIX,lan,DIRECT
DOMAIN-KEYWORD,lan,DIRECT
IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
IP-CIDR,169.254.0.0/16,DIRECT,no-resolve
IP-CIDR,224.0.0.0/4,DIRECT,no-resolve
IP-CIDR6,::1/128,DIRECT,no-resolve
IP-CIDR6,fc00::/7,DIRECT,no-resolve
IP-CIDR6,fe80::/10,DIRECT,no-resolve

# ========== 系统检测 / NTP / 推送（勿动 gstatic 主域） ==========
DOMAIN,captive.apple.com,DIRECT
DOMAIN,connectivitycheck.gstatic.com,DIRECT
DOMAIN,connectivitycheck.android.com,DIRECT
DOMAIN,www.msftconnecttest.com,DIRECT
DOMAIN,msftconnecttest.com,DIRECT
DOMAIN,detectportal.firefox.com,DIRECT
DOMAIN-SUFFIX,push.apple.com,DIRECT
DOMAIN-SUFFIX,push-apple.com.akadns.net,DIRECT
DOMAIN-SUFFIX,time.apple.com,DIRECT
DOMAIN-SUFFIX,ntp.org,DIRECT
DOMAIN-SUFFIX,pool.ntp.org,DIRECT
DOMAIN-SUFFIX,cn.pool.ntp.org,DIRECT

# ========== 即时通讯（GEOSITE 不够时补进程/IP） ==========
PROCESS-NAME,Telegram,PROXY
PROCESS-NAME,org.telegram.desktop,PROXY
PROCESS-NAME,Discord,PROXY
PROCESS-NAME,Discord Canary,PROXY
PROCESS-NAME,Slack,PROXY
PROCESS-NAME,Signal,PROXY
GEOIP,telegram,PROXY,no-resolve

# ========== 国内常用域名（GeoSite 命中前的快速路径） ==========
DOMAIN-SUFFIX,cn,DIRECT
DOMAIN-SUFFIX,baidu.com,DIRECT
DOMAIN-SUFFIX,bdstatic.com,DIRECT
DOMAIN-SUFFIX,qq.com,DIRECT
DOMAIN-SUFFIX,gtimg.com,DIRECT
DOMAIN-SUFFIX,qpic.cn,DIRECT
DOMAIN-SUFFIX,tencent.com,DIRECT
DOMAIN-SUFFIX,weixin.com,DIRECT
DOMAIN-SUFFIX,wechat.com,DIRECT
DOMAIN-SUFFIX,alibaba.com,DIRECT
DOMAIN-SUFFIX,alicdn.com,DIRECT
DOMAIN-SUFFIX,aliyuncs.com,DIRECT
DOMAIN-SUFFIX,aliyun.com,DIRECT
DOMAIN-SUFFIX,taobao.com,DIRECT
DOMAIN-SUFFIX,tmall.com,DIRECT
DOMAIN-SUFFIX,alipay.com,DIRECT
DOMAIN-SUFFIX,alipayobjects.com,DIRECT
DOMAIN-SUFFIX,jd.com,DIRECT
DOMAIN-SUFFIX,360buyimg.com,DIRECT
DOMAIN-SUFFIX,bilibili.com,DIRECT
DOMAIN-SUFFIX,hdslb.com,DIRECT
DOMAIN-SUFFIX,zhihu.com,DIRECT
DOMAIN-SUFFIX,zhimg.com,DIRECT
DOMAIN-SUFFIX,163.com,DIRECT
DOMAIN-SUFFIX,126.com,DIRECT
DOMAIN-SUFFIX,126.net,DIRECT
DOMAIN-SUFFIX,127.net,DIRECT
DOMAIN-SUFFIX,netease.com,DIRECT
DOMAIN-SUFFIX,iqiyi.com,DIRECT
DOMAIN-SUFFIX,iqiyipic.com,DIRECT
DOMAIN-SUFFIX,youku.com,DIRECT
DOMAIN-SUFFIX,ykimg.com,DIRECT
DOMAIN-SUFFIX,douyin.com,DIRECT
DOMAIN-SUFFIX,toutiao.com,DIRECT
DOMAIN-SUFFIX,bytedance.com,DIRECT
DOMAIN-SUFFIX,feishu.cn,DIRECT
DOMAIN-SUFFIX,larkoffice.com,DIRECT
DOMAIN-SUFFIX,dingtalk.com,DIRECT
DOMAIN-SUFFIX,douban.com,DIRECT
DOMAIN-SUFFIX,meituan.com,DIRECT
DOMAIN-SUFFIX,dianping.com,DIRECT
DOMAIN-SUFFIX,ctrip.com,DIRECT
DOMAIN-SUFFIX,trip.com,DIRECT
DOMAIN-SUFFIX,12306.cn,DIRECT
DOMAIN-SUFFIX,mi.com,DIRECT
DOMAIN-SUFFIX,xiaomi.com,DIRECT
DOMAIN-SUFFIX,huawei.com,DIRECT
DOMAIN-SUFFIX,hicloud.com,DIRECT
DOMAIN-SUFFIX,oppo.com,DIRECT
DOMAIN-SUFFIX,vivo.com,DIRECT
DOMAIN-SUFFIX,suning.com,DIRECT
DOMAIN-SUFFIX,pinduoduo.com,DIRECT
DOMAIN-SUFFIX,yangkeduo.com,DIRECT
DOMAIN-SUFFIX,kuaishou.com,DIRECT
DOMAIN-SUFFIX,ximalaya.com,DIRECT
DOMAIN-SUFFIX,uc.cn,DIRECT
DOMAIN-SUFFIX,sogou.com,DIRECT
DOMAIN-SUFFIX,sohu.com,DIRECT
DOMAIN-SUFFIX,sina.com.cn,DIRECT
DOMAIN-SUFFIX,weibo.com,DIRECT
DOMAIN-SUFFIX,iq.com,DIRECT
DOMAIN-SUFFIX,cctv.com,DIRECT
DOMAIN-SUFFIX,gov.cn,DIRECT
DOMAIN-SUFFIX,windowsupdate.com,DIRECT
DOMAIN-SUFFIX,download.windowsupdate.com,DIRECT
DOMAIN-SUFFIX,wustat.windows.com,DIRECT

# ========== Apple / Microsoft 中国 ==========
DOMAIN-SUFFIX,apple.com.cn,DIRECT
DOMAIN-SUFFIX,icloud.com.cn,DIRECT
DOMAIN-SUFFIX,cdn-apple.com,DIRECT
DOMAIN-SUFFIX,mzstatic.com,DIRECT
DOMAIN-SUFFIX,officechina.com,DIRECT

# ========== GeoSite 直连 ==========
GEOSITE,category-ads-all,REJECT
GEOSITE,category-porn,REJECT
GEOSITE,private,DIRECT
GEOSITE,cn,DIRECT
GEOSITE,apple@cn,DIRECT
GEOSITE,microsoft@cn,DIRECT
GEOSITE,steam@cn,DIRECT
GEOSITE,category-games@cn,DIRECT

# ========== 流媒体 / 社交 / AI / 开发（走代理） ==========
GEOSITE,google,PROXY
GEOSITE,youtube,PROXY
GEOSITE,github,PROXY
GEOSITE,gitlab,PROXY
GEOSITE,twitter,PROXY
GEOSITE,facebook,PROXY
GEOSITE,instagram,PROXY
GEOSITE,whatsapp,PROXY
GEOSITE,telegram,PROXY
GEOSITE,discord,PROXY
GEOSITE,signal,PROXY
GEOSITE,linkedin,PROXY
GEOSITE,reddit,PROXY
GEOSITE,tiktok,PROXY
GEOSITE,netflix,PROXY
GEOSITE,disney,PROXY
GEOSITE,hbo,PROXY
GEOSITE,spotify,PROXY
GEOSITE,twitch,PROXY
GEOSITE,bahamut,PROXY
GEOSITE,pixiv,PROXY
GEOSITE,openai,PROXY
GEOSITE,anthropic,PROXY
GEOSITE,huggingface,PROXY
GEOSITE,category-ai-!cn,PROXY
GEOSITE,category-social-media-!cn,PROXY
GEOSITE,category-media-!cn,PROXY
GEOSITE,category-games-!cn,PROXY
GEOSITE,category-dev,PROXY
GEOSITE,category-forums,PROXY
GEOSITE,category-scholar-!cn,PROXY
GEOSITE,stackoverflow,PROXY
GEOSITE,figma,PROXY
GEOSITE,notion,PROXY
GEOSITE,slack,PROXY
GEOSITE,medium,PROXY
GEOSITE,dropbox,PROXY
GEOSITE,zoom,PROXY
GEOSITE,canva,PROXY
GEOSITE,vercel,PROXY
GEOSITE,netlify,PROXY
GEOSITE,bbc,PROXY
GEOSITE,cnn,PROXY
GEOSITE,nytimes,PROXY
GEOSITE,blizzard,PROXY
GEOSITE,nintendo,PROXY
GEOSITE,sony,PROXY
GEOSITE,ubi,PROXY
GEOSITE,category-emby,PROXY
GEOSITE,category-speedtest,PROXY
GEOSITE,category-crypto-!cn,PROXY
GEOSITE,category-vpnservices,PROXY
GEOSITE,category-entertainment-!cn,PROXY
GEOSITE,amazon,PROXY
GEOSITE,aws,PROXY
GEOSITE,cloudflare,PROXY
GEOSITE,paypal,PROXY
GEOSITE,binance,PROXY
GEOSITE,onedrive,PROXY
GEOSITE,epicgames,PROXY
GEOSITE,steam,PROXY
GEOSITE,microsoft,PROXY
GEOSITE,apple,PROXY

# ========== GFW / 非中国 IP 段 ==========
GEOSITE,gfw,PROXY
GEOSITE,greatfire,PROXY
GEOSITE,geolocation-!cn,PROXY
GEOSITE,tld-!cn,PROXY

# ========== GeoIP 兜底 ==========
GEOIP,CN,DIRECT,no-resolve
GEOIP,PRIVATE,DIRECT,no-resolve

# ========== 默认 ==========
MATCH,PROXY
```

## 注意事项

- **不使用** `category-ads-cn`（mihomo 会崩溃）
- **不包含** `www.gstatic.com` 直连（会导致 Google 异常）
- `.local` 用 REJECT 而非 DIRECT，避免 mDNS 解析失败刷屏日志
- YouTube **片中广告**与正片同 CDN，代理层无法完全去除
