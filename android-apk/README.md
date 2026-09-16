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

当前版本 **3.1**（`versionCode=4`）继续使用这一份外壳的 `com.travelfrog.offline`。
升级时不得改为 `com.frog.offline`：Android 按应用包名隔离数据，改名会使原存档不可见。
必须保持原签名、`file:///android_asset/index.html` 与存储键 `frog.offline.save`，覆盖安装而不卸载。
APK 文件名采用 `TravelFrog-offline-3.1.apk`；文件名不决定应用身份。

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

现有 SDK 可直接编译同一份 Java/Manifest（无需下载 Gradle）：

```bash
# 配置 JAVA_HOME 与 ANDROID_HOME，准备与已安装版本一致的签名密钥/证书
python work/tools/build_android_apk.py
# -> dist/TravelFrog-offline-3.1.apk；签名验证并逐文件核对 APK 资产
```

也可使用 Gradle（Release 产物仍需使用原密钥签名，不能拿 debug 签名覆盖正式包）：

```bash
cd android-apk
# 需要：JDK 17、Android SDK（platform 35 + build-tools）、Gradle 8.7+
gradle :app:assembleRelease        # 或在 Android Studio 里直接 Build
```

- 仓库里**没有** `gradlew` / wrapper jar，所以要先自己装 Gradle（或执行 `gradle wrapper` 生成后再用 `./gradlew`）。
- SDK 路径通过 `ANDROID_HOME` 或 `local.properties` 的 `sdk.dir` 指定（`local.properties` 已被 gitignore）。
- 产物在 `app/build/outputs/apk/`；本仓库的 `.gitignore` 已排除 `app/build/` 与 `*.apk`。

## 三、升级边界

- 本分支的 3.1 升级继续使用本工程；`build_wrapper_apk.py` 的 HTTP 外壳有不同包名及存储地址，不能替代。
- Android Studio 的调试构建可能使用另一张证书；签名不匹配时应修正构建配置，禁止卸载原包规避。
- 版本、签名、覆盖安装和存档验收步骤见 `docs/构建与打包.md`。
