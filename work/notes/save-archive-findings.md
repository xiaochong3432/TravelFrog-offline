# 玩家导出包 `测试用存档.tar.gz` 分析（结论：**不含存档**，但含最后一批官方内容）

分析对象：`测试用存档.tar.gz`（66.6 MB，1969 个文件 / 解包 87.4 MB）
来源：某位老玩家按小红书笔记导出的**安卓应用私有数据目录**转存（uid `u0_a42`），
包名 `com.ali.croak.nearme.gamecenter`（OPPO 渠道包，与本项目 `base.apk` 同一包名/同一条发布线）。

## 一、为什么"不能转成我们的存档"——因为里面没有存档

1. **WebView 的 localStorage（Chrome leveldb）是空的**
   `app_webview/Default/Local Storage/leveldb/`：`000003.log` = 0 字节，
   只有 41 字节的 `MANIFEST-000001`，`LOG` 里两次 "Recovering log #3" —— 一个键都没有。
2. **游戏真正落地到本地的状态在 `shared_prefs/localhost.xml`（73 KB，26 个键）**
   EjoySDK 把 WebView 的 localStorage 映射到这份 SharedPreferences。
   其中只有这些：
   - `clover_pos_1 … clover_pos_20`：庭院 20 个三叶草槽位的**显示坐标 + 生成时间**
     （例：`{"x":348.97,"y":11.21,"key":1788947209}`，key = `last_harvest`）
   - `<账号md5>@clover_harvest_resend` = `[]`（收获未确认时的客户端重发队列，空）
   - `res_record.json`（41 KB）：资源 md5 记录（防篡改/下载记录，不是进度）
   - `EjoySDKAnnounceMentP10528`、`@anns_read_*`、`@notice_open`、`@notice_click_*`：公告与已读标记
   - `enter_agree_check` = `check`
3. **全包字节级扫描**：`guideStep`、`clientSettings`、`achieves`、`bag_completed`、
   `have_fur`、`hall_hello`、`client_load_all_info`、`clover_update`、`StartCloverPoint`
   只出现在**缓存的客户端 JS**（`1083/js/main.min.js`）里，没有任何一处是数据。
   `frog.offline`（我们离线版的存档键）0 命中。
4. **架构原因（客户端本身就没有本地存档）**：客户端 JS 里唯一的游戏侧本地写入是
   ```js
   var p = JSON.parse(core.String.getCookieGlobal("clover_pos_" + l.clover_id) || "{}");
   if (null != p.key && p.key == l.last_harvest) { u.x = p.x; u.y = p.y; }
   else { …; core.String.setCookieGlobal("clover_pos_" + l.clover_id, JSON.stringify(p)); }
   ```
   即"庭院三叶草的摆放位置"而已。昵称、三叶草数量、背包、家具、相册、特产、称号、
   图鉴、任务进度全部在**官方服务器**上，客户端从不落盘。
5. 其余 128 个 `databases/*`（NearMeSTAT、adp_sdk、TCG_* 等）与 57 个 `shared_prefs/*`
   全是 OPPO/Ejoy/友盟/崩溃 SDK 的图书账，无任何游戏进度表。
   包内还留有导出者的账号标识（OPPO `ssoid` / `roleid`），属个人信息，外传前需注意。

**结论：没有任何可以映射进我们存档结构（`frog.offline.save`）的数据。**
唯一可迁移的是那 20 个槽位的坐标 + 时间戳（纯摆放外观），
而且我们引擎会按自己的 `last_harvest` 重新推送，默认根本用不上。

> 补充：如果目标是"保住这位玩家的蛙"，那他的进度此刻仍存在阿里服务器上
> （停服 2026-12-08 18:00 才清数据），本包无法替代。

## 二、这个包真正值钱的地方：**最后一批官方内容（2024-03 → 2026-02）**

`files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/`
是这台设备当年从官方 CDN 拉取的**增量补丁缓存**，版本号 `1073`→`1088`，
下载时间 2026-09-09 ~ 09-12（停服前），`Last-Modified` 覆盖：

