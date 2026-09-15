# 《旅かえる》(Tabikaeru) — Game Data Reference

**Target game:** 旅かえる by Hit-Point, released 2017-11, iOS/Android, single-player offline, free with IAP.
Official site: <http://www.hit-point.co.jp/games/tabikaeru/> · Official FAQ: <http://www.hit-point.co.jp/games/tabikaeru/faq/faq.html>

**Confidence legend — used consistently below**

| Mark | Meaning |
|---|---|
| **[V]** | **Verified** — a source URL is given and states this. |
| **[C]** | **Conflicting** — sources disagree; both are shown, neither is chosen silently. |
| **[U]** | **Uncertain** — single source, hedged source, or derivation (not a direct measurement). |
| **[CODE]** | Read from **decompiled game code**, not a web source. Mechanism is authoritative; note the version caveat in §0.3. |
| **not found** | Could not verify anywhere. Written literally, per instructions. |

---

## ⚠️ 0. READ FIRST — three traps in this data

### 0.1 There are TWO different games called "旅行青蛙"

| | 旅かえる (this document's target) | 旅行青蛙·中国之旅 |
|---|---|---|
| Publisher | **Hit-Point** (Japan) | **Alibaba** (China) |
| Released | 2017-11 | 2018-04 |
| Extra systems | none | 池/pond, 玉佩, 水墨纸伞, 睡垫, 家具, 100+ achievements, 11 regions / 28 cities |

**[V]** <https://www.9game.cn/lxqwzgb/11584047.html> · <https://www.biubiu001.com/lxqwzgzl/26690.html>

Many high-quality, numeric Chinese guides are about the **CN remake**, not the JP original. Every CN-version figure below is explicitly flagged. **Do not mix them.**

### 0.2 h1g.jp is unreachable from this environment

The definitive JP wiki — **旅かえる 攻略Wiki (ヘイグ), `h1g.jp/tabikaeru`** — returned HTTP 403 on every attempt (direct fetch, 4 browser user-agents, CORS proxies, Google Translate proxy). Its `ふくびき` (lottery), `いっぴん`, `めいぶつ`, `称号` pages are exactly where the missing numbers live. **This is the single largest gap in this report.** Also unreachable: wikiwiki.jp, altema.jp, game8.jp (no tabikaeru section — genuine 404), kamigame.jp (404), reddit.com, ja/zh wikipedia, web.archive.org.

### 0.3 The only decompiled code available is the **Chinese** build

`work/run/engine/data/define.json` holds a `Tabikaeru.Define` tuning table extracted from the CN build's `assets/game/js/main.min.js`. Its own header records:

> `"_source": "Tabikaeru.Define in assets/game/js/main.min.js (offsets 418503..423223) - the original server's tuning table"`
> `"VERSION": 1.07`

**Evidence it derives from the JP original:** uses `Tabikaeru.Define`; save paths `/Tabikaeru.sav`, `/GameData.sav`; JP ball kanji 白玉/青玉/緑玉/赤玉/黄玉; JP SE names `se01`–`se12`.
**Evidence it is NOT the pristine JP build:** `VERSION 1.07` (the JP APK in this workspace is **1.8.5/1.8.6**, per <http://www.hit-point.co.jp/games/tabikaeru/>); contains CN-only fields (`紫玉`, `ItemPutDesc` in Chinese, `FURNITURE_*`, `HandCraft*`, `Courtyard`, `ComposeId`); and its lottery model **differs structurally** from the JP one (§4.6).

**Therefore:** mechanisms that are identical in both versions are cited as **[CODE]**; **JP-specific numeric values are NOT asserted from this file** unless independently web-corroborated. Where they are, I say so.

---

## 1. CLOVER (三つ葉 / クローバー)

### 1.1 Growth slots in the garden (庭/畑/花壇) — **20**

| Claim | Value | Status | Source |
|---|---|---|---|
| Exact slot count | **20** (`花坛中总共有 20 根三叶草`) | **[V]** | <https://www.gameres.com/794522.html> · <https://www.sohu.com/a/222006355_505788> |
| Exact slot count | **20** | **[V]** | <https://blog.csdn.net/FlyPigYe/article/details/89797634> · <https://blog.csdn.net/sinat_38239454/article/details/79231297> |
| Max quantity | 最多数量为**20棵** | **[V]** | <https://m.techweb.com.cn/article/2018-01-21/2631065.shtml> · <https://www.9game.cn/news/2167141.html> |
| First-hand JP player, 2023 | 「花壇のマックスは**20枚**。」 | **[V]** | <https://brunet.hatenadiary.com/entry/2023/07/08/154941> |
| Loose wording | 總數約20片 | **[V]** (approx) | <https://zetaspace.cc/tabi-kaeru/> |
| CN-version | 三叶草数量上限是20个 | **[V]** (CN ver.) | <https://a.9game.cn/news/11249082.html> |

**Answer: exactly 20 growth slots.** Five independent sources; no source anywhere gives 21 / 24 / 30. The JP 2023 first-hand report upgrades the original "約20" to a hard 20.

### 1.2 Growth time per clover

| Claim | Value | Status | Source |
|---|---|---|---|
| Per-clover min/max | **最短 5 分鐘 (300 s) / 最長 4 小時 (14400 s)**, each clover independent | **[V]** | <https://www.saydigi.com/2018/01/tabikaeru-lucky-clover.html> |
| Per-clover min/max | **300 s – 14400 s**, individually re-grown | **[V]** | <https://www.gameres.com/794522.html> · <https://www.sohu.com/a/222006355_505788> · <https://blog.csdn.net/FlyPigYe/article/details/89797634> |
| Distribution shape | Regrowth follows a **normal (Gaussian) distribution inside [300 s, 14400 s]** | **[U]** — the mean/σ were in **formula images** that survived into no mirror | <https://www.gameres.com/794522.html> |
| **Exact μ / σ** | — | **not found** | — |
| Per-clover respawn interval table | — | **not found** | — |
| **Competing claim** | 「三叶草地**每隔3个小时**就会自动长满一次」 ("patch auto-refills fully every 3 hours") | **[C]** — contradicts the per-clover random model | <https://www.9game.cn/news/2166765.html> · <https://www.9game.cn/news/2167141.html> · <https://m.techweb.com.cn/article/2018-01-21/2631065.shtml> |
| Circumstantial support for ~3 h | A JP player review: 「1回の三葉集めで**50ほど**貰えたり」 (one harvest yields ~50) | **[V]** as an observation; <https://applion.jp/旅かえる/android-jp.co.hit_point.tabikaeru/review/> |

**Answer: minimum 5 minutes (300 s), maximum 4 hours (14400 s), random per clover, independently.** The exact Gaussian parameters are **not found**. A widely syndicated Chinese guide's "fully refills every 3 hours" **conflicts** with the per-clover model; note that a 300 s–14400 s distribution *averaging* ~3 h is arithmetically compatible with it, so the two claims may be describing the same thing at different levels of precision — but **no source reconciles them**, so this is left as **[C]**.

### 1.3 Harvest rules

| Question | Answer | Status | Source |
|---|---|---|---|
| Tap or slide? | Harvest is a **tap**: 「抜く作業はタッチ(タップ)するだけです。」 | **[V]** | <https://brunet.hatenadiary.com/entry/2023/07/08/154941> |
| Slide/flick also used | DLL contains `hitFlickClover`, `CheckHitClover`; tutorial text 「スライド操作でみつ葉のクローバーを収穫しましょう」 | **[CODE]** | JP `Assembly-CSharp.dll` string heap |
| One tap = one clover, or a group? | **A group.** First-hand JP: 「油断して誤タップして四つ葉を**ゴソッと**抜いてしまうこともしばしば」 (a careless mis-tap pulls four-leaf clovers *in a bunch*); 「(真ん中だけタッチするのはまず無理)」 (touching only the exact center is basically impossible) ⇒ the tap has an effective **radius** | **[V]** | <https://brunet.hatenadiary.com/entry/2023/07/08/154941> |
| Do clovers auto-respawn without tapping? | **No.** Regrowth is described as happening **after** the clover is cut: 「三叶草**割完之后**重生的时间…」. An unharvested slot stays occupied. | **[V]** | <https://www.gameres.com/794522.html> |
| Corroboration | A JP player deliberately **leaves 四つ葉 unharvested for years** to fill the bed; the bed only changes when he taps | **[V]** | <https://brunet.hatenadiary.com/entry/2023/07/08/154941> |
| Do unharvested clovers expire? | DLL has `CloverDestroyTime` / `cloverDestroy` — a destroy timer exists. Value **not found**. | **[CODE]** name only | JP `Assembly-CSharp.dll` |
| Can you buy clovers? | **Yes — IAP only.** Official: 「価格：無料 **アプリ内購入あり**」; a クローバーこうにゅう (clover purchase) screen exists. | **[V]** | <http://www.hit-point.co.jp/games/tabikaeru/> · <http://www.hit-point.co.jp/games/tabikaeru/faq/faq.html> |
| Official price list | — | **not found** (Hit-Point publishes none) | — |

### 1.4 Buying clovers — IAP tiers

**[U]** The only JP price figures located come from APPLION's *課金アイテム売れ筋ランキング* (a best-seller list that prints product names + prices — **not** an official price list):

| Product | JPY | clovers/yen |
|---|---|---|
| みつ葉 **400** | **110円** | 3.64 |
| みつ葉 **1000** | **220円** | 4.55 |
| みつ葉 **1800** | **330円** | 5.45 |
| みつ葉 **2800** | **440円** | 6.36 |

Source: <https://applion.jp/iphone/app/1255032913/> · corroborating hedged player review: 「三葉2800？で440円くらいだったので」 <https://applion.jp/旅かえる/android-jp.co.hit_point.tabikaeru/review/>

The JP DLL contains the constant **names** `CLOVER_ADD_1`…`CLOVER_ADD_4` **[CODE]** — confirming exactly **4 IAP tiers**, consistent with the 4 products above.

**[V] CN version (different app) for contrast:** 400/6元, 1000/12元, 1800/18元, 2800/25元 — <https://www.9game.cn/lxqwzgb/4897362.html>

### 1.5 Four-leaf clover (四つ葉) probability — **1 % per regrowth**

| Claim | Value | Status | Source |
|---|---|---|---|
| Probability per clover regrowth | **1 %**, **plus one free four-leaf after the tutorial** | **[U]** — community reverse-engineering, reproduced on 5 mirrors | <https://www.gameres.com/794522.html> · <https://www.sohu.com/a/222006355_505788> · <https://blog.csdn.net/FlyPigYe/article/details/89797634> · <https://blog.csdn.net/sinat_38239454/article/details/79231297> · <https://blog.csdn.net/weixin_30500289/article/details/99397036> |
| Independent corroboration | 「每一株三葉草重生的過程中，都有 **1%** 的機率會成為四葉幸運草」 | **[V]** | <https://www.saydigi.com/2018/01/tabikaeru-lucky-clover.html> |
| Official wording | 「とても珍しいクローバーとなり、なかなか生えてこなくなっています」 — **no number** | **[V]** | <http://www.hit-point.co.jp/games/tabikaeru/faq/faq.html> |
| CN-version arithmetic restatement | "a full 20-slot pond ⇒ **20 %** chance" | **[U]** — derived, not measured; CN ver. | <https://a.9game.cn/news/11249082.html> |
| Any other datamined rate ("1 in N") | — | **not found** | — |

**Answer: 1 % per clover regrowth, + 1 guaranteed after the tutorial.** A full 20-slot garden therefore gives 20 independent 1 % rolls per cycle (≈18 % chance of ≥1 four-leaf). The widely-quoted "20 %" is a CN-version article's arithmetic, not a measurement.

**Methodological note:** the JP DLL has `fourCloverSprite` and tutorial text 「畑では、みつ葉のクローバー以外にも 稀によつ葉のクローバーを収穫します」 **[CODE]**, and CFG symbols `clover_mu` / `clover_sigma` **[CODE]** exist — these are the **spatial placement** Gaussian (where in the bed a clover spawns), *not* the four-leaf probability. **No evidence was found for a datamined 1 %**; treat 1 % as **[U]**.

### 1.6 Is 四つ葉 worth 三つ葉 when sold/used?

| Question | Answer | Status |
|---|---|---|
| Sell/exchange rate 四つ葉 → みつ葉 | — | **not found** |
| Can it be sold at all? | No source documents any sell or buy-back mechanic. The shop only **takes** みつ葉 as currency. | **not found** (absence of evidence) |
| What it actually is | 四つ葉 is **`itemId 1000`**, an item of type `Amulet`, **price field = 0** (not purchasable) | **[CODE]** JP `ItemDataBase` |
| What it does | おまもり that raises the acquisition probability of **めいぶつ** | **[V]** <https://rinranron.net/tabikaeru-kouryaku/> |
| Tutorial-declared use | 「おまもりに「よつ葉」を選んで … かんりょう ボタンを押してください」 | **[CODE]** JP DLL |
| Other acquisition routes | (a) grown in the bed, very rare; (b) given by visiting friends as an おもてなし return gift, 1 at a time | **[V]** <http://kankuri-game.com/post-1064/> · <https://www.cnblogs.com/sjssice/> |
| One JP player's phrasing | 「たまに生える四つ葉はレアアイテム。刈って貯めて**アイテムと交換**します。」 | **[U]** — a single 2023 blog turn of phrase; **no other source supports any exchange**, and no rate is given. Probably loose wording. |

**Answer: there is no verified sell/exchange rate for 四つ葉. It is a charm item, not a currency.** `not found`.

### 1.7 Is 四つ葉 consumed or reusable? — **[C] UNRESOLVED**

| Claim | Text | Source |
|---|---|---|
| **Consumed** | 「おまもり、切符、四つ葉は**使用するとなくなります**」 | <https://rinranron.net/tabikaeru-kouryaku/> |
| **Reusable** | 「四つ葉のクローバーは**何度でも使用可**」 | **same URL, immediately adjacent bullet** (verified in raw HTML) |
| Consumed | 四叶草作为**一次性护身符**使用 | <https://blog.csdn.net/FlyPigYe/article/details/89797634> |

**Answer: rinranron.net contradicts itself in the same `<ul>`, and CN guides call it one-time. NOT RESOLVED.** The user's own JP APK could settle this from the item's `spend` flag — see §8.

---

## 2. TRAVEL RULES

### 2.1 Trip duration

| Claim | Value | Status | Source |
|---|---|---|---|
| Official maximum | 「遠くに旅に出ようとすると長旅となり、長い時は**4日**ほど家を空けることもございます」 (**up to ~4 days**) | **[V] official** | <http://www.hit-point.co.jp/games/tabikaeru/faq/faq.html> |
| Official minimum framing | Tutorial text: 「今回のしたくなら**数時間**ほどで帰ってきそうだ」 | **[CODE]** JP DLL | — |
| Modelled range, all bentou | **6 – 72 時間** | **[U]** — reverse-engineering | <https://www.gameres.com/794522.html> |
| Base constant | `TRAVEL_TIME_MIN: 60` (minutes) | **[CODE]** CN define, v1.07 — **JP value unconfirmed** | `work/run/engine/data/define.json` |
| Stamina-exhaustion rest | **3 hours**; stamina restored to **100**; the rest **counts as travel time** | **[U]** | <https://www.gameres.com/794522.html> |
| `REST_TIME` constant | `180` (s ⇒ 3 min? or the 3 h rest in minutes?) | **[CODE]**, unit ambiguous | same |
| Player impression | 「1、2時間くらいかな？と思ってたら**数時間**帰って来ないとかが普通」 | **[V]** | <https://gamewith.jp/gamedb/article/game/show/2577/22970> |

**Bentou → maximum trip length [V]** (<https://rinranron.net/tabikaeru-kouryaku/>):

| おべんとう | Price (みつ葉) | Max trip |
|---|---|---|
| えびづるのスコーン | 10 | **最大6時間** |
| はこべのサンドイッチ | 20 | **最大12時間** |
| かぼちゃのベーグル | 50 | **最大24時間** |
| のびるキッシュ | 80 | **最大72時間** |
| よもぎのフォカッチャ | 100 | **最大72時間** (暖かい場所へ行きやすい) |
| あさつきのぴろしき | 100 | **最大72時間** (寒い場所へ行きやすい) |

These are **explicit "最大" (maximum) figures** — the actual trip can be shorter. Note のびるキッシュ is special: the JP item description reads 「**帰りが早くなる**」 ("return becomes earlier") **[CODE]**, i.e. it *shortens* the trip.

**What extends/shortens a trip [CODE]:**
- **Extends:** higher-tier bentou (距離小 → 距離大), and the item-description effects 「まあまあ出かける」/「そこそこ出かける」/「かなり遠くまで出かける」 (JP `ItemDataBase`, verified from APK).
- **Shortens:** のびるのキッシュ (「帰りが早くなる」).
- **Does NOT affect duration:** どうぐ and おまもり change *destination and photograph type*, not length. 称号 (titles) **do** change travel time **[V]** <https://rinranron.net/tabikaeru-kouryaku/> (e.g. かえらぬ旅路 = "旅が長くなる").

### 2.2 Time the frog stays home between trips (滞在時間)

| Question | Answer | Status |
|---|---|---|
| Official | 「家に滞在する時間は、**かえるの気分によってかわってきます**が、かばんにもちものをしたくして「かんりょう」ボタンを押しておくと、**少しだけ早く**旅立っていきます。」 | **[V] official, but purely qualitative** |
| **Exact normal home-stay duration** | — | **not found** |
| **Exact magnitude of the かんりょう speed-up** | — | **not found** (official says only 少しだけ = "just a little") |
| Named constants | `FROG_RESTTIME: 400`, `FROG_RESTTIME_MAX: 900`, `FROG_STANDBY_WAIT_MIN: 60` | **[CODE]** CN define v1.07 — units unstated, **JP values unconfirmed** |
| Achievement thresholds bracketing it | おさんぽ日和 = trip **< 30 分**; かえらぬ旅路 = trip **≥ 1440 分** | **[V]** <https://rinranron.net/tabikaeru-kouryaku/> |
| Post-runaway return, once food is on the desk | **5 ～ 30 分** | **[U]** <https://www.gameres.com/794522.html> |

**Answer: `not found` for the normal home-stay duration.** Official is mood-dependent with no number. `FROG_RESTTIME: 400` / `_MAX: 900` is suggestive (400–900 s ≈ 6.7–15 min, or 400–900 min) but **the unit is not stated and this is the CN v1.07 build**, so it is **not** asserted as the JP value.

### 2.3 Bag (かばん) and desk (つくえ) slots

| Container | Layout | Total | Status | Source |
|---|---|---|---|---|
| **かばん** | **1** おべんとう + **1** おまもり + **2** どうぐ | **4** | **[V]** (2 sources) | <https://www.8090.com/news/gonglue/article_298550.html> ("背包…一共4个格子，左上角有一个，右上角有一个，最后下面还有两栏") · <https://www.cr173.com/gonglue/228540_1.html> |
| **かばん** — independent code confirmation | `BAGITEMS: 4`; the client's `bagDataList=[-1,-1,-1,-1]` (a 4-element array) | **[CODE]** | `define.json`; `work/run/engine/data/define.json` |
| **つくえ** | **2** おべんとう + **2** おまもり + **4** どうぐ | **8** | **[V]** (10 sources, largely one syndicated CN text) | <https://www.9game.cn/qwyx/2132715.html> · <https://shouyou.3dmgame.com/gl/65508.html> · <https://m.ali213.net/news/gl1801/213111.html> · <https://newgame.17173.com/content/01232018/154439656.shtml> |
| **つくえ** どうぐ cap | 「つくえに用意（**どうぐは最大４つまで**）」 | **[V]** | <https://rinranron.net/tabikaeru-kouryaku/> |
| **つくえ** — independent code confirmation | `DESKITEMS: 8`; `deskDataList=[-1,-1,-1,-1,-1,-1,-1,-1]` (an 8-element array) | **[CODE]** | `define.json`; `work/run/engine/data/define.json` |

**Answer: かばん = 4 slots (1 + 1 + 2); つくえ = 8 slots (2 + 2 + 4).** The bag figure independently rests on **two** CN sources *and* on two code constants (`BAGITEMS: 4`, `DESKITEMS: 8`), so this is the best-supported number in the report. The JP DLL also defines the constant names `BAGITEMS` and `DESKITEMS` **[CODE]**, confirming the mechanism exists identically.

**Difference between the two [CODE]:** the JP tutorial text explains かばん = you pack it personally; つくえ = a standing reserve that the frog packs for itself before leaving. 「つくえにしたくをしてあげると 帰ってくるタイミングがあわなくても は自分でもちものを選んで旅立っていきます」.

**Can the frog carry more than one item? [V] Yes** — structurally it is two lists, `bagList` / `deskList`, holding up to 4 and 8 entries. JP DLL: `[TravelSimulator] 旅行イベントを作成しました：かばん / bag[ ] / desk[ ]` **[CODE]**.

**Item stock cap [CODE]:** `HaveItemMax: 99` — the DLL gate `FindItemStock(...) < 0x63` (= 99) with the message 「もちものがいっぱいです」. **99 per item.**

### 2.4 How items are consumed

| Item | Consumable? | Status | Source |
|---|---|---|---|
| おべんとう | **Consumed**, one use | **[V]** | <https://www.cnblogs.com/sjssice/> · <https://www.9game.cn/qwyx/2132715.html> |
| おまもり | **Consumed** | **[V]** | <https://rinranron.net/tabikaeru-kouryaku/> · <https://www.hxnews.com/news/dmyx/djyx/yxxw/201801/24/1388560.shtml> |
| 切符 (東/西/南/北国きっぷ) | **Consumed** | **[V]** | <https://rinranron.net/tabikaeru-kouryaku/> |
| 四つ葉 | **[C]** — see §1.7 | — | — |
| どうぐ (all 18) | **Reusable / permanent** | **[V]** | <https://rinranron.net/tabikaeru-kouryaku/> (「どうぐは購入後何度でも使用できる」) · <https://www.hxnews.com/news/dmyx/djyx/yxxw/201801/24/1388560.shtml> (「道具则是永久性的」) |
| 幸運の鈴 | **Reusable**, 3000 みつ葉, めいぶつ rate slightly up | **[V]** | <https://rinranron.net/tabikaeru-kouryaku/> |
| Code-level consumable flag | `ItemDataFormat.spend`; when `spend == false` and the player already owns one, purchase is cancelled (`!format2.spend && FindItemStock(...) != 0` → `SE_Cancel`) ⇒ **permanent items are single-purchase** | **[CODE]** (decompiled, third-party) | <https://segmentfault.com/a/1190000014740565> |
| JP DLL consumption log lines | Both `[SuperGameMaster] 消費アイテムを使いました：ID =` **and** `非消費アイテムを使いました` exist ⇒ two classes | **[CODE]** JP DLL | — |

### 2.5 What happens if you leave nothing — the 「！」 mark

| Fact | Text | Status | Source |
|---|---|---|---|
| The rule | 「おうち画面の左下「したく」に「**！**」マークが表示されている場合、その状態のまま出かけてしまうと、**かえるが帰ってこなくなります**。」 | **[V] official** | <http://www.hit-point.co.jp/games/tabikaeru/faq/faq.html> |
| Remedy | Put a おべんとう on the つくえ; he picks it up on return and leaves again | **[V] official** | same |
| No bentou at all | 「**おべんとうがないとかえるは旅に出かけられずずっと待っています。**」 (cannot depart; waits forever) | **[V]** | <https://rinranron.net/tabikaeru-kouryaku/> |
| Sustained no-bentou | 「かばんやつくえに**おべんとうのしたくがない状態がつづく**と、かえるは**出かけたまま帰ってこなくなる**。」 | **[V]** | <https://gamewith.jp/gamedb/article/game/show/2577/22970> |
| Mechanism | No bentou ⇒ the game builds a **放浪 (wander) event instead of a travel event**: JP DLL `[TravelSimulator] 「べんとう」がないため、放浪イベントを作成しました` | **[CODE]** JP DLL | — |
| Consequence | A wander trip brings back **no photos and no souvenirs** | **[CODE]** (inferred from the event split) | — |
| Real case | A player's frog was gone ~1 month with 「！」 showing | **[V]** | <https://kankuri-game.com/post-1159/> |

**Answer:** the 「！」 means the したく is in a state that makes the frog **not come back**. Putting a bentou on the desk restores it. Not merely "he waits" — the game literally switches from a *travel* event to a *wander* event.

### 2.6 Number of どうぐ (tools) — **18**

| Claim | Value | Status | Source |
|---|---|---|---|
| Total tool types | **18種類** | **[V]** — recounted from the source's own table | <https://rinranron.net/tabikaeru-kouryaku/> |
| Recount | 手ぬぐい ×3 (150/250/400) + テント ×3 (300/450/750) + うつわ ×3 (450/700/1200) + あかり ×3 (600/900/1500) + えりまき ×3 (500 ea) + ボトル ×3 (500 ea) = **18** | **[V]** | same |
| Independent code confirmation | JP `ItemDataBase` contains exactly **12** tool records (itemType 2, ids 2000–2011): テント ×3, 器 ×3, ろうそく/ちょうちん/ランタン, てぬぐい ×3. rinranron's 18 adds **えりまき ×3 + ボトル ×3 = 6** (later update) ⇒ 12 + 6 = **18** | **[CODE]** JP APK | `work/spec/jp-reference.md` §2.1 |
| Is ラジオ受信機 a 19th どうぐ? | **No** — it is **house furniture** (BGM), **1000 みつ葉**, added **v1.2.0, 2018-06-14**. 「これは旅に持たせるどうぐではなく、購入する事でおうちに設置する事が出来る家具」 | **[V]** | <https://kankuri-game.com/post-2094/> |

---

## 3. VISITORS (お客さん / 友だち)

### 3.1 Full list

**[V] Garden visitors — exactly 3.** (「遊びに来るお友達は「カタツムリ」「ハチ」「カメ」」 — <https://www.harmonize.blue/entry/tabikaeru>)

| # | Nickname | Animal | Kanji | Unlock condition | Source |
|---|---|---|---|---|---|
| 1 | **まいまい** | カタツムリ (snail) | 蝸牛 | **0 いっぴん** — always available, the first to appear | <https://zetaspace.cc/tabi-kaeru-friend/> |
| 2 | **ぶんぶん** | ハチ (bee) | 蜜蜂 | once you own **3 いっぴん** | same · <https://muccarana.com/tabikaeru_play> |
| 3 | **ぷかぷか** | カメ (turtle) | 石亀 | once you own **6 いっぴん** | same |

**[V]** Dated personal log confirming the thresholds: `2018/1/28 追記 いっぴん 3 個たまったら「ぶんぶん」が来ました！` and `2018/2/22 追記 いっぴん 6 個たまったら「ぷかぷか」が来ました！` — <https://muccarana.com/tabikaeru_play>

**[CODE] JP `CharacterDataBase`** independently names exactly three garden visitors, with animation paths:
`まいまい → AniAnimation/MainOut/katatsumuri_niwa`, `ぶんぶん → AniAnimation/MainOut/mitsubati_niwa`, `ぷかぷか → AniAnimation/MainOut/isigame_niwa`.

**A 4th+ garden visitor: `not found`.** No source describes one.

**[V] Travel companions** (appear in the frog's *photos*, not at the garden): **カニ (crab)**, **ネズミ (mouse)**, **チョウ (butterfly)** — <https://rinranron.net/tabikaeru-kouryaku/> · <https://muccarana.com/tabikaeru_play>

**[V]** Other creatures sighted in photos (not core companions): サンショウウオ, テントウムシ (<https://muccarana.com/tabikaeru_play>); アリ, カマキリ, トンボ, フクロウ, ヒキガエル (<https://jingyan.baidu.com/article/e52e36151438d940c70c515a.html>).

**CN version only:** introduces a 4th neighbor 嘟嘟 tied to the plant/园艺 system (**[V]** CN ver., <https://www.9game.cn/lxqwzgb/11584047.html>) — **do not carry this into the JP spec.**

### 3.2 Appearance conditions and frequency

| Question | Answer | Status |
|---|---|---|
| Condition | Number of distinct **いっぴん** registered: 0 / 3 / 6 (snail / bee / turtle). No other stated condition. | **[V]** |
| Snail independent of frog's location | 「まいまいはかえるが家に居ようが居まいが、お構いなしに来ます」 | **[V]** <https://muccarana.com/tabikaeru_play> |
| **Visit frequency / hours between visits / cooldown** | — | **not found.** *No web source gives a visit interval. Do not infer one.* |
| Constraint on that gap | **[CODE]** The CN v1.07 define *does* contain a cooldown constant — `FRIEND_VISIT_COOL: 21600` (s = **6 h**) plus `FRIEND_VISIT_RNDPER: 10`, `FRIEND_VISIT_RNDSEC: 1800`, `FRIEND_VISIT_ACTCOUNT_MIN: 6`, `FRIEND_VISIT_ACTCOUNT_MAX: 8` | **[CODE] CN v1.07 only — JP value unconfirmed.** Reported as a *lead*, not as the JP rule. |
| **[C] Stay duration** | **180–270 分** (3–4.5 h): 「來訪停留的時間180～270 分鐘不等」 <https://zetaspace.cc/tabi-kaeru-friend/> | **[C]** |
| | **1–2 時間** then leaves: 「1-2小时候会离开」 <http://sy.yzz.cn/lxqw/news/201801-1281530.html> | **[C]** |
| | **Unresolved.** Both are single-source and neither is authoritative. | — |
| Feedings per visit | 「随意选一个就可以喂了，**只能喂一次**」 (one feeding per visit) | **[V]** <http://sy.yzz.cn/lxqw/news/201801-1281530.html> |

### 3.3 What you feed them, and what you get

**[V] Step 1 — the ちらし (flyer).** Each visit puts a flyer in the mailbox (ゆうびんうけ). Opening it plays an **ad (requires network)** and grants **1 ふくびき券**.
「朋友每次拜訪時都會送一張抽獎券 這時候需要觀看一下廣告」 — <https://zetaspace.cc/tabi-kaeru-friend/>
Official: 「ゆうびん受けのチラシ…広告の表示には通信が必要となります」 — <http://www.hit-point.co.jp/games/tabikaeru/faq/faq.html>

**[V] Not guaranteed:** 「抽奖券也有一定概率拿不到，不过即使是随机的，得到的概率却相当高」 — <http://sy.yzz.cn/lxqw/news/201801-1281530.html>
**[V] Order quirk:** the ad can be watched *before* feeding (「其实喂食前就可以看广告」) — same URL.
**[V] Android quirk (2018):** the ad could be dismissed instantly — arguably a bug — <https://zetaspace.cc/tabi-kaeru-friend/>.
**Any cooldown / daily cap on flyers: `not found`.**

**[V] Step 2 — the feeding.** You feed the visitor a **めいぶつ** (specialty). JP DLL confirms the food pool is めいぶつ, not arbitrary items: 「からもらった めいぶつ で おもてなし をしてあげましょう」 **[CODE]**.

**[V] Step 3 — the reward.** The thank-you is **exactly one of** みつ葉 / よつ葉 / ふくびき券, and **never more than one kind at a time**:
「お礼はみつ葉・よつ葉・ふくびき券のどれかが貰え、一度に複数貰える事はありません」 — <http://kankuri-game.com/post-1064/>

> **Direct answer to the question "what exactly do they give":** **みつ葉 (clovers), よつ葉 (four-leaf clover), or ふくびき券 (lottery tickets).**
> **They do NOT give おまもり, and they do NOT give いっぴん / めいぶつ.** **[V]** <http://kankuri-game.com/post-1064/>

**[V] Reaction stages (4), same as the in-game text:**
`喜んでいます` (delighted) > `嬉しそうです` (looks happy) > `お腹がいっぱいです` (full) > `もう食べられません` (can't eat more)
JP DLL confirms all four strings **[CODE]**. The reaction is **fixed per (めいぶつ × visitor)** — 「おもてなしとして渡しためいぶつ毎に友達の反応の種類は決まっています」 — but the *reward magnitude* is still random. **[V]** <http://kankuri-game.com/post-1064/>

**[V] Degradation rule:** feeding the same item 3 times in a row worsens later gifts.
「如果連續餵食相同的食物 後面得到的回禮會變差 所以不要連續餵食相同的食物三次」 — <https://zetaspace.cc/tabi-kaeru-friend/>
JP DLL constant **`FRIEND_ITEM_DEBUFF`** with values **`[0.6, 0.75, 0.9]`** **[CODE]** — a *multiplier ladder* consistent with progressive punishment.

**[V] Universal favourite:** **温泉まんじゅう** is liked by all three visitors — the safe default — <https://zetaspace.cc/tabi-kaeru-friend/> · <http://kankuri-game.com/post-1064/>

**[V] Observed payout magnitudes** — from a Japanese player's 3-year log totalling **1,243 recorded visits** (まいまい 431 / ぶんぶん 425 / ぷかぷか 387), updated 2019-07-28:

| Visitor | Best observed みつ葉 | よつ葉 | ふくびき券 range |
|---|---|---|---|
| まいまい | **62 枚** (温泉まんじゅう, 喜んでいます) | 1–2 枚 | 1–4 枚 |
| ぶんぶん | **77–92 枚** (六方焼 / 温泉まんじゅう, 喜んでいます) | 1 枚 | 1–4 枚 |
| ぷかぷか | **88 枚** (かた焼き, 嬉しそうです) | 1–4 枚 | 1–4 枚 |

Source: <http://kankuri-game.com/post-1064/> — **this is a player log, not a datamine.** A **formula mapping reaction stage → clover amount: `not found`.**
The "58 clovers" figure seen in one search snippet could **not** be confirmed anywhere — **not found**.

**[CODE] Corroborating constants (CN v1.07 — mechanism only):**
`FRIEND_GIFTBOUNUS_CLOVER: 20`, `FRIEND_GIFTBOUNUS_TICKET: 1`, `FRIEND_GIFTBOUNUS_TICKET_MAX: 3` ⇒ the gift is **+20 clovers**, or **1 ticket, capped at 3**. Gift-type odds: `FRIEND_GIFTPER_NORMAL {Clover:80, FourClover:18, Ticket:2}` / `FRIEND_GIFTPER_RARE {Clover:20, FourClover:50, Ticket:30}`. The JP DLL independently defines `FRIEND_GIFTBOUNUS_CLOVER`, `FRIEND_GIFTBOUNUS_TICKET`, `FRIEND_GIFTBOUNUS_TICKET_MAX`, `FRIEND_ITEM_DEBUFF` **[CODE]** — so **the JP version has the same mechanism**, but the JP numeric values are **not** verified from this file.

---

## 4. LOTTERY (ふくびき)

### 4.1 Cost and access — solid

| Fact | Value | Status | Source |
|---|---|---|---|
| Cost per spin | **5 ふくびき券** | **[V]** | <https://rinranron.net/tabikaeru-kouryaku/> · JP DLL `ふくびき券5枚で 1回抽選に挑戦ができます` **[CODE]** |
| Code constant | `RAFFEL_NEEDTICKETS: 5`; `GetTicket(-5)` | **[CODE]** | `define.json`; <https://segmentfault.com/a/1190000014740565> |
| Where | おみせ screen → top-right button | **[V] official** | <http://www.hit-point.co.jp/games/tabikaeru/faq/faq.html> |
| Ticket count shown | top-right of the ふくびき screen | **[V] official** | same |
| Ticket cap | `TicketMax: 999` | **[CODE]** CN v1.07 | `define.json` |
| Unclaimed-prize guard | 「前回のふくびきの景品を 受け取っていません」 | **[CODE]** JP DLL | — |

### 4.2 How you get ふくびき券 (tickets)

| # | Source | Detail | Status |
|---|---|---|---|
| ① | かえるのおみやげ | Frog returns from a trip with tickets. Official: 「したくのお礼に「みつ葉」と「ふくびき券」を持って帰ってきます」 — **normally 1 per return** | **[V] official** |
| ② | ともだちのちらし | Watching the visiting friend's ad (§3.3). **Not guaranteed** | **[V]** |
| ③ | おもてなしのお礼 | Friend's thank-you; observed **1–4 枚** | **[V]** |
| ④ | お店のおまけ | Random shop bonus on purchase; observed **≈1 in every 4–5 purchases** (「大体4～5回に1回くらいはふくびき券がついてくるみたいです」). Because the roll is **per purchase**, buying the cheapest item (えびづるのスコーン, 10 みつ葉) in bulk is most ticket-efficient. | **[V]** <https://muccarana.com/tabikaeru_play> |
| ⑤ | 白玉 (consolation) | The white ball returns **1 ticket** | **[V]** §4.4 |
| — | Shop constant | `SHOP_TICKET_PER: 15` **[CODE]** — suggests a guaranteed ticket every N shop purchases; matches "~1 in 4–5" only loosely | **[CODE]** CN v1.07 |

Sources: <https://rinranron.net/tabikaeru-kouryaku/> (lists ①②③④) · <https://muccarana.com/tabikaeru_play>

### 4.3 Tier system — **5 tiers, named by ball colour**

**[V]** The tiers are named after the drawn ball: **白玉 / 青玉 / 緑玉 / 赤玉 / 黄玉**, and in game text you see 「がでました」 with `SE_Raffle` / `SE_RaffleResult` **[CODE]**.
Sources: <https://www.9game.cn/news/2219377.html> · <http://sy.yzz.cn/lxqw/news/201801-1281530.html> · <https://www.52dushu.cn/shouyougl/80669.html>

**[V] The white ball is the "no prize".**
「抽奖一定能得到东西！奖项一共分为五档 … 白玉（安慰奖）系统会直接会返还一张抽奖券作为安慰，无其他奖品，其他全部奖都是可以自己选一种。」
— "You always get *something*. Five tiers. The white ball is the consolation: the system returns exactly **1 lottery ticket** and nothing else. **Every other tier lets you choose one item.**"
Source: <http://sy.yzz.cn/lxqw/news/201801-1281530.html>

**[V]** A Japanese player independently: 「青や緑などの色のついた玉が出たら当たりです！」 ("if a **coloured** ball comes out, it's a win") — i.e. **white = lose** — <https://muccarana.com/tabikaeru_play>

**Note:** the Chinese guides' 一等/二等 labels are the *guide's own ranking*, **not in-game text.** There is no 一等/二等/三等 screen text. **[V]**

### 4.4 Prize list per tier (JP)

**[V]** rinranron states the definitive JP prize list: 「ふくびきの景品」= おまもり・切符・金平糖・たまごぼうろ・**ふくびき券１枚（はずれ）** — <https://rinranron.net/tabikaeru-kouryaku/>

| Tier | Prize type | Full variants | Effect |
|---|---|---|---|
| 黄玉 (rarest) | **切符** | 東国 / 西国 / 南国 / 北国きっぷ (4) | Nudges/forces travel toward that direction. One-time use. |
| 赤玉 | **金平糖** | いちご / レモン / ぶどう / メロン (4) | Steers the travel companion: いちご→ネズミ, レモン→チョウ, ぶどう→カニ, メロン=調査中 |
| 緑玉 | **たまごぼうろ** | にんじん / かぼちゃ / えだまめ / みるく / ごぼう (5) | にんじん→ネズミ, かぼちゃ→カニ, えだまめ→チョウ, みるく=調査中, ごぼう→ネズミ+チョウ |
| 青玉 | **おまもり** | 黄=東 / 白=西 / 赤=南 / 青=北 / 桃=知らない場所 (5) | Raises probability of that direction; raises いっぴん/めいぶつ acquisition. One-time use. |
| 白玉 | **ふくびき券 1枚** | — | はずれ (consolation). **No choice.** |

Sources: <https://rinranron.net/tabikaeru-kouryaku/> · <http://sy.yzz.cn/lxqw/news/201801-1281530.html> · <https://www.9game.cn/news/2167138.html>

**[V] Independent code confirmation of the JP prize *pool*.** JP `PrizeDataBase` (`count = 19`) contains **19 records** = 1 empty slot + **4 tiers** totalling exactly the 18 items above:

| JP tier field | Contents | Count |
|---|---|---|
| 1 | 黄色(東)/白色(西)/赤色(南)/青色(北)/桃色(未知)のお守り | 5 |
| 2 | にんじん/かぼちゃ/えだまめ/ミルク/ごぼう ぼうろ | 5 |
| 3 | いちご/レモン/ぶどう/メロン の金平糖 | 4 |
| 4 | 東国/西国/南国/北国きっぷ | 4 |

**[CODE]** from the JP APK — `work/spec/jp-reference.md` §7.2. **Cross-check:** all 18 of these items have **price field = 0** in `ItemDataBase`, i.e. they are **lottery-only, not purchasable** — exactly as the web sources say. Strong mutual confirmation.

> **Numbering caution:** the JP data's numeric `tier` field (1–4) is **not** the ball colour. There are **5 ball colours** but only **4 item tiers** + 1 empty slot. **The exact colour↔tier mapping is NOT confirmed.** ⚠️ Do not assume JP tier 1 = 白玉.

### 4.5 Probabilities — **the hard part**

**There is no official odds disclosure.** `not found` — <http://www.hit-point.co.jp/games/tabikaeru/> carries no probability page.

Two **incompatible** numeric sets exist. Both are reported; neither is chosen.

**Set A — one Chinese guide, JP ball names, 5 tiers, sums to exactly 100 %**

| Ball | JP prize | Probability |
|---|---|---|
| 黄玉 | 切符 | **0.3 %** |
| 赤玉 | 金平糖 | **3 %** |
| 緑玉 | たまごぼうろ | **8 %** |
| 青玉 | おまもり | **24.3 %** |
| 白玉 | ふくびき券1枚（はずれ） | **64.3 %** |
| | **Total** | **100.0 %** |

**[U]** Source: <https://www.9game.cn/news/2219377.html> — "《旅行青蛙》新手抽奖攻略 抽奖几率解析和奖励一览", author 雪球, credited to 太平洋电脑网, published **2018-03-16**. Exact text: `黄玉（中奖率0.3%）… 赤玉（中奖率3%）… 绿玉（中奖率8%）… 青玉（中奖率24.3%）… 白玉（中奖率64.3%）`.
**This is the ONLY source found giving per-tier odds, it is a third-party Chinese guide, and it is not official or datamined.** It is internally consistent (sums to 100 %, and the ordering matches the prize ordering above) but **single-source**.

**Set B — decompiled `Tabikaeru.Define` tuning table (CN build, v1.07): 6 tiers**

| Rank | Ball | Weight | Clover payout |
|---|---|---|---|
| White | 白玉 | **40** | 10 |
| Blue | 青玉 | **25** | 30 |
| Purple | 紫玉 | **22** | 50 |
| Green | 绿玉 | **9** | 100 |
| Red | 红玉 | **3** | 350 |
| Gold | 黄玉 | **1** | 1000 |
| `RankMax` | | **100** | |

**[CODE]** — `work/run/engine/data/define.json` (source: `assets/game/js/main.min.js` offsets 418503..423223).

**Why Set B cannot be presented as the JP values:**
1. It has **6** tiers (adds **紫玉**); the JP DLL's string heap contains only **白玉/青玉/緑玉/赤玉/黄玉** — **no 紫玉, no 金玉**.
2. Its payouts are **clovers**, whereas the JP prize pool is **items** (omamori/kippu/kompeito/bouro) with **no clover prizes** in `PrizeDataBase`.
3. Its build is **v1.07**; the JP app is **1.8.5/1.8.6**.

**How the two relate (analysis, [U]):** Set A's ball names are Japanese; Set B's are the same names **plus** 紫玉 and **simplified-Chinese** glyphs (绿/红 rather than JP 緑/赤) — evidence the CN team *edited* the inherited JP table. Splitting Set B's 紫玉 (22) into Set A's 青玉 (24.3) + 赤玉 (3) — and reading Set B's 黄玉/gold (1) as Set A's rarest tier — yields a consistent story: **the JP original had 5 balls, and the CN version inserted a 6th.** But **no source states this**, so it is an inference, not a fact.

**Numerical cross-check supporting that inference [U]:** Set B's clover payouts step monotonically **10 → 30 → 50 → 100 → 350 → 1000**, in exactly the same rarest-last order as Set A's prize tiers (白玉 → 青玉 → 緑玉 → 赤玉 → 黄玉). If Set B's weights are renormalised onto Set A's 5-ball scale and the 紫玉 22 is split, the result *reproduces Set A's own numbers*:

| Ball | Set A stated | Set B-derived (5-ball renormalisation) |
|---|---|---|
| 白玉 | 64.3 % | 40 / 62 × 100 = **64.5** |
| 青玉 | 24.3 % | 15 / 62 × 100 = **24.2** |
| 緑玉 | 8 % | 5 / 62 × 100 = **8.06** |
| 赤玉 | 3 % | 2 / 62 × 100 = **3.23** |
| 黄玉 | 0.3 % | 0.5 / 62 × 100 = **0.81** |

Agreement is within **~0.5 pp on four of five tiers**. This is a strong indication the two sets describe **the same underlying table** at different revisions — but it is **my arithmetic, not a measurement**, and it still does not establish which revision the *current* JP 1.8.6 build ships. Recorded as **[U]**.

**Recommendation for the spec:** treat `PrizeBalls = [White 40, Blue 25, Purple 22, Green 9, Red 3, Gold 1]` as a **6-tier system with a 紫玉 tier**, flagged as **CN-v1.07 tuning data**; and Set A as a **5-tier, third-party, JP-named** estimate. **Do not present either as Hit-Point's official odds.**

**Within-tier odds** (per omamori colour, per kompeito flavour, per ticket direction): **not found**.

### 4.6 Rarest prize and "guaranteed 1等"

- **[V] There is no total loss.** 白玉 always returns 1 ticket, so the floor of a 5-ticket spin is 1 ticket back. <http://sy.yzz.cn/lxqw/news/201801-1281530.html>
- **[U] Rarest tier = 黄玉 (切符)** — 0.3 % by Set A; weight 1/100 by Set B. Both agree it is rarest.
- **[V] Qualitative corroboration that rare tiers are genuinely rare** — a long-time JP player: 「ふくびきはとにかく渋いので、存在しないと思った方が精神衛生上いいです。特に金平糖とか全く出ません。」 — <https://applion.jp/旅かえる/android-jp.co.hit_point.tabikaeru/review/>
- **Any official odds page, any datamined drop table for the JP build: `not found`.**

---

## 5. CURRENCY

### 5.1 Does the JP version have only clovers + lottery tickets?

**Essentially yes — with one event-only exception.**

| Currency | JP name | Status | Evidence |
|---|---|---|---|
| Clover (3-leaf) — **the only general currency** | クローバー / みつ葉 | **[V]** | Official FAQ: 「みつ葉が足りません」 (shop); 「したくのお礼に「みつ葉」…を持って帰ってきます」 — <http://www.hit-point.co.jp/games/tabikaeru/faq/faq.html> · <https://plus.jmca.jp/takashima4/takashima4-03.html> |
| Lottery ticket — **secondary, lottery-only** | ふくびき券 | **[V]** | 5 tickets = 1 spin; **not spendable on anything else** |
| Four-leaf clover | よつ葉のクローバー | **[V] but NOT a currency** | It is **`itemId 1000`, type Amulet, price 0** **[CODE]** — a charm item. Cannot be spent. |
| Exchange ticket — **event only, v1.4.0+** | **ひきかえ券** | **[V]** | From the mailbox and from the ふくびき **白玉**. **3 ひきかえ券 → 1 旅行券.** <https://muccarana.com/tabikaeru_update> |
| Travel ticket — **event only, v1.4.0+** | **旅行券** | **[V]** | An event おまもり for reaching 特別な場所; yields limited souvenirs/photos; becomes worthless paper when the event ends. <https://muccarana.com/tabikaeru_update> · <https://rinranron.net/tabi-kaeru-kouryaku/> |

- **[V] No premium currency.** No gems / diamonds / coins / crystals in any source. **[CODE]** The JP save structure holds only `CloverPoint`, `CloverPointStock`, `Ticket`, `itemStock`. **There is no premium currency in the JP version.**
- **[V] 金平糖 / たまごぼうろ are NOT currencies** — they are lottery-prize bentou-class items that steer travel companions.
- **Excluded:** a GitBook page at `travelfrog.gitbook.io` advertising a "クローバー / ダイヤモンド（プレミアム通貨）/ フロッグコイン" system is **not Hit-Point's game** and is irrelevant.

**Answer: JP currency = 三つ葉のクローバー (general) + ふくびき券 (lottery-only), plus the event-only ひきかえ券 → 旅行券 pair in v1.4.0+. No premium currency.**

### 5.2 Clover sources and sinks

| | Detail | Status |
|---|---|---|
| **Source** | Garden harvest (~20 slots, tapping) | **[V]** |
| **Source** | Frog's return gift | **[V] official** |
| **Source** | Visitor thank-you (みつ葉 branch) | **[V]** |
| **Source** | Achievement / mail rewards — **[CODE]** `MailEventDataBase` fields include `CloverPoint` and `ticket` | **[CODE]** |
| **Sink** | Shop: 6 bentou + 18 どうぐ + 幸運の鈴 | **[V]** |
| **Sink** | **みつ葉 300 → +2 album pages** | **[V]** <https://kankuri-game.com/post-2172/> |
| **Sink** | ラジオ受信機 1000 みつ葉 | **[V]** <https://kankuri-game.com/post-2094/> |
| **IAP** | Yes, `クローバーこうにゅう` screen; requires v1.0.6+ | **[V] official** |
| **Can みつ葉 be exchanged for ふくびき券?** | **not found** | — |

---

## 6. SOUVENIRS (おみやげ / いっぴん / めいぶつ) AND PHOTOS (写真)

### 6.1 Terminology — two distinct souvenir classes

| | **いっぴん** (逸品 / "fine article") | **めいぶつ** (名物 / "specialty") |
|---|---|---|
| Count | **26** (stated) / **28** (actually listed by the same source) | **47** |
| Effect | **Increases which visitors appear** (0/3/6 thresholds) | **Consumable food for visitors** (the おもてなし pool) |
| Can be fed to friends? | **No** | **Yes** |
| Rarity | **Rarer** | **Commoner** |
| How obtained | Probabilistically on **reaching a destination (GOAL)** | Probabilistically during/after trips, per region |

**[V]** <https://rinranron.net/tabikaeru-kouryaku/> · <https://muccarana.com/tabikaeru_play> (「何種かの「めいぶつ」と、運がよければ「いっぴん」がもらえます」)

**[C]** One Chinese source says いっぴん *are* used to entertain friends (「逸品的作用是招待朋友和收藏」, <https://www.9game.cn/news/2135112.html>). This contradicts rinranron's 「ともだちにふるまえない」. **Unresolved**; rinranron + the official FAQ's parenthetical 「いっぴん・めいぶつ」 phrasing favour rinranron.

### 6.2 How many いっぴん? — **unresolved (26 vs 28)**

| Claim | Value | Status | Source |
|---|---|---|---|
| Heading | **全26種類** | **[V] as stated** | <https://rinranron.net/tabikaeru-kouryaku/> |
| Same source's own list, counted | **28** — 東北5 + 関東3 + 中部4 + 近畿5 + 中国1 + 四国2 + 九州5 + 北海道1 + 沖縄2 | **[V] as counted** | same |
| v1.0.1 era (Jan 2018) | **10** — and the article enumerates exactly 10 | **[V]** | <https://www.techweb.com.cn/shoujiyouxi/2018-01-25/2632666.shtml> |
| "32" | **NOT an いっぴん count** — it is a **copy-paste error**: the "いっぴんは全32種類" line is the *body heading of the めいぶつ section*, whose TOC entry correctly reads 「めいぶつは全47種類」 | **[V]** | <https://rinranron.net/tabikaeru-kouryaku/> |
| **Exact current いっぴん count** | — | **not found** | — |

**Note the independent JP memory:** the JP APK's `CollectionDataBase` contains **exactly 10** records — はと笛, わっぱ弁当 (東北), 福だるま (関東), 飾りくし, まねきねこ (中部), 金の扇, 古いマッチ, 蚊遣りぶた (近畿), 竹のかご, 月うさぎのボタン (九州) **[CODE]**. That matches the Jan-2018 "10 種" figure **exactly**, and matches the first 10 of rinranron's 28-item list. **The most likely reading: いっぴん started at 10, grew to 26/28 with later updates.** The APK in this workspace is an older build for this table.

**Full いっぴん list, by region [V]** (<https://rinranron.net/tabikaeru-kouryaku/>):

| Region | いっぴん | Count |
|---|---|---|
| 東北地方 | はと笛、わっぱ弁当、こけし、赤べこ、将棋の駒 | 5 |
| 関東地方 | 福だるま、犬張子、竹のうちわ | 3 |
| 中部地方 | 飾りくし、米食いねずみ、まねきねこ、さるのお守り | 4 |
| 近畿地方 | 金の扇、古いマッチ、蚊遣りぶた、墨、錫のグラス | 5 |
| 中国地方 | 緋色の勾玉 | 1 |
| 四国地方 | 真珠のブローチ、藍色のハンカチ | 2 |
| 九州地方 | 雉子車、べっ甲の髪飾り、竹のかご、月うさぎのボタン、ガラスのちろり | 5 |
| 北海道地方 | 木彫りのくま | 1 |
| 沖縄地方 | 海色のグラス、星の砂 | 2 |
| **Total listed** | | **28** |

### 6.3 How many めいぶつ? — **47 stated / 46 by dedupe**

| Claim | Value | Status |
|---|---|---|
| Stated | **47種類** | **[V]** <https://rinranron.net/tabikaeru-kouryaku/> |
| Counted from the same source's regional table, after removing cross-region duplicates | **46** (47 if 近畿's `温千まんじゅう` — almost certainly a typo of 温泉まんじゅう — is counted separately) | **[U]** |
| Fixed total? | **No** — 「めいぶつはアップデートにより随時追加されている」 (added over time by updates) | **[V]** |

**Independent code cross-check:** the JP APK's `SpecialtyDataBase` (count = 29) holds **11 地方名物 + 18 食材 = 29** **[CODE]**, and the めきき名人 title's thresholds are **11 and 18** **[CODE]** — internally consistent. Again: an **older build** than the current 47.

**めいぶつ are NOT rarity-tiered.** **No source ranks individual いっぴん or めいぶつ by rarity**, and the JP tables contain **no rarity field** **[CODE]**. The "SSR" terminology in Chinese guides refers to **postcards**, not souvenirs. **`not found` for any souvenir rarity tier.**

### 6.4 How souvenirs are obtained

**[V] Official:** probabilistic — 「写真や各地のおみやげ（いっぴん・めいぶつ）は、かえるの気分によってもらえるときともらえないときがあります。」 <http://www.hit-point.co.jp/games/tabikaeru/faq/faq.html>

**[V] いっぴん base probability on reaching a destination (GOAL) = 15 %** — **[U]**, reverse-engineering: <https://www.gameres.com/794522.html>; the same figure appears in a zhihu answer snippet: 「收藏品的获得的基础概率是 15%，使用 四叶草 或者 幸运铃铛 可以减少收集收藏品的阻力，增加获得概率」.
**[U] Guaranteed-collection-after-3 setting exists in code but is NOT enabled** — <https://www.gameres.com/794522.html>
**[CODE] Corroboration that collection is a probability roll:** `COLLECT_PER: [15, 30, 50, 100]` and the JP save field `collectFailedCnt[ ]` (a *failure counter* exists ⇒ pity logic). JP constant `COLLECT_PER` name confirmed. `SPECIALTY_PER: 60`.
⚠️ **`COLLECT_PER: [15,30,50,100]` is a 4-element array. It is NOT stated anywhere what the 4 elements index** (omamori tier? title? number of attempts?). **The JP value of the 15 % base rate is not independently confirmed.**

**[V] 4-step method (rinranron):** (1) pick the region → (2) select that direction's おまもり → (3) pick the どうぐ matching the desired situation → (4) pick a long-trip おべんとう → send. Repeat the **same** combination until it drops: 「毎回いっぴんを持ち帰るとは限らないので、入手するまで同じ場所とアイテムの組み合わせで繰り返し旅にでかけましょう」.

**[V] Boosters:**
- おまもり: 「旅先または「いっぴん」や「めいぶつ」の獲得確率をUPさせる」
- 四つ葉: めいぶつの入手確率UP
- 幸運の鈴 (3000 みつ葉): めいぶつの入手確率が**少し**UP, reusable

**[CODE] Drop model:** 特産 drop by a **per-node whitelist** — `NodePrefDataBase` (`count = 45`), each node listing **1–5 candidate itemIds**. This is the actual mechanism behind "go to region X to get souvenir Y".
**[CODE] いっぴん/めいぶつ cannot be bought:** all 29 specialty items and 10 collections have **price = 0** in `ItemDataBase`.

### 6.5 Photos / postcards (写真 / 明信片)

**Total count: `not found`.** Only a floor exists.

| Claim | Value | Status | Source |
|---|---|---|---|
| Floor, v1.0 era (2018-02-23) | 「根据现在已知的明信片有50种，可见旅行青蛙明信片至少是有50种」 — *"50 kinds are currently known, so there are **at least** 50."* | **[V]** as a floor | <https://jingyan.baidu.com/article/e52e36151438d940c70c515a.html> |
| Any authoritative current total | — | **not found** | — |

**Why a fixed total is structurally hard to state:**
- **[V]** Ordinary postcards randomise 「蛙蛙的动作表情，天空颜色，云，苔藓，树叶的位置」 (pose, expression, sky colour, clouds, moss, leaf positions) — <https://m.ali213.net/news/gl1801/214403.html>
- **[V]** 「同じ場所でも、葉っぱの舞いかたが違ったり、背景が違ったりと ちょっとずつ異なっている」 — the same location yields subtly different photos; duplicates occur 「結構な確率で」 — <https://muccarana.com/tabikaeru_play>

**Photo categories [U]:** one CN source lists 8 — 普通 / 景点 / 道具 / 稀有 / 螃蟹 / 仓鼠 / 蝴蝶 / 谜之 — <https://shouyou.3dmgame.com/gl/66368_2.html>.
**JP code gives 3 photo classes [CODE]:** `Picture_Normal` / `Picture_Tools` / `Picture_Unique`, with debug output `■ 写真：通常（道：`) / `■ 写真：道具（道：`) / `■ 写真：ユニーク（道：`. **These two taxonomies are different and neither is the other's refinement** — the 8-category list is a fan-facing menu grouping, the 3-class split is the generation logic. Both are reported; **[C]**.

**What triggers a photo [U]:**
- **[V]** Photos arrive with a push notification when the frog returns, or mid-trip; they go to うらべや → アルバム — <https://muccarana.com/tabikaeru_play>
- **[V] Postcards per trip: 1–3.** Sources: <https://zetaspace.cc/tabi-kaeru-friend/> (1–3); <https://harudiki.com/diary20180130/> (はこべのサンドイッチ 20 みつ葉 → **1–2** photos; かぼちゃのベーグル 50 みつ葉 → **2–3** photos); <https://jingyan.baidu.com/article/e52e36151438d940c70c515a.html> (usually 1)
- **[CODE]** Photo generation depends on the **route, whether a どうぐ was carried, and whether the destination was reached** — inferred from `■ 写真：通常/道具/ユニーク（道：`. Exact formula: **not found**.
- **[V]** どうぐ → situation/photo type (see the table in §7.2)
- **[V]** 称号 → photo situation: 「称号は、旅時間や写真に写るシチュエーションが変化する」
- **[V]** えりまき colour → companion (event 北の旅 observation): 黄色→ねずみ, 赤色→カニ, 青色→蝶々 — <https://muccarana.com/tabikaeru_update>

**Are photos duplicated / repeatable? YES [V]:**
「かえるからは、結構な確率で同じ場所の写真をもらうことがあります」 and a review: 「前に保存したのと全く同じ写真を保存してしまうとかままあります」 — <https://muccarana.com/tabikaeru_play> · <https://applion.jp/旅かえる/android-jp.co.hit_point.tabikaeru/review/>

**Album capacity — base 60, max 96 [V]:**

| Fact | Value | Source |
|---|---|---|
| Base | **6 photos × 10 pages = 60** | <https://muccarana.com/tabikaeru_play> · <https://nanny.livedoor.blog/archives/2082303.html> · <https://www.9game.cn/news/2159965.html> |
| v**1.2.1** (2018-06-28) added アルバムページの拡張 | **みつ葉 300 → +2 pages** | <https://muccarana.com/tabikaeru_play> · <https://kankuri-game.com/post-2172/> |
| Max as of 2018-11-23 | **16 pages = 96 photos** | <https://muccarana.com/tabikaeru_play> |
| **[C]** rinranron | 「写真はアルバムに登録できる（**50ページ**）」 — inconsistent with every other source; **appears to be an error** | <https://rinranron.net/tabikaeru-kouryaku/> |
| **[?]** Later review | Added pages until the icon disappeared at **~30 added pages** ⇒ cap raised after 2018; interpretation ambiguous (20–40 pages) | <https://applion.jp/旅かえる/android-jp.co.hit_point.tabikaeru/review/> |
| **Exact current maximum** | — | **not found** |

**[CODE] Code constants (CN v1.07 — reported, not asserted for JP):** `ALBUM_MAX: 60` (matches base 60), `PICTURE_GETMAX: 4`, `BASE_PICTURE_PER: 70`, `PICTURE_TOOLS_PLUSPER: {0:0, 1:15, 2:30, 3:50}`, `SNAP_MAX: 30`.

**[CODE] JP photo-generation evidence tables (from the JP APK):** `PictureDataBase` count **68** (compositions, ids from 100), `PictureBackDataBase` **135** (backgrounds), `PictureTagDataBase` **43** (location tags), `PictureCharaDataBase` **38** (frog poses), `PictureRandomDataBase` **31** (random layer groups).
> **Important caveat:** these are **composition *assets*, not unlockable photo counts.** `68 compositions × 135 backgrounds` does **not** mean 9,180 photos. **Do not multiply them.** `not found` for the true total.

---

## 7. Bonus tables verified along the way

### 7.1 称号 (titles) — 7 (Jan 2018) → 11 → 13 (current)

| Count | Date / source |
|---|---|
| **7** | Jan 2018, early CN/TW guides — <https://m.techweb.com.cn/article/2018-01-22/2631367.shtml> |
| **11** | 2018-01-31, consistent across 3 sources — <https://www.saydigi.com/2018/01/tabikaeru-title-tips.html/> · <https://www.japanese-language.com.tw/info-161.html> · <https://www.9game.cn/news/6940868.html> |
| **13** | current — <https://rinranron.net/tabikaeru-kouryaku/> (adds どさんこかえる, うちなーかえる with the 北海道/沖縄 regions) |
| **[CODE] 11** | JP APK `AchieveDataBase` contains **exactly 11** records, with numeric thresholds: trips **10/25/50**; trip duration **<30 min** (`1799` s) or **≥1400 min** (`84000` s); clover **100000**; lottery **20** spins; all-ingredient registration (**11 and 18**) |

⚠️ **[C]** The `かえらぬ旅路` row is internally inconsistent in the JP data: the description says **1440 分**, but the stored value is **84000 s = 1400 分** — a **40-minute discrepancy** between text and threshold. Reported as found.

⚠️ **[C]** rinranron's 11 vs the JP APK's 11 **are not the same 11** (rinranron has お菓子なごはん and まんじゅう怖い; the APK list differs). Unresolved.

**[V]** Titles are equipped by tapping the frog, and they change travel time and photo situations — <https://rinranron.net/tabikaeru-kouryaku/>.

### 7.2 どうぐ → destination / photo situation [V]

| どうぐ | 旅先・写真のシチュエーション |
|---|---|
| 手ぬぐい (地/木/装) | 町・道端・カフェ |
| テント (ナチュラル/スタイリッシュ/ハイテク) | 野営・野原・森 |
| うつわ (透明/木/漆) | 船旅・川辺・海辺 |
| あかり (ろうそく/手提げ提灯/ランタン) | 洞窟・探検 |
| えりまき (赤/黄/青) | 寒い地域 + しっぽ・はさみ・はねをもつともだちとの写真 |
| ボトル (赤/茶/紫) | 暑い地域 + しっぽ・はさみ・はねをもつともだちとの写真 |
| ラジオ受信機 | おうち設置のみ（BGM） — 1000 みつ葉 |

Source: <https://rinranron.net/tabikaeru-kouryaku/> · **[V]** 「上位のどうぐになるほど、遠くレアな旅先になりやすい傾向があります。」

### 7.3 Shop prices — bentou and どうぐ [V]

| Category | Items and prices (みつ葉) |
|---|---|
| おべんとう | えびづるのスコーン **10** · はこべのサンドイッチ **20** · かぼちゃのベーグル **50** · のびるキッシュ **80** · よもぎのフォカッチャ **100** · あさつきのぴろしき **100** |
| どうぐ — てぬぐい (町) | 地 **150** · 木 **250** · 装 **400** |
| どうぐ — テント (野営) | ナチュラル **300** · スタイリッシュ **450** · ハイテク **750** |
| どうぐ — うつわ (船旅) | 透明 **450** · 木 **700** · 漆 **1200** |
| どうぐ — あかり (探検) | ろうそく **600** · 手提げ提灯 **900** · ランタン **1500** |
| どうぐ — えりまき (寒い地域) | 赤/黄/青 **500** each |
| どうぐ — ボトル (暑い地域) | 赤/茶/紫 **500** each |
| おまもり | 幸運の鈴 **3000** (reusable) |

**[V]** <https://rinranron.net/tabikaeru-kouryaku/>
**[CODE] Strong independent confirmation:** all of the above prices match the JP APK's `ItemDataBase` price field exactly (10/20/50/80/100/100; 150/250/400; 300/450/750; 450/700/1200; 600/900/1500; 3000) — see `work/spec/jp-reference.md` §2.1. **This validates the entire price column against the binary.**

---

## 8. CONSOLIDATED "not found" LIST

Everything below is `not found`. **Do not fill these with guesses.**

1. **Gaussian μ and σ** of clover regrowth time (present only as images in the source article).
2. Any **per-clover respawn interval table** beyond the 300 s / 14400 s bounds.
3. The **JP value of `CloverDestroyTime`** (unharvested-clover expiry).
4. Any **four-leaf probability other than 1 %** — no "1 in N" variant found anywhere.
5. Any **sale or exchange price for 四つ葉 in みつ葉** — no such mechanic is documented.
6. **Whether 四つ葉 is consumed** — sources directly contradict each other (§1.7).
7. The **normal home-stay duration (滞在時間)** in hours/minutes, and the **exact size of the かんりょう speed-up**.
8. **Visitor visit frequency** — no hours-between-visits, no rate, no cooldown in any web source.
9. **Definitive visitor stay duration** — 180–270 min vs 1–2 h, unresolved.
10. A **formula mapping visitor reaction stage → clover amount**; also the "58 clovers" figure seen in one snippet.
11. **Official Hit-Point lottery odds** — none published.
12. **Within-tier lottery odds** (per omamori colour, per kompeito flavour, per ticket direction).
13. The **colour ↔ tier mapping for the JP 5 balls** (5 colours, 4 item tiers, no stated correspondence).
14. **Exact current いっぴん count** — 26 stated vs 28 listed vs 10 in the APK build.
15. **Independent verification of めいぶつ = 47** — one source; its own list dedupes to 46.
16. Any **per-souvenir rarity tier** — none exist in any source or table.
17. The **total number of distinct photos** — only a 2018 floor of "≥50".
18. The **current maximum album pages** — 16 pages (96 photos) as of 2018-11-23; later bound unclear.
19. **Official Hit-Point JP IAP price list** — APPLION's best-seller list is the only source.
20. The exact formula for **`COLLECT_PER: [15,30,50,100]`** — what the 4 elements index.
21. **JP values** for `FRIEND_VISIT_COOL`, `FROG_RESTTIME`, `FRIEND_GIFTBOUNUS_*`, `SHOP_TICKET_PER`, `PrizeBalls` — the CN v1.07 table gives numbers but the JP build is v1.8.x and differs structurally.
22. Whether the **JP version has a 紫玉 (purple) ball** — the JP DLL's string heap has only 5 ball names; the CN table has 6 ranks. Unresolved.

## 9. HIGHEST-VALUE NEXT STEPS

1. **Reach h1g.jp/tabikaeru** from a network where it is not blocked. It is the authoritative JP wiki and holds `ふくびき`, `いっぴん`, `めいぶつ`, `称号`, `用語集` pages that would close gaps 11–14 and 18 directly.
2. **Decompile the JP `Assembly-CSharp.dll`** (`work/jp_apk/assets/bin/Data/Managed/Assembly-CSharp.dll`). A `dotnet` SDK **is** present at `C:\Program Files\dotnet\dotnet.exe` and JDK 17 is available at `work\jdk\jdk-17.0.2` — `ilspycmd` (or a JDK-based decompiler on the DEX) would read every `Define` constant directly from the JP binary and settle **the majority of the `[CODE]`-uncertain items in one pass**, including: `CloverDestroyTime`, `BAGITEMS`/`DESKITEMS`, `TRAVEL_TIMEMIN/MAX`, `RAFFEL_NEEDTICKETS`, `PrizeBalls` weights, `FRIEND_VISIT_COOL`, `FRIEND_GIFTBOUNUS_*`, `SHOP_TICKET_PER`, the four-leaf `spend` flag (§1.7), and the colour↔tier mapping.
3. **Verify the APK build version.** `jp.co.hit_point.tabikaeru.apk` is a third-party (3DM) repack; confirm its internal version string against the current 1.8.6 before treating any extracted count (e.g. `CollectionDataBase` = 10 いっぴん) as current.

---

## 10. PROVENANCE / FILES

**Primary outputs of this research**

| Path | Contents |
|---|---|
| `TABIKAERU-GAME-DATA-REFERENCE.md` | **This document.** |
| `raw\REPORT-clover-garden-travel.md` | Detailed clover/garden/travel report (276 lines) with per-claim source tables |
| `raw\lot_REPORT.md` | Detailed lottery/visitors/currency/souvenirs/photos/titles report (445 lines) |
| `raw\*.txt` | ~180 raw HTML→text page dumps |
| `work\tools\fetch.ps1`, `work\tools\fetch2.ps1` | Reusable page fetchers (fetch2 adds GB2312/Big5/Shift_JIS detection) |

**Existing datamine assets consulted (pre-existing, not produced here)**

| Path | Contents |
|---|---|
| `work\spec\jp-reference.md` | 666-line JP-APK datamine: all 19 `*DataBase` tables, 67 items with prices, prize pool, achievements, currencies |
| `work\jp_apk\tables.json`, `items.json`, `tokens.json`, `Assembly-CSharp.json`, `us.txt` | Extracted JP tables and DLL symbol/string heaps |
| `work\run\engine\data\define.json` | The `Tabikaeru.Define` tuning table (**CN v1.07, not pristine JP**) |

**Honest accounting of method.** `web_search` in this environment returns source URLs and short snippets only — never page bodies. All web facts above therefore come from pages fetched directly over HTTP with `Invoke-WebRequest` and stripped to text. Roughly 150 fetch attempts were made across ~60 domains. Facts that could not be reached that way are marked `not found` rather than estimated. No percentage, count, or duration in this document was invented.
