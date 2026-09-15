# `测试用存档.tar.gz` 完整清单

压缩包 66610346 bytes；目录项 880，文件项 1969；文件合计 87.43 MB

文件 mtime 范围（UTC）：2026-09-09 07:11 ~ 2026-09-12 06:19；打包用户 u0_a42

## 一、顶层目录

| 目录 | 文件数 | 体积 | 是什么 |
|---|---:|---:|---|
| `files/` | 1717 | 64.44 MB | 应用私有文件：**游戏 CDN 增量缓存 + EjoySDK 运行时（lua/js）+ 各种 key/日志** |
| `databases/` | 128 | 1.21 MB | SDK 的 SQLite 库（OPPO/Ejoy/友盟/崩溃/广告），无游戏进度 |
| `shared_prefs/` | 57 | 1.76 MB | SharedPreferences：**含游戏侧的 localhost.xml（唯一本地游戏状态）** |
| `crashsdk/` | 22 | 0.00 MB | 阿里崩溃 SDK 的 tag/log |
| `app_SGLib/` | 20 | 0.66 MB | 阿里 SecurityGuard 加固（反调试/反篡改）数据 |
| `app_webview/` | 13 | 4.10 MB | WebView 用户数据（Chrome 档案：Cookies / Web Data / **空的 localStorage leveldb**） |
| `app_lib/` | 4 | 0.48 MB | 随包解出的 .so（oneplus/heytap/微信插件/hdiff） |
| `app_plugins/` | 3 | 14.73 MB | OPPO 游戏服务插件（一个 14.7 MB 的 apk） |
| `cache/` | 3 | 0.03 MB | WebView HTTP 缓存（Code Cache / wasm） |
| `app_emas_accs/` | 1 | 0.00 MB | 阿里云移动推送(EMAS)消息文件 |
| `gosdk/` | 1 | 0.00 MB | cn.gosdk 配置 |

## 二、`files/` 细分

| 路径 | 文件数 | 体积 |
|---|---:|---:|
| `files/games` | 988 | 51.20 MB |
| `files/jsdata` | 571 | 6.27 MB |
| `files/ejoysdk_lightboat_res` | 42 | 6.51 MB |
| `files/html` | 40 | 0.26 MB |
| `files/cache` | 20 | 0.03 MB |
| `files/.5bbf` | 8 | 0.01 MB |
| `files/ejoysdk_res` | 7 | 0.00 MB |
| `files/oat` | 4 | 0.01 MB |
| `files/.7934039a7252be16` | 3 | 0.00 MB |
| `files/.ply` | 2 | 0.00 MB |
| `files/.gspatch2` | 1 | 0.01 MB |
| `files/ejoysdklogv1` | 1 | 0.00 MB |
| `files/risk` | 1 | 0.01 MB |
| `files/gu_sdk_logs` | 1 | 0.00 MB |
| `files/dns` | 1 | 0.00 MB |
| `files/.umeng` | 1 | 0.00 MB |

### `files/games/` —— 官方 CDN 缓存（本项目最关心的部分）

文件数 988，体积 51.20 MB

| 前缀 | 文件数 | 体积 |
|---|---:|---:|
| `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release` | 950 | 51.05 MB |
| `files/games/https/p10528-launcher.ejoy.com/#/ann` | 36 | 0.02 MB |
| `files/games/http/p10528-cms.ejoy.com/post_images/67c7ef6a736d0f0025eff86f!o.png#header` | 1 | 0.00 MB |
| `files/games/http/p10528-cms.ejoy.com/post_images/67c7ef6a736d0f0025eff86f!o.png` | 1 | 0.14 MB |
| 版本目录 | 文件数 | 体积 |
|---|---:|---:|
| `1073` | 432 | 17.03 MB |
| `1074` | 42 | 1.68 MB |
| `1075` | 2 | 0.03 MB |
| `1076` | 48 | 1.44 MB |
| `1077` | 26 | 2.04 MB |
| `1078` | 58 | 2.52 MB |
| `1079` | 100 | 7.10 MB |
| `1080` | 122 | 9.09 MB |
| `1081` | 22 | 0.85 MB |
| `1082` | 2 | 0.26 MB |
| `1083` | 6 | 4.32 MB |
| `1084` | 4 | 0.44 MB |
| `1085` | 14 | 0.93 MB |
| `1086` | 12 | 0.22 MB |
| `1087` | 12 | 0.20 MB |
| `1088` | 4 | 2.76 MB |
| `launcherv2.js#` | 22 | 0.08 MB |
| `manifest.1.0.20.json#` | 22 | 0.06 MB |