| 版本目录 | 官方更新时间 | 文件数 |
|---|---|---|
| 1073 | 2024-03-18 | 216 |
| 1074 | 2024-03-27 | 21 |
| 1075 | 2024-04-10 | 1 |
| 1076 | 2024-04-24 | 24 |
| 1077 | 2024-05-15 | 13 |
| 1078 | 2024-05-29 | 29 |
| 1079 | 2024-07-31 | 50 |
| 1080 | 2024-12-04 | 61 |
| 1081 | 2025-01-15 | 11 |
| 1082 | 2025-03-05 | 1 |
| 1083 | 2025-04-11 | 3 |
| 1084 | 2025-05-21 | 2 |
| 1085 | 2025-06-26 | 7 |
| 1086 | 2025-09-29 | 6 |
| 1087 | 2025-12-24 | 6 |
| 1088 | 2026-02-10 | 2 |

### 2.1 数据表：`1088/resource/China/eab/config.eab`（2,232,684 B，我们的是 1,780,884 B）
用 `work/tools/eab_decrypt.py`（XXTEA，key `ejoyassetbundle`，`y_init=v0`）解出 **61 张表**（我们是 60 张）：

| 表 | 我们 | 1088 | 新增 |
|---|---|---|---|
| furnitureData | 324 | 405 | **+81** |
| furnitureShopData | 172 | 290 | **+118** |
| benchData | 327 | 410 | **+83** |
| Picture | 351 | 382 | **+31** |
| PictureTag | 200 | 221 | **+21** |
| shopData | 66 | 89 | **+23** |
| resources（清单） | 1270 | 1353 | +83 |
| Item | 411 | 420 | +9 |
| Collection | 62 | 64 | +2 |
| Achieve | 101 | 103 | +2 |
| Specialty | 64 | 66 | +2 |
| GoalNumber | 38 | 40 | +2 |
| furnitureCommon | 40 | 43 | +3 |
| decoration / compostData / pocketData | 31/15/6 | 32/16/7 | 各 +1 |
| **encytravel** | — | 2 | **全新表** |

内容举例（都是官方行，不是我们造的）：
- **3 套完整家具**（每套 27 件，共 81 件）：
  `xw11 甲辰迎春`(2101-2127)、`xw12 夏凉`(2201-2227)、`xw13 彩陶庆典`(2301-2327)
  —— 我们此前只有 xw10/xw101（参考项目的 A 档移植）。
- **31 张新明信片**：Goal 类 内蒙古 ×3 / 新疆 ×3 / 重庆3 / 青岛3 / 贵州7 / 西安4 / 郑州1 / 北京6；
  Unique 类 松鼠/狗/灯笼/凤眼莲/蟹味/夏至 ×2/中秋2/周年2/各月 `monthN_3`。
- **相册扩容 36–56**（shopData 66–88，价格 1000–3000 三叶草）+ 动态相框 4/5。
- **新特产**：沙果(3039)、馕(3040) → 西北地区；**新典藏**：马头琴(62)、和田玉(63)；
  **新称号**：内蒙美食家、新疆美食家；**新装饰**：君子兰；点击特效 ×4（青蛙/壁虎/刺猬/萤火虫）。
- **`encytravel`**：百科"旅行"页文案（食物/道具的说明，如"旅行商人概率刷新""森之国度联动""周年活动特有食物"）。

### 2.2 资源文件：缓存里 453 条不同路径
与我们 `work/run/web` 比对：**48 条相同 / 102 条更新 / 303 条全新**，更新+新增合计 **48.34 MB**：

| 目录 | 相同 | 更新 | 全新 | 体积 |
|---|---|---|---|---|
| `images/Picture`（明信片图） | 2 | 16 | 84 | 11.19 MB |
| `images/Scene`（场景/日历/家具图） | 41 | 58 | 133 | 7.33 MB |
| `sheet/icon2_sheet*`、`icon3_sheet*`、`furniture_xw1*` | 0 | 4 | 1 | 14.0 MB |
| `animation/gif_photo`（gif_4 / gif_5 动态照片） | 0 | 0 | 63 | 4.03 MB |
| `eab/config.eab`、`reward.eab`、`system.eab`、`preload.eab` | 1 | 3 | 0 | 3.4 MB |
| `js/main.min.js`、`js/default.thm.js` | 0 | 2 | 0 | 2.6 MB |
| `animation/furniture`（xw10/xw11/xw12 动效） | 3 | 0 | 9 | 0.07 MB |
| `animation/game_egg`（egg_6_jiaoshui、egg_7_linyu） | 0 | 0 | 6 | 0.47 MB |

