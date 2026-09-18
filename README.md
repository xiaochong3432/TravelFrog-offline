# 旅行青蛙·中国之旅 —— 离线单机版

把已停运的《旅行青蛙·中国之旅》（国服 Egret H5 客户端）改造成**纯本地、无服务端、无广告、无充值**的单机游戏。
规则引擎内联进游戏页面，替换掉原有的网络层；客户端修复由可重放补丁维护。

当前版本 **3.4**（`versionCode=8`）沿用原路线 **`com.frog.offline`**、原签名和 `http://127.0.0.1:18763/index.html` 存档地址。本版集中修复玩家反馈中的照片收取、邻居回礼与邀约、堆肥、手工品、家具、信箱/场景显示、相册回收站、工作台库存刷新和购买页布局。构建命令：`python work/tools/build_release_apk.py`（先设置 `FROG_UPGRADE_FROM` 为实际发布的旧 APK）。`com.travelfrog.offline` 属于另一个包，不能直接覆盖或自动读取其存档。详见 [3.4 修复记录](docs/修复记录-3.4.md)、[构建与打包](docs/构建与打包.md) 和 [安卓打包接口规范](docs/安卓打包接口规范.md)。

- **244 条客户端协议已实现 217 条**；剩下 27 条是客户端单向发出的推送/上报，服务端无需回包
- 数值与规则以客户端自身逻辑为准绳：60 张数据表从客户端加密包解出，另加原版调参表与归档的地图数据
- 所有自行设定的数值与换算都逐条列出（见 `docs/设计取舍与自定数值.md`）
- 纯离线：不联网、不请求任何服务端、不包含广告与充值逻辑

## 目录

```
docs/               开发者文档（先读这里）
work/app/src/      安卓外壳 Java 源码（本地 HTTP 服务、WebView 与存档桥）
work/run/engine/    游戏服务端全部逻辑（引擎 + 协议 + 数据表）
work/run/server/    路线 A：本地 WebSocket 服务端（仅调试用）
work/run/web/       游戏网页运行时（页面代码 + 离线补丁 + 内联引擎；resource/ 本地生成）
work/tools/         数据解密、打包、验收、单测等工具
work/spec/          字段级逆向规格与解出的权威数据表
work/notes/         专题发现记录
work/pristine/      原版客户端 JS 的独立副本（补丁与比对用）
android-apk/        com.travelfrog.offline 开发路线参考（不是当前发布入口）
dist/               玩家说明书、启动器脚本、签名证书（**不含** APK / 压缩包）
```

> **仓库里有什么、没有什么**：本仓库只放**代码 + 数据表 + 规格 + 文档**。
> **不含**客户端原始美术/音频（`resource/`，约 260 MB）、**不含**成品包（APK / 压缩包），
> **也不使用 GitHub Releases 分发**。资源请从你自己合法持有的游戏安装包提取（见下节），
> 成品请从项目自身的发布渠道获取或自行构建。规矩与自查命令见 `CONTRIBUTING.md`。

## 两条运行路线

| 路线 | 用途 | 怎么跑 |
|---|---|---|
| **B（发行方式）** | 纯前端，无需任何服务端 | 用静态服务器托管 `work/run/web/`，打开 `index.html`。引擎以 `work/run/web/__offline-engine.js` 内联进页面，接管 `core.SocketManage` |
| **A（调试）** | 本地联调、抓协议日志 | `node work/run/server/main.js`，浏览器访问它打印的地址 |

> 浏览器不允许 `file://` 页面读取本地文件，所以必须经一个静态服务器打开（任何静态服务器均可）。

## 快速开始（开发者）

```bash
# 1) 引擎单元测试（最快的一环，改逻辑先跑它）
node work/tools/engine_test.js                 # 所有检查通过，0 failed
#    未包含客户端美术资源时（见下节），会有 1 条用例标记 SKIP，属正常

# 2) 在浏览器里真跑（headless Edge 分步驱动）
cd work/run/web && python -m http.server 8231  # 另开一个终端
node work/tools/cdp_drive.js --url http://127.0.0.1:8231/index.html --fresh --wait 9000 --step shot:shot.png

# 3) 改完引擎必须重建内联引擎，否则页面里跑的还是旧代码
python work/tools/bundle_engine.py

# 4) 出包
python work/tools/build_pc_zip.py              # PC 解压即玩包
# 设置 FROG_UPGRADE_FROM 为实际发布的旧 com.frog.offline APK 后：
python work/tools/build_release_apk.py         # 3.4 安卓包，编译原生源码并沿用原签名
python work/tools/apk_identity.py --apk dist/TravelFrog-offline-3.4.apk # 期望 RESULT: OK
```