## 三、小目录逐文件（完整）


<details><summary><b>shared_prefs（57）</b> — 57 个文件 / 1.76 MB</summary>

```
     1724496  shared_prefs/nearme_config_com.ali.croak.nearme.gamecenter.xml
       73012  shared_prefs/localhost.xml
       16193  shared_prefs/com.nearme.gamecenter.open.xml
        7258  shared_prefs/ejoysdk.xml
        6279  shared_prefs/TCG@Nearx_cfbb33ae94664c1dd1a6a7c971b36485_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a.xml
        1509  shared_prefs/umeng_general_config.xml
        1004  shared_prefs/download_range_info_cache.xml
         968  shared_prefs/dispatch_strategy_com.ali.croak.nearme.gamecenter.xml
         875  shared_prefs/dispatch_strategy.xml
         862  shared_prefs/share_data.xml
         794  shared_prefs/com.ali.croak.nearme.gamecenter_preferences.xml
         715  shared_prefs/umzid_general_config.xml
         698  shared_prefs/com.ali.croak.nearme.gamecenter_ip_prefs.xml
         682  shared_prefs/nearme_func_com.ali.croak.nearme.gamecenter.xml
         591  shared_prefs/TCG@Nearx_ff031262c5c2386f74b2f8d3b1cfbc4c_TCG_Nearxfcf5a694a759b66bcdfb95e6f0e7b5fa.xml
         511  shared_prefs/common-com.ali.croak.nearme.gamecenter:gcsdk.xml
         484  shared_prefs/msp_config.xml
         478  shared_prefs/EMAS_Agoo_AppStore.xml
         414  shared_prefs/com.opos.st.strategy.prefs.xml
         409  shared_prefs/mobad_sdk_record.xml
         408  shared_prefs/EMAS_ACCS_SDK.xml
         369  shared_prefs/cn.gosdk.pref.ver.xml
         354  shared_prefs/umeng_common_config.xml
         273  shared_prefs/CloudConfig@Nearx_379711a8e809971f5959d68eb0c781c0_Nearx84b6dde4b4497b2d6e1b255098772c26.xml
         269  shared_prefs/nearme_setting_com.ali.croak.nearme.gamecenter.xml
         264  shared_prefs/um_social_azx.xml
         244  shared_prefs/sp_emas_info.xml
         230  shared_prefs/track_preference_com.ali.croak.nearme.gamecenter:gcsdk.xml
         224  shared_prefs/TCG@Nearx_526f9cd1fcd6b73109831bac79869dc6_TCG_Nearxfcf5a694a759b66bcdfb95e6f0e7b5fa.xml
         221  shared_prefs/track_preference_com.ali.croak.nearme.gamecenter:gcsdk_20164.xml
         218  shared_prefs/TCG@Nearx_489e87a0439db8875aa9f278b3b5c98d_TCG_Nearxfcf5a694a759b66bcdfb95e6f0e7b5fa.xml
         217  shared_prefs/um_policy_grant.xml
         215  shared_prefs/cn.aga.xdatasdk.pref.ver.xml
         215  shared_prefs/plugin_framework.xml
         212  shared_prefs/kitcommon.xml
         210  shared_prefs/EMAS_AGOO_BINDAliyunPushacs4public.m.taobao.com.xml
         209  shared_prefs/Alvin2.xml
         191  shared_prefs/UM_PROBE_DATA.xml
         181  shared_prefs/cn.gosdk.pref.xml
         174  shared_prefs/gateway_command.xml
         172  shared_prefs/umeng_socialize.xml
         157  shared_prefs/com.opos.cmn.biz.ext.prefs.xml
         151  shared_prefs/openid.xml
         148  shared_prefs/sp_common_file.xml
         146  shared_prefs/heytap_gamesdk.xml
         146  shared_prefs/um_session_id.xml
         137  shared_prefs/e3c9997fed83a974.xml
         136  shared_prefs/delayed_transmission_flag_new.xml
         133  shared_prefs/net_remote_config.xml
         132  shared_prefs/com.ejoy.sdk.lua.xml
         129  shared_prefs/com.ali.croak.nearme.gamecenter.xml
         127  shared_prefs/cn.ejoyads.adpsdk.pref.xml
         127  shared_prefs/WebViewChromiumPrefs.xml
         119  shared_prefs/com.opos.cmn.third.id.prefs.xml
         116  shared_prefs/BaseSDK.xml
          65  shared_prefs/download_multi_duration_cache.xml
          65  shared_prefs/umeng_sp_oaid.xml
```
</details>

