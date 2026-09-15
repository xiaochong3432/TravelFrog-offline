# `android-apk/` —— 用 Android Studio / Gradle 自己出包

这一份是**接手制作的团队**贡献的 Gradle 外壳（提交 `dc7f61f Add Android APK wrapper`），
作为"自带 SDK 的构建路径"保留在仓库里。它和本仓库原有的打包链
（`work/tools/build_wrapper_apk.py` + `sign_apk.py` + `apk_identity.py`）是**两条并行的出包方式**：

| | `android-apk/`（这一份） | `work/tools/build_*.py`（原有） |
|---|---|---|
| 构建 | Gradle + AGP 8.7.3，需要自装 JDK 17 / Android SDK 35 / Gradle 8.7+ | 直接调用本机已装的 `aapt2`/`d8`/`javac`（或 `ANDROID_HOME`/`JAVA_HOME` 指向的 SDK） |
| 加载方式 | `file:///android_asset/index.html`（WebView 直接读资产） | 进程内 `AssetServer` 起回环 HTTP 只读服务 |
| 存档导出/导入 | 无原生桥（只靠 WebView 存储） | 有 `SaveBridge`，悬浮球可导出/导入存档 |
| 包名 | `com.travelfrog.offline` | `com.frog.offline` |

> ⚠️ **包名不同 = 存档不互通**。Android 按包名隔离应用数据，两个包会并存、各有一份存档。
> 想共用存档，需要把这一份的 `applicationId`/`namespace` 对齐到 `com.frog.offline`
> （并且用同一把签名密钥），这属于对原贡献的改动，请先在 Issue/PR 里和作者确认。

## 一、为什么 `web/` 不在仓库里

`app/build.gradle` 里的资产来源是：

```gradle
sourceSets { main { assets.srcDirs = ["../../work/run/web"] } }
```

`work/run/web/` 是**本地生成**的运行时目录：仓库只跟踪其中的页面代码，
客户端的 `resource/`（美术/音频，约 260 MB）由你自己从合法持有的安装包提取 —— 见
`CONTRIBUTING.md` 与 `docs/数据与逆向说明.md`：

```bash
python work/tools/extract_game.py     # 生成 work/run/web/resource/**
python work/tools/patch_game.py       # 幂等离线补丁
python work/tools/bundle_engine.py    # 重建内联引擎（__offline-engine.js）
```

（早期那份提交曾把整个运行时放在仓库根的 `web/` 里，已按仓库规矩移出，见 `CONTRIBUTING.md`。）

## 二、构建

```bash
cd android-apk
# 需要：JDK 17、Android SDK（platform 35 + build-tools）、Gradle 8.7+
gradle :app:assembleRelease        # 或在 Android Studio 里直接 Build
```

- 仓库里**没有** `gradlew` / wrapper jar，所以要先自己装 Gradle（或执行 `gradle wrapper` 生成后再用 `./gradlew`）。
- SDK 路径通过 `ANDROID_HOME` 或 `local.properties` 的 `sdk.dir` 指定（`local.properties` 已被 gitignore）。
- 产物在 `app/build/outputs/apk/`；本仓库的 `.gitignore` 已排除 `app/build/` 与 `*.apk`。

## 三、和主打包链的取舍

- 想要**存档导出/导入**与身份校验（`apk_identity.py`），用主打包链；
- 想要**在 Android Studio 里调试**或自带 SDK 构建，用这一份；
- 两边都请遵守同一把签名密钥，否则老用户无法覆盖安装（Android 要求升级包同一签名）。
