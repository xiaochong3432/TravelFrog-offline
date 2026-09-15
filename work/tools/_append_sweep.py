"""Append the persistence-sweep section to the README."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, '..', 'run', 'README.md')
s = open(P, encoding='utf-8').read()

TEXT = '''

================================================================================
持久化总 sweep（33 项）+ 抓出"扭蛋任务板永远是空的"
================================================================================

objective 的第三条腿是**持久化**。之前我都是**分子系统**验的，这轮做了一次
**统一 sweep**：把每个子系统的状态都种下去 → save() → **真实 reload** → 逐项读回。

```
{"checked":33,"failed":[],
 "detail":{"clover":true,"ticket":true,"cloverSpanRerolled":true,
   "albumFiled":true,"albumPending":true,"albumRecycleBin":true,
   "giftPictures":true,"giftSpecialty":true,
   "benchSlot3":true,"decoPutId":true,
   "provinces":true,"visitorGift":true,"visitorCarpet":true,
   "drawingState":true,"drawingColls":true,"guestServed":true,
   "wishCoin":true,"capsuleCoin":true,"capsuleTasksDealt":true,
   "cookingMonth":true,"cookingPro":true,"cookingSelect":true,"cookingTask":true,
   "lotteryPhase":true,"lotteryAnswer":true,"lotteryFlags":true,
   "animGuide":true,"animPages":true,"animPutNum":true,
   "moments":true,"storyGift":true,"storyFeedback":true,"guideAwardGiven":true}}
```

**33/33 全过** —— 覆盖三叶草（含重掷的 rebirth_span）、相册三个桶、礼品盒、
家具长凳、庭院装饰、省份收集、串门访客、友情绘本、邻居 guest、许愿池、扭蛋、
料理、抽奖、动态照片、彩蛋、故事、新手引导。

## sweep 当场抓出一个真 bug：扭蛋的**任务板永远是空的**

第一遍跑，33 项里挂了 1 项：`capsuleTasksDealt: "no tasks"`。

查下去是真问题，而且很隐蔽：

```js
// 客户端只在 patch_num > 0 时才会发 capsule_patch：
if (0 == task_list.length && patch_num > 0) this.req_patch();
```

**而 patch_num 从来没有被赋值过** —— 引擎里没有任何地方设它。于是 patch_num 恒为 0，
客户端**永远不请求发牌**，**任务板永远是空的**，`capsule_patch` 这条命令
**根本不可达**。扭蛋活动的"任务"那一半等于**死代码**。

**它没有"卡住"的形态，所以之前所有测试都放过了它**：界面能开、奖励能抽，
只是任务栏空空如也 —— **看起来像"这活动本来就没任务"**。

修法：`refreshCapsule()` 首次启动时设 `patchNum = task_list 的行数`（8）。
`capsuleData` **没有**"发几张牌"这个字段，所以这个数字**标注为我的选择**。

> 修完我还差点写了一个**自相矛盾的断言**：我断言"patch_num > 0 且 task_list > 0"，
> 但 `patch_num` 是**剩余待发数** —— 发完之后它本来就该是 0。
> 断言改成 **已发 + 待发 = 整张表**，这才是真正的不变量。

## 实测

**引擎单测 247 全过**（新增 1 条扭蛋任务板断言）；持久化 sweep **33/33**。
'''

s = s.rstrip() + TEXT
open(P, 'w', encoding='utf-8', newline='').write(s)
print('appended; file now %d chars' % len(s))