<details><summary><b>databases（128）</b> — 128 个文件 / 1.21 MB</summary>

```
      217088  databases/NearMeSTAT.db
       69632  databases/track_sqlite_com.ali.croak.nearme.gamecenter:gcsdk_20164
       65536  databases/emas_message_accs_db
       40960  databases/ua.db
       32768  databases/share.db
       24576  databases/track_sqlite_common_com.ali.croak.nearme.gamecenter:gcsdk
       24576  databases/acs_st.db
       20480  databases/adp_sdk.db
       20480  databases/track_crash_collector_db
       20480  databases/opos_mobad_ad
       20480  databases/crash_collector_db
       20480  databases/agalog_stat.db
       20480  databases/utdid.db
       20480  databases/umeng_zero_cache.db
       20480  databases/TCG_Nearx_TCG_compass_20164_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearxfcf5a694a759b66bcdfb95e6f0e7b5fa_BUSINESS_20164_EventRule_V3@5316
       20480  databases/bizlog_dao.db
       20480  databases/emas_accs.db
       20480  databases/gosdk_log.db
       16384  databases/TCG_Nearx_TCG_compass_20164_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearxfcf5a694a759b66bcdfb95e6f0e7b5fa_BUSINESS_20164_CONFIG@266
       16384  databases/request_statistic.db
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_NetMonitor@3
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_AutoLoginDelayDurationConfig@3
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_MspModeWhiteDeviceList@34
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_BrandGameUnionBizMod@39
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PreOrderPayBlackPluginVersionCode@7
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_ResUpdateOcrCheckConfig@10
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_NetMonitorBlacklist@2
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PluginHLogConfig@7
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PreOrderPaySwitch@9
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_FaceScanPkgWhiteList@2
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_BlackGamePackageList@45
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_CallPaymentProtectPkgWhiteList@36
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PayResultChainConfig2@2
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_WebLoginLimit@4
       12288  databases/Nearx_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_Nearx84b6dde4b4497b2d6e1b255098772c26_MspModeBlackDeviceList@29
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PayTechConfig@11
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PluginSend2MspDelayConfig@2
       12288  databases/TCG_Nearx_TCG_50351_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearxfcf5a694a759b66bcdfb95e6f0e7b5fa_TrackGlobalConfig3@44
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_HangupUpdatePackageLimit@5
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_MspAppVersionCodeList@11
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_GetGenderLimitConfig@7
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_whiteDomainList@3
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_CheckForegroundResultMode@8
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PluginVersionCodeList@9
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_hookHWhitePkgName@5
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_MspModeBlackDeviceList@29
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_NetMonitorSampleRate@2
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PayParamsSwitch@2
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_CrashModeSwitch@6
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_NetMonitorSuccessCodeMap@2
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_IsAdultMethodWhiteList@16
       12288  databases/Nearx_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_Nearx84b6dde4b4497b2d6e1b255098772c26_MspModeWhiteDeviceList@34
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_LogSubmissionConfig@10
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_EnableResUpdate@22
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_SDKInitReportConfig@4
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_DisplaySellingPointConfig@4
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_hookH_enable@2
       12288  databases/TCG_Nearx_TCG_compass_20164_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearxfcf5a694a759b66bcdfb95e6f0e7b5fa_BUSINESS_20164_CONFIG_FLEXIBLE@1
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_NoRealNameReturnFailed@6
       12288  databases/Nearx_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_Nearx84b6dde4b4497b2d6e1b255098772c26_BrandGameUnionBizMod@39
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_CheckCpRepeatOrderConfig@3
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_SinglePlayerGamePayConfig@18
       12288  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_IllegalPayValidation@3
        8192  databases/usetrace.db
         223  databases/cdn.gz
           0  databases/opos_mobad_ad-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_hookHWhitePkgName@5-journal
           0  databases/umeng_zero_cache.db-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PluginHLogConfig@7-journal
           0  databases/TCG_Nearx_TCG_compass_20164_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearxfcf5a694a759b66bcdfb95e6f0e7b5fa_BUSINESS_20164_EventRule_V3@5316-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_CrashModeSwitch@6-journal
           0  databases/emas_accs.db-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_SDKInitReportConfig@4-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_SinglePlayerGamePayConfig@18-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_AutoLoginDelayDurationConfig@3-journal
           0  databases/Nearx_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_Nearx84b6dde4b4497b2d6e1b255098772c26_MspModeBlackDeviceList@29-journal
           0  databases/adp_sdk.db-journal
           0  databases/TCG_Nearx_TCG_compass_20164_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearxfcf5a694a759b66bcdfb95e6f0e7b5fa_BUSINESS_20164_CONFIG@266-journal
           0  databases/track_sqlite_com.ali.croak.nearme.gamecenter:gcsdk_20164-journal
           0  databases/TCG_Nearx_TCG_compass_20164_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearxfcf5a694a759b66bcdfb95e6f0e7b5fa_BUSINESS_20164_CONFIG_FLEXIBLE@1-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_NetMonitor@3-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_NetMonitorBlacklist@2-journal
           0  databases/NearMeSTAT.db-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_BlackGamePackageList@45-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_CallPaymentProtectPkgWhiteList@36-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_FaceScanPkgWhiteList@2-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_EnableResUpdate@22-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_NetMonitorSuccessCodeMap@2-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_MspModeBlackDeviceList@29-journal
           0  databases/acs_st.db-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_DisplaySellingPointConfig@4-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_NetMonitorSampleRate@2-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_IsAdultMethodWhiteList@16-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PayParamsSwitch@2-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_IllegalPayValidation@3-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_LogSubmissionConfig@10-journal
           0  databases/Nearx_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_Nearx84b6dde4b4497b2d6e1b255098772c26_BrandGameUnionBizMod@39-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_BrandGameUnionBizMod@39-journal
           0  databases/track_sqlite_common_com.ali.croak.nearme.gamecenter:gcsdk-journal
           0  databases/ua.db-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_GetGenderLimitConfig@7-journal
           0  databases/TCG_Nearx_TCG_50351_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearxfcf5a694a759b66bcdfb95e6f0e7b5fa_TrackGlobalConfig3@44-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_whiteDomainList@3-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_hookH_enable@2-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_NoRealNameReturnFailed@6-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PluginSend2MspDelayConfig@2-journal
           0  databases/share.db-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_CheckCpRepeatOrderConfig@3-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PayResultChainConfig2@2-journal
           0  databases/crash_collector_db-journal
           0  databases/emas_message_accs_db-journal
           0  databases/track_crash_collector_db-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_HangupUpdatePackageLimit@5-journal
           0  databases/gosdk_log.db-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_WebLoginLimit@4-journal
           0  databases/request_statistic.db-journal
           0  databases/utdid.db-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_MspAppVersionCodeList@11-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_CheckForegroundResultMode@8-journal
           0  databases/Nearx_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_Nearx84b6dde4b4497b2d6e1b255098772c26_MspModeWhiteDeviceList@34-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PayTechConfig@11-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_MspModeWhiteDeviceList@34-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PreOrderPaySwitch@9-journal
           0  databases/agalog_stat.db-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PreOrderPayBlackPluginVersionCode@7-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_ResUpdateOcrCheckConfig@10-journal
           0  databases/TCG_Nearx_TCG_mdp_1885_com.ali.croak.nearme.gamecenter:gcsdk_TCG_Nearx2976c4d4def6c46beda8af88abeb6e5a_PluginVersionCodeList@9-journal
           0  databases/bizlog_dao.db-journal
```
</details>