客户端 JS 本身：`1083/js/main.min.js` = 1,341,100 B（我们 1,315,383 B）。
命令集合与功能标记**基本一致**（`museumday/springcard/greetcard/partycake/koto/compass` 计数相同），
只多了 `furniture_replace_flowerpot`。

### 2.3 顺带确认的一件事
**"探秘东山岛"从未进过客户端**：在 1088（2026-02）这份最后的官方内容里，
`东山/南门/流星/野营/探秘/dongshan/nanmen/liuxing/yeying` 在缓存路径与客户端 JS 中**全部 0 命中**。
这独立印证了本项目此前的判断（内容只到 2024-08 四馆联动那一批）。

## 二·补：两个额外发现（都可直接利用）

1. **`1088/patch.json` 是完整的官方资源清单**：4168 条，键=资源路径，值=`{"0": 版本目录, "1": md5, "2": 大小}`，
   URL 规则写在 `__url__` 里：`https://ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/<版本目录>/<路径>`。
   也就是说**整个最终版资源树（4168 个文件）是可枚举、可下载的**，玩家缓存里那 453 条只是其中一部分。
2. **官方 CDN 与活动页现在仍然在线**（2026-09-13 实测，均 200）：
   - `.../android/1088/patch.json`（662,225 B）、`.../launcherv2.js`、`.../manifest.1.0.20.json`
   - `https://act.lingxigames.com/prism-kpf75rez` —— 这就是公告缓存里 `activity_travelmap`（`isOpen=1`）指向的
     **官方"足迹地图"H5**（166 KB），即我们当初因为"服务端驱动、拿不到"而自己画 `map.html` 的那个功能，
     官方页面本身还活着（用它就不必自己画图、也不涉及审图号问题）。

另：公告缓存里还有 `client_setting: hideCalendar = 1`（2023-07-10 起官方就把日历入口藏了），
与我们把日历修好、显示真实日期的做法相反，可作为备注。

## 三、导出手法 vs 小红书教程：两个都不是"错"，而是同一个前提不成立

**结论：玩家手法没问题，教程也不是"操作错了"，而是"要导的那样东西在本地根本不存在"。**

1. **这份 dump 是一次完整、规范的 App 私有目录备份**（甚至可以说是教科书级）：
   顶层 23 个目录一个不缺 —— `app_SGLib / app_lib / app_libs / app_plugins / app_textures /
   app_odex / app_odex_update / app_update / app_track_sslcache / app_webview / cache / code_cache /
   crashsdk / databases / files / gosdk / shared_prefs` 以及 4 个 `app_TCG_*` 插件目录、`app_mdp_1885_*`、
   `app_emas_accs`；连 14.7 MB 的 OPPO 插件 apk、1.7 MB 的厂商配置、crashsdk tag、加固数据都一并带走；
   文件 mtime 连续覆盖 09-09 15:11 ~ 09-12 14:19（正是公告发布后的那一周）。
   包里没有 `no_backup/`（该目录可能本就不存在），也没带 `/sdcard/Android/data/<pkg>/`
   —— 这两处都不存游戏进度。
2. **WebView 的 localStorage 不是"被备份工具漏掉"，而是本来就是空的**：
   `CURRENT` → `MANIFEST-000001`（41 B，未引用任何 `.ldb`）、`000003.log` = 0 字节。
   而游戏侧的本地写入（`core.String.setCookieGlobal("clover_pos_"+id,…)`）实际由 EjoySDK 的桥接写进
   `shared_prefs/localhost.xml` —— 那份文件里 26 个键一条不少。两处对得上，不存在遗漏。
3. **客户端从来没有"导出存档"这个功能**：把 1.0.20 原版与最终 1083 版 `main.min.js` 都搜了一遍，
   `导出 / 存档 / 备份 / exportSave / 云存档 / cloudSave` **全部 0 命中**。
   官方停运公告的口径也只是"您可自行提前保存您希望保留的角色**信息**"（供后续提供），而不是导出数据。