## 关于游戏资源

本仓库**不包含**客户端的原始美术/音频资源（`resource/`，约 260 MB），
这些资源属于原权利人，请从你合法持有的游戏安装包中自行提取：

```bash
python work/tools/extract_game.py     # 从 base.apk 提取 assets/game/ 到 work/run/web
python work/tools/patch_game.py       # 应用离线补丁（幂等，从原始 main.min.js 出发）
python work/tools/bundle_engine.py    # 重建内联引擎
```

跑完这三步，`work/run/web/` 就是一份可运行的完整运行时（静态服务器打开即可）。
详见 `docs/数据与逆向说明.md`。需要自带资源的完整副本时可用
`python work/tools/stage_repo.py --with-assets` 生成到工作区之外，**不要提交进仓库**。

## 成品包从哪里来

仓库**不提供**成品包，也**不使用 GitHub Releases**。成品（安卓 APK / PC 解压即玩包）
由项目自身的发布渠道提供；需要自己出包时按 `docs/构建与打包.md` 构建。
3.4 成品为 `dist/TravelFrog-offline-3.4.apk`，包名 `com.frog.offline`。版本由 `work/release.json` 管理。
用户提供的 V3 实包为 `com.travelfrog.offline`，与原路线不兼容；3.1 已恢复原路线，3.4 继续沿用。已使用该 V3 或开发分支的玩家需先导出再导入存档，不能直接卸载。发布前始终核对目标旧 APK 的包名、签名和存储地址。

## 可移植性

所有脚本都**按自身位置推导仓库根**，不写死任何绝对路径，因此仓库放在哪里、
在 Windows / Linux / macOS 上都能直接运行。需要外部工具链时（只有重新打包 APK、
编译 PC 启动器、跑无头浏览器验收才需要）用环境变量指过去即可：

```bash
export JAVA_HOME=/path/to/jdk17            # 或 FROG_JAVA_HOME
export ANDROID_HOME=/path/to/android-sdk   # build-tools 与 platforms 都从它下面找
export FROG_BROWSER=/path/to/chrome        # 无头浏览器（默认自动查找 Edge/Chrome）
```

缺什么时脚本会打印对应的变量名。详见 `docs/构建与打包.md` 的「可移植性」一节。

## 文档索引

| 文档 | 内容 |
|---|---|
| `docs/修复记录-3.4.md` | v4 前最后一个准备版本的修复清单、行为边界与发行验收 |
| `docs/玩法与实现状态.md` | 已实现的全部玩法、协议覆盖率、诚实的功能边界 |
| `docs/架构.md` | 两条路途线的接缝、引擎接口、数据文件与浏览器内联机制 |
| `docs/构建与打包.md` | 构建链、打包命令、目录布局、发行注意事项 |
| `docs/安卓打包接口规范.md` | 原生桥接口、存档来源、端口与覆盖升级验收要求 |
| `docs/照片图层修订.md` | 照片图层修订依据、视觉验收与回归方法 |
| `docs/测试与验收.md` | 四层验收体系、全部测试入口与期望结果 |
| `docs/数据与逆向说明.md` | 数据表怎么来的、加密包怎么解、资源如何重建、CDN 归档 |
| `docs/目的地系统.md` | 目的地/区域系统的数据依据、算法与判定规则 |
| `docs/设计取舍与自定数值.md` | 所有【自设计】的数值与口径，以及未实现项的原因 |
| `docs/开发历史.md` | 按时间顺序的改动记录（问题 → 处理 → 验证） |
| `docs/文件清单.md` | 仓库内每个目录/关键文件的用途，哪些是生成物 |
| `docs/game-data-reference.md` | 游戏数据结构参考（表、字段、取值） |
| `docs/GitHub连接问题.md` | 国内网络下推送失败的原因诊断与四种解法（SSH/443、hosts、代理、重试脚本） |
| `docs/权利归属与使用限制.md` | 权利声明与使用限制 |

## 权利归属

游戏原作《旅行青蛙》/ 旅かえる © Hit-Point Co., Ltd.；国服《旅行青蛙·中国之旅》由灵犀互娱/阿里发行。
本项目为**个人非商业性的保存与研究项目**，不含官方服务端内容，不提供联网功能，不用于任何商业用途。
游戏内的美术、音乐、数据表均来自原客户端；若权利人提出异议，将立即下架相关内容。
完整声明见 `NOTICE.txt` 与 `docs/权利归属与使用限制.md`。