<details><summary><b>app_webview（13）</b> — 13 个文件 / 4.10 MB</summary>

```
     4194304  app_webview/BrowserMetrics-spare.pma
       83968  app_webview/Default/Web Data
       24576  app_webview/Default/Cookies
         337  app_webview/Default/Local Storage/leveldb/LOG
         337  app_webview/Default/Local Storage/leveldb/LOG.old
         187  app_webview/pref_store
          41  app_webview/Default/Local Storage/leveldb/MANIFEST-000001
          37  app_webview/webview_data.lock
          16  app_webview/Default/Local Storage/leveldb/CURRENT
           0  app_webview/Default/Web Data-journal
           0  app_webview/Default/Local Storage/leveldb/000003.log
           0  app_webview/Default/Local Storage/leveldb/LOCK
           0  app_webview/Default/Cookies-journal
```
</details>

<details><summary><b>crashsdk（22）</b> — 22 个文件 / 0.00 MB</summary>

```
        2575  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.sts
         336  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.meminfo
         301  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.hdr
         258  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.status
         151  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.bati
          75  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.st
          36  crashsdk/tags/unique
          31  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.end
          25  crashsdk/tags/ver
          25  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.start
          22  crashsdk/tags/bvu
          22  crashsdk/tags/bytes
          20  crashsdk/tags/pv.wa
          20  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.uptime
          14  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.time
           4  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.pid
           1  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.ss
           1  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.anrtmp
           0  crashsdk/tags/RETNECEMAG0EMRAEN0KAORC0ILA0MOC.ps
           0  crashsdk/tags/cr.wa
           0  crashsdk/tags/dt.wa
           0  crashsdk/tags/cdt.wa
```
</details>