4. 根因是架构：进度 100% 在服务器（客户端连 `addClover/addTicket/addHouseItem` 都是空壳，
   一切广播由服务器推送），本地只有 `clover_pos_1..20` 这点摆放外观。
   所以任何人用"复制文件"的办法都拿不到这个账号的蛙 —— **不是导不出来，是没有可导的东西。**

**真要拿到可用的档案，只有两条教程没写的路**（且都要赶在 2026-12-08 18:00 清档之前）：
- **协议层抓包**：游戏是明文 JSON over WebSocket，把登录后的 `client_load_all_info` 回复与后续推送录下来，
  就等于一份完整档案（需要设备装代理与 CA 证书，纯复制文件做不到）。
- **官方渠道**：公告明确客服可查"剩余充值获得的三叶草"，并允许玩家自行保存角色信息用于后续诉求。

**附带价值**：这份包"没存到存档"，却正好存到了我们项目需要的东西 —— 最后的官方内容（CDN 缓存）
与官方公告/开关缓存（含停运公告全文、足迹地图活动地址、`hideCalendar` 开关）。

## 四、从仍在线的官方 CDN 补档（已完成）

- 清单：`1088/patch.json` = **4168 条 / 287.5 MB**（每条含 版本目录 + md5 + 大小）。
- 与 `work/run/web` 逐文件 md5 比对：**3764 条已逐字节相同**（1073 是 2024-03 的全量发布，
  我们 APK 那批文件大多未变），**缺 404 条 / 47.7 MB**（= 2024-03→2026-02 新内容 + 被我们补丁改过的文件的官方原版）。
- 已拉到 `work/cdn/final1088/<版本目录>/<原路径>`：**成功 403 / 失败 1**，耗时 6 秒，
  逐文件复核 **403 一致 / 0 不一致**。脚本 `work/tools/fetch_final_cdn.mjs`，日志 `work/logs/cdn_final1088.txt`，
  说明见 `work/cdn/final1088/README.txt`。
- 唯一"失败"项不是下载失败：`1073/resource/China/config/gameConfig.json` 的 CDN 现状 md5（`dcbc1d6f…`）
  与清单所写（`d143ffe8…`）不一致，而同为 988 B；核对 `base.apk` 内同一文件正是 `dcbc1d6f…`，
  即 CDN 给的是官方那一份，是清单这条自身对不上。已按 CDN 原样收录。
  顺带得到官方端点表：正式服 `wss://ali-lxqw-login.ejoy.com:443`（+ 备份服、+ 裸 IP `ws://8.135.13.60:80`）、
  测试服 `wss://c1-p10526-prebuild.ejoy.com` —— 将来若做私服/数据恢复可作参照。
- 新内容抽样（run/web 中确认不存在）：xw11 39 / xw12 42 / xw13 37 个文件、gif_4 36 / gif_5 15、
  `g_beijing6`×5、`u_month6_3`、`calendar_1..12`、`icon2_sheet`/`icon3_sheet`/`furniture_xw1(-1)`、
  `egg_6_jiaoshui`/`egg_7_linyu`、`config.eab`(1088)、`default.res.json`(1085)、`main.min.js`+`default.thm.js`(1083)、
  `reward.eab`/`system.eab`。

## 五、建议
1. **存档方面**：无内容可转；如需向分享者解释，本文件第一节即为答复。
2. **内容方面（真正值得做的）**：把这批 1073–1088 的官方增量按我们既有的
   `merge_rows_preserving_format.py`（文本插入保格式）+ `verify_a_tier_merge.py`（INTENDED 校验）
   + `bundle_engine.py` 流程合入：
   - 先合三张表（furnitureData / furnitureShopData / benchData）与 `default.res.json`（1085，508,256 B）
   - 再补 `encytravel`、新明信片、相册扩容行、新特产/典藏/称号
   - 最后搬 48 MB 资源（注意 sheet 大图与 `default.res.json` 必须同批更新，否则纹理对不上）
3. **不建议**整体替换 `main.min.js`/`default.thm.js`：版本差异小、收益低，风险（我们的离线补丁都在其上）远大于收益。
4. 工作产物放在 `work/_save_probe/`（解包、解密的 61 张表、比对报告），确认后可清理或按需入库。
