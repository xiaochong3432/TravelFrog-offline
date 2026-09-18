# 贡献说明（请先读这一页）

本仓库是《旅行青蛙·中国之旅》的**离线化改编源码仓库**，不是游戏分发站。
为了让仓库能长期维护、任何人都能 clone 下来继续改，有三条硬规矩。

## 一、仓库里不放什么（硬规矩）

| 不放 | 原因 |
|---|---|
| **客户端原始美术/音频资源**（`resource/`、根目录 `web/`、`work/cdn/`） | 版权属于原权利人，且体积巨大（约 260 MB） |
| **成品包**（`*.apk` / `*.zip` / `*.aab`） | 属于发布物，不随源码走；本仓库也不使用 Releases 分发 |
| **本机绝对路径**（例如"某个盘符 + 用户名目录"、旧工作区根） | 换台机器就崩，且泄露个人信息 |
| **构建产物与临时文件**（`build/`、`__pycache__`、`*.bak`、截图） | 可随时重建 |
| 单文件 **> 5 MB** | 需要时先说清楚为什么，再讨论放哪 |

自查（提交前会由 pre-commit 自动跑一遍）：

```bash
node work/tools/staged_check.js          # 暂存区
node work/tools/staged_check.js --all    # 全部已跟踪文件（CI 也跑这个）
python work/tools/scan_machine_paths.py .        # 机器路径全量扫描
python work/tools/lang_stats.py .               # 语言统计预估
```

一次启用本地钩子：

```bash
git config core.hooksPath .githooks
```

## 二、怎么在本地跑起来（自己准备资源）

仓库**不含**美术/音频，需要从你自己合法持有的游戏安装包提取：

```bash
python work/tools/extract_game.py     # 从 base.apk 提取 assets/game/ 到 work/run/web
python work/tools/patch_game.py       # 应用离线补丁（幂等）
python work/tools/bundle_engine.py    # 重建内联引擎
node   work/tools/engine_test.js      # 所有检查通过，0 failed
cd work/run/web && python -m http.server 8231   # 浏览器打开 http://127.0.0.1:8231/index.html
```

打包见 [构建与打包](docs/构建与打包.md) 和 [安卓打包接口规范](docs/安卓打包接口规范.md)。
当前 3.4（`versionCode=8`）沿用 `com.frog.offline`、原签名和
`http://127.0.0.1:18763/index.html` 加载地址，必须覆盖安装，不得先卸载。
正式入口为 `python work/tools/build_release_apk.py`：从 `work/app/src/` 编译原生外壳，
保留实际旧包的图标与资源并校验升级身份。APK 文件名可以变化，`applicationId` 不得随版本变化。
`com.travelfrog.offline` 与转发包 `com.offline.frog.appx` 的数据与当前包隔离，不可互作升级包。

## 三、协作方式

1. **走 PR**：`main` 开了分支保护，请从 fork 或分支发起 Pull Request，由维护者合并
   （这样 CI 的仓库检查一定会先跑一遍）。
2. 提交信息写清"改了什么、为什么、怎么验证的"；涉及数值/机制的改动，请附上客户端依据
   （函数名 + `main.min.js` 字符偏移）或明确标注为自行设定。
3. 改了引擎就重建内联引擎并跑测试：
   ```bash
   python work/tools/bundle_engine.py && node work/tools/engine_test.js
   ```
4. 想加新玩法：先写规格到 `work/spec/`，再实现，再补单测与页面探针（见 `docs/测试与验收.md`、`docs/目的地系统.md` 的写法示例）。

## 四、致谢

本仓库包含多位贡献者的成果，历史提交里保留了每个人的记录；曾经的整包提交（V3 运行时、
Android Gradle 外壳）已按上述规矩从当前版本移出，但**贡献记录保留在 git 历史中**。