<details><summary><b>cache</b> — 3 个文件 / 0.03 MB</summary>

```
       28700  cache/WebView/font_unique_name_table.pb
          48  cache/WebView/Default/HTTP Cache/Code Cache/wasm/index-dir/the-real-index
          24  cache/WebView/Default/HTTP Cache/Code Cache/wasm/index
```
</details>

<details><summary><b>gosdk</b> — 1 个文件 / 0.00 MB</summary>

```
         720  gosdk/clientConfig
```
</details>

<details><summary><b>app_emas_accs</b> — 1 个文件 / 0.00 MB</summary>

```
         861  app_emas_accs/message333340292
```
</details>

<details><summary><b>app_lib</b> — 4 个文件 / 0.48 MB</summary>

```
      215120  app_lib/liboneplussdk.so
      124664  app_lib/libhdiff.so
       92104  app_lib/libonlywechat_plugin.so
       71608  app_lib/libheytaplog.so
```
</details>

<details><summary><b>app_plugins</b> — 3 个文件 / 14.73 MB</summary>

```
    15447602  app_plugins/oppo_game_service_6230102.apk
        1904  app_plugins/.Og.meta.crypt
          82  app_plugins/.Og.meta
```
</details>

<details><summary><b>app_SGLib</b> — 20 个文件 / 0.66 MB</summary>

```
      200169  app_SGLib/.utask_64/08303282611259212593/52@24
      147423  app_SGLib/.utask_64/08303282612545529285/66@37
      142135  app_SGLib/.utask_64/27756254392545529285/56@37
       66463  app_SGLib/.utask_64/28009282652775325187/27@18
       50512  app_SGLib/.utask_64/3006226982269812571525955/17@11
       36573  app_SGLib/.utask_64/0830725715/9@5
       32552  app_SGLib/.utask_64/083042929525189/3@2
       14124  app_SGLib/.c49493b420
        2648  app_SGLib/fnc4/Arom_0_400005
         800  app_SGLib/B63841DC8376825A3DA9FB74055F8B44
         375  app_SGLib/app_1788937433/main/main_1701400586.pkgInfo
         363  app_SGLib/.utask_64/0830925207/1@1
         340  app_SGLib/SG_INNER_DATA_AVMP
         280  app_SGLib/.cd78eccde0
         247  app_SGLib/app_1788937433/main/middletier_1701400586.pkgInfo
         227  app_SGLib/app_1788937433/main/securitybody_1701400586.pkgInfo
         202  app_SGLib/fnc4/Aspl_0_400001
          24  app_SGLib/.c794579e40
           0  app_SGLib/.sgdynkp
           0  app_SGLib/app_1788937433/lock.lock
```
</details>

## 四、最大的 40 个文件

