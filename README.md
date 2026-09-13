# 旅行青蛙·中国之旅 —— 离线单机版

把已停运的《旅行青蛙·中国之旅》（国服 Egret H5 客户端）改造成**纯本地、无服务端、无广告、无充值**的单机游戏。
客户端一行不改即可运行：规则引擎内联进游戏页面，替换掉原有的网络层。

- **244 条客户端协议已实现 217 条**；剩下 27 条是客户端单向发出的推送/上报，服务端无需回包
- 数值与规则以客户端自身逻辑为准绳：60 张数据表从客户端加密包解出，另加原版调参表与归档的地图数据
- 所有自行设定的数值与换算都逐条列出（见 `docs/设计取舍与自定数值.md`）
- 纯离线：不联网、不请求任何服务端、不包含广告与充值逻辑

## 目录

```
docs/               开发者文档（先读这里）
work/run/engine/    游戏服务端全部逻辑（引擎 + 协议 + 数据表）
work/run/server/    路线 A：本地 WebSocket 服务端（仅调试用）
work/run/web/       游戏网页运行时（客户端资源 + 离线补丁 + 内联引擎）
work/tools/         数据解密、打包、验收、单测等工具
work/spec/          字段级逆向规格与解出的权威数据表
work/notes/         专题发现记录
work/pristine/      原版客户端 JS 的独立副本（补丁与比对用）
dist/               发行说明、启动器、签名证书（APK 与压缩包走 Releases）
```

## 两条运行路线

| 路线 | 用途 | 怎么跑 |
|---|---|---|
| **B（发行方式）** | 纯前端，无需任何服务端 | 用静态服务器托管 `work/run/web/`，打开 `index.html`。引擎以 `work/run/web/__offline-engine.js` 内联进页面，接管 `core.SocketManage` |
| **A（调试）** | 本地联调、抓协议日志 | `node work/run/server/main.js`，浏览器访问它打印的地址 |

> 浏览器不允许 `file://` 页面读取本地文件，所以必须经一个静态服务器打开（任何静态服务器均可）。

## 快速开始（开发者）

```bash
# 1) 引擎单元测试（最快的一环，改逻辑先跑它）
node work/tools/engine_test.js                 # 期望 346 passed, 0 failed
#    未包含客户端美术资源时（见下节），会有 1 条用例标记 SKIP，属正常

# 2) 在浏览器里真跑（headless Edge 分步驱动）
cd work/run/web && python -m http.server 8231  # 另开一个终端
node work/tools/cdp_drive.js --url http://127.0.0.1:8231/index.html --fresh --wait 9000 --step shot:shot.png

# 3) 改完引擎必须重建内联引擎，否则页面里跑的还是旧代码
python work/tools/bundle_engine.py

# 4) 出包
python work/tools/build_pc_zip.py              # PC 解压即玩包
python work/tools/build_wrapper_apk.py         # 安卓外壳 APK（未签名）
python work/tools/sign_apk.py --in <unsigned.apk> --out <signed.apk>
python work/tools/apk_identity.py              # 期望 RESULT: OK
```

## 关于游戏资源

本仓库默认**不包含客户端的原始美术/音频资源**（`work/run/web/resource/`，约 260 MB）。
这些资源属于原权利人，请从你合法持有的游戏安装包中自行提取：

```bash
python work/tools/extract_game.py     # 从 base.apk 提取 assets/game/ 到 work/run/web
python work/tools/patch_game.py       # 应用离线补丁（幂等，从原始 main.min.js 出发）
python work/tools/bundle_engine.py    # 重建内联引擎
```

需要一份自带资源的完整副本时，可用
`python work/tools/stage_repo.py --with-assets` 重新生成入库目录。
详见 `docs/数据与逆向说明.md`。

## 文档索引

| 文档 | 内容 |
|---|---|
| `docs/玩法与实现状态.md` | 已实现的全部玩法、协议覆盖率、诚实的功能边界 |
| `docs/架构.md` | 两条路途线的接缝、引擎接口、数据文件与浏览器内联机制 |
| `docs/构建与打包.md` | 构建链、打包命令、目录布局、发行注意事项 |
| `docs/测试与验收.md` | 四层验收体系、全部测试入口与期望结果 |
| `docs/数据与逆向说明.md` | 数据表怎么来的、加密包怎么解、资源如何重建、CDN 归档 |
| `docs/目的地系统.md` | 目的地/区域系统的数据依据、算法与判定规则 |
| `docs/设计取舍与自定数值.md` | 所有【自设计】的数值与口径，以及未实现项的原因 |
| `docs/开发历史.md` | 按时间顺序的改动记录（问题 → 处理 → 验证） |
| `docs/文件清单.md` | 仓库内每个目录/关键文件的用途，哪些是生成物 |
| `docs/game-data-reference.md` | 游戏数据结构参考（表、字段、取值） |
| `docs/权利归属与使用限制.md` | 权利声明与使用限制 |

## 权利归属

游戏原作《旅行青蛙》/ 旅かえる © Hit-Point Co., Ltd.；国服《旅行青蛙·中国之旅》由灵犀互娱/阿里发行。
本项目为**个人非商业性的保存与研究项目**，不含官方服务端内容，不提供联网功能，不用于任何商业用途。
游戏内的美术、音乐、数据表均来自原客户端；若权利人提出异议，将立即下架相关内容。
完整声明见 `NOTICE.txt` 与 `docs/权利归属与使用限制.md`。