| 体积 | 路径 |
|---:|---|
| 14.73 MB | `app_plugins/oppo_game_service_6230102.apk` |
| 4.11 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1073/resource/China/sheet/icon3_sheet.png#/045b8c1119591563fcdbc9f92f174438` |
| 4.09 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1079/resource/China/sheet/icon2_sheet.png#/4b60bfd3a0e1b5692c924bf48b4a3120` |
| 4.00 MB | `app_webview/BrowserMetrics-spare.pma` |
| 3.68 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1080/resource/China/sheet/furniture_xw1.png#/3df6b74519eeccb320bb13604d6896a1` |
| 2.13 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1088/resource/China/eab/config.eab#/896ec322f35a7a00fc703a470c6eb009` |
| 1.70 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1083/resource/ejoysdk_lua.zip#/94e75c567b5b1d982915ae87ae577f20` |
| 1.64 MB | `shared_prefs/nearme_config_com.ali.croak.nearme.gamecenter.xml` |
| 1.46 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1080/resource/China/sheet/furniture_xw1-1.png#/3fb4a61b944e579b8d44d0e36b24ade1` |
| 1.40 MB | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_cashier_assets_index-legacy-9JQDGpuu.js` |
| 1.38 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1077/resource/China/animation/gif_photo/gif_6/gif_6_role_bhqw.png#/b64b0dad13ee836b28cf630f156a24bd` |
| 1.34 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1083/js/default.thm.js#/97f3ea8c97828f262acf0d24b3974b5f` |
| 1.29 MB | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_cashier_assets_index-XKmCcfjK.js` |
| 1.28 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1083/js/main.min.js#/9161863afd5844ef5bc1cea9e59d45e2` |
| 1.15 MB | `files/ejoysdk_lightboat_res/lingxi_accounts_m_latest/2.0.18/lingxi_2.0.0_public_m_vendors_m.4902fc97.async.js` |
| 0.91 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1073/resource/China/eab/reward.eab#/c98d632e324cda273f76118bf243abcf` |
| 0.78 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1080/resource/China/animation/sleep/sleep_4.png#/749e618a0016c88b322c61cde81c3352` |
| 0.67 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1073/resource/China/sheet/icon3_sheet-1.png#/b57d4e284cf3e203a233946b337ae86e` |
| 0.66 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1080/resource/China/animation/sleep/sleep_3.png#/435e48de2480aeba94058047bcb51c6b` |
| 0.63 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1088/patch.json#/f15c8102bb1db5d12ac38ad241988815` |
| 0.51 MB | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_ticket_assets_index-legacy-B2oMBgUL.js` |
| 0.51 MB | `files/ejoysdk_lightboat_res/lingxi_accounts_m_latest/2.0.18/lingxi_2.0.0_public_m_umi_m.5e3df59b.js` |
| 0.51 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1073/resource/China/animation/gif_photo/gif_4/gif_4_bg.png#/fbbb2a7aec7dc4a374891a64e5121659` |
| 0.48 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1085/resource/China/default.res.json#/b03cf65528018e040ac40411f02db8fb` |
| 0.42 MB | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_ticket_assets_index-BJnagsjJ.js` |
| 0.42 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1074/resource/China/animation/game_egg/egg_6_jiaoshui.png#/d8c3bde6074cba25dc8a455cc00e0338` |
| 0.38 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1078/resource/China/eab/system.eab#/ecadcbc55fdf0f0c6dbfc69b568b3fb2` |
| 0.37 MB | `files/ejoysdk_lightboat_res/lingxi_accounts_m_latest/2.0.18/lingxi_2.0.0_public_m_umi_m.38539cec.css` |
| 0.34 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1076/resource/China/animation/gif_photo/gif_5/gif_5_bg.png#/f8def3ddcbe93b7acd4c036cca6454b7` |
| 0.32 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1079/resource/China/images/Picture/Unique/u_month8_2.png#/c0081f8004185ac7d78b9e5013a03ce4` |
| 0.31 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1074/resource/China/images/Picture/Unique/u_two_month4_2.png#/5b676c221119370c55b0a3acf34ea254` |
| 0.29 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1073/resource/China/images/Picture/Unique/u_anniv.png#/120171140726cb76912e9129f9c995e7` |
| 0.28 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1073/resource/China/images/Picture/Unique/u_two_month2_2.png#/9032b492f962e5f30888b1d3b7b2bba8` |
| 0.28 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1073/resource/China/images/Picture/Unique/u_player.png#/9173113d904d54d60efcc14b5746a2b9` |
| 0.28 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1073/resource/China/eab/preload.eab#/80946c26d3acf20bd7a4ebca58a7d60d` |
| 0.28 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1073/resource/China/images/Picture/Goal/g_neimenggu1.png#/49669bb97a17f01ebf126fdadb377d77` |
| 0.27 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1079/resource/China/images/Picture/Unique/u_two_month10_3.png#/d5a36168da1d59c276928377017f938f` |
| 0.27 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1076/resource/China/images/Picture/Unique/u_month5_2.png#/a63ffddd265172f9169ea3a77cc7f7c6` |
| 0.27 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1079/resource/China/images/Picture/Unique/u_mid_autumn_2.png#/5bbaef86203d43023c9db2bc942c3692` |
| 0.27 MB | `files/games/https/ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/1079/resource/China/images/Picture/Unique/u_two_month8_2.png#/a5701534258cc9853431de008fe00575` |

## 五、`files/` 下的非游戏文件（按体积）

| 体积 | 路径 |
|---:|---|
| 体积 | 路径 |
|---:|---|
| 1467147 B | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_cashier_assets_index-legacy-9JQDGpuu.js` |
| 1347952 B | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_cashier_assets_index-XKmCcfjK.js` |
| 1204288 B | `files/ejoysdk_lightboat_res/lingxi_accounts_m_latest/2.0.18/lingxi_2.0.0_public_m_vendors_m.4902fc97.async.js` |
| 539564 B | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_ticket_assets_index-legacy-B2oMBgUL.js` |
| 539551 B | `files/ejoysdk_lightboat_res/lingxi_accounts_m_latest/2.0.18/lingxi_2.0.0_public_m_umi_m.5e3df59b.js` |
| 442309 B | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_ticket_assets_index-BJnagsjJ.js` |
| 388268 B | `files/ejoysdk_lightboat_res/lingxi_accounts_m_latest/2.0.18/lingxi_2.0.0_public_m_umi_m.38539cec.css` |
| 192331 B | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_cashier_assets_polyfills-legacy-cOrFIEQx.js` |
| 187918 B | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_ticket_assets_polyfills-legacy-Jsqtyflp.js` |
| 150477 B | `files/jsdata/resource/ejoysdk_lua/ejoysdk_gangplank.lua` |
| 129058 B | `files/jsdata/resource/ejoysdk_lua/ejoysdk_android.lua` |
| 127067 B | `files/jsdata/resource/ejoysdk_lua/chat/ejoysdk_chat_base.lua` |
| 122451 B | `files/ejoysdk_lightboat_res/lingxi_accounts_m_latest/2.0.18/lingxi_2.0.0_public_m_static_scan_guid.9fbc0b95.png` |
| 118759 B | `files/jsdata/resource/ejoysdk_lua/chat/ejoysdk_chat_model_impl.lua` |
| 105430 B | `files/jsdata/resource/ejoysdk_lua/ejoysdk_harmonyos.lua` |
| 105298 B | `files/jsdata/resource/ejoysdk_lua/res/model/http_download_multi_task.lua` |
| 92801 B | `files/jsdata/resource/ejoysdk_lua/friend/ejoysdk_friend.lua` |
| 89110 B | `files/jsdata/resource/ejoysdk_lua/ejoysdk_ios.lua` |
| 85072 B | `files/jsdata/resource/ejoysdk_lua/ejoysdk.lua` |
| 79291 B | `files/runtime-dex.jar` |
| 78838 B | `files/html/assets/js/app.min.js` |
| 77796 B | `files/jsdata/resource/ejoysdk_lua/ejoysdk_windows.lua` |
| 76434 B | `files/jsdata/resource/ejoysdk_lua/res/model/src_adapters/ejoy_res_source.lua` |
| 71389 B | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_cashier_assets_index-D96UDkVe.css` |
| 69272 B | `files/jsdata/resource/ejoysdk_lua/res/model/http_download_task.lua` |
| 68050 B | `files/jsdata/resource/ejoysdk_lua/res/model/res_src/ejoy_res_source_model.lua` |
| 67117 B | `files/jsdata/resource/ejoysdk_lua/chat/ejoysdk_chat.lua` |
| 61373 B | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_ticket_assets_index-Psi7BULj.css` |
| 60639 B | `files/jsdata/resource/ejoysdk_lua/player/player_info.lua` |
| 60002 B | `files/jsdata/resource/ejoysdk_lua/res/ejoysdk_res.lua` |
| 58877 B | `files/jsdata/resource/ejoysdk_lua/chat/ejoysdk_voice.lua` |
| 57985 B | `files/html/assets/js/libs.min.js` |
| 57415 B | `files/jsdata/resource/ejoysdk_lua/res/startup/interceptors/sub_pkg_interceptor/sub_pkg_interceptor.lua` |
| 55607 B | `files/jsdata/resource/ejoysdk_lua/vendors/push.lua` |
| 53408 B | `files/jsdata/resource/ejoysdk_lua/vendors/aligames.lua` |
| 52829 B | `files/jsdata/resource/ejoysdk_lua/vendors/cloud_game.lua` |
| 51143 B | `files/jsdata/resource/ejoysdk_lua/res/lightboat/ejoysdk_lightboat.lua` |
| 49603 B | `files/ejoysdk_lightboat_res/prod_lingxi_paycenter/1.0.18/paycenter_feature_1.6.1_views_cashier_assets_index-legacy-GDWSP8MD.js` |
| 49030 B | `files/jsdata/resource/ejoysdk_lua/ejoysdk_launcher.lua` |
| 48463 B | `files/html/assets/css/style.css` |
| 47779 B | `files/jsdata/resource/ejoysdk_lua/cloud_game/cloud_ui/cloud_web_text_res.lua` |
| 45479 B | `files/jsdata/resource/ejoysdk_lua/vendors/firebase.lua` |
| 44265 B | `files/jsdata/resource/ejoysdk_lua/vendors/agora.lua` |
| 44045 B | `files/jsdata/resource/ejoysdk_lua/res/model/ejoy_http_download_model.lua` |
| 43898 B | `files/jsdata/resource/ejoysdk_lua/res/ejoy_namespace_dispatcher.lua` |

## 六、官方公告/开关缓存 `files/games/https/p10528-launcher.ejoy.com/`

36 个文件（7 条 detail 公告 JSON + 8 条 ticket 回执 + 各自 `#header`）。内容解析如下：

| 类型 | 标题/名称 | 官方时间 | 内容摘要 |
|---|---|---|---|
| `cadpa` | 旅行青蛙 | 2021-09-01 | 适龄提示说明：  1、本游戏是一款玩法简单的佛系放置类游戏，适用于年满 8 周岁及以上的用户，建议未成年人在家长监护下使用游戏产品。  2、本游戏的主角是一只大眼睛的小青蛙，小青蛙独自居住在一个石头洞的小屋里，房子外面的 |
| `system_normal` | 《旅行青蛙·中国之旅》停运公告 | 2026-09-09 | 亲爱的养蛙人： 大家好！ 由于IP授权合作到期，我们怀着万分不舍的心情向大家宣布：《旅行青蛙·中国之旅》将于2026年12月8日正式停止运营。 这些年，谢谢大家为小青蛙收三叶草、收拾行囊，在小青蛙出门时等小青蛙回家，为小 |
| `system_normal` | 《旅行青蛙·中国之旅》停运公告 | 2026-09-08 | 亲爱的养蛙人： 大家好！ 由于IP授权合作到期，我们怀着万分不舍的心情向大家宣布：《旅行青蛙·中国之旅》将于2026年12月8日正式停止运营。 这些年，谢谢大家为小青蛙收三叶草、收拾行囊，在小青蛙出门时等小青蛙回家，为小 |
| `recharge_merch` | https://s.tb.cn/c.0vbiEq | 2025-04-24 |  |
| `recharge_merch` | https://s.tb.cn/c.0FEPhO | 2025-04-24 |  |
| `recharge_merch` | https://s.tb.cn/c.0v9bmW | 2025-04-24 |  |
| `recharge_merch` | https://s.tb.cn/c.0vmEGl | 2025-04-24 |  |
| `recharge_merch` | https://s.tb.cn/c.0vSGwn | 2025-04-24 |  |
| `recharge_merch` | https://s.tb.cn/c.0vuUtg | 2025-04-24 |  |
| `client_setting` | hideCalendar | 2023-07-10 | 1 |
| `activity_travelmap` | https://act.lingxigames.com/prism-kpf75r | 2023-02-09 |  |
| `activity_cooking` |  | 2021-09-01 |  |

（以上为完整清单脚本产物，源：`work/_save_probe/inventory.py`）
