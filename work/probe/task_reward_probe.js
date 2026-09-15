(async function () {
  /* A 的真页面验收：走客户端自己的 socket 领"累计计划奖励"（就是那个「伴蛙前行」面板里
     点不动的按钮），并读客户端 TaskModel 的状态确认它真的被更新了。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w = 0; w < 60 && !window.__engine; w++) await sleep(500);
  var eng = window.__engine;
  var out = {};
  if (!eng) return { error: 'no engine' };
  var sm = core.SocketManage.getInstance();
  var M = null;
  try { M = core.ModelManage.getInstance().getModel(TaskModel); } catch (e) { out.modelErr = String(e); }

  /* 让 是日清单（type1, target 3）达成：三条 type1 清单行都由"出行次数"驱动 */
  eng.state.travel.tripCount = 5;
  eng.state.taskTiers = {};

  var tl = null, tll = null;
  sm.send('task_load', new core.Action2(function (r) { tl = r; }));
  sm.send('task_load_list', new core.Action2(function (r) { tll = r; }));
  await sleep(400);
  out.taskLoad = { tasks: (tl && tl.tasks || []).length, hasPro: !!(tl && tl.tasks && typeof tl.tasks[0].pro === 'number'),
    list: (tl && tl.list || []).length };
  out.listRows = (tll && tll.reward || []).filter(function (r) { return r.id === 101 || r.id === 201; });
  out.clientDataSample = (M && M.data || []).slice(0, 2);
  out.clientDataList102 = M && M.dataList ? M.dataList[102] : 'n/a';

  /* 领 type1 的第 1 档 */
  var reply = null;
  sm.send('task_get_list_reward', new core.Action2(function (r) { reply = r; }), 101);
  await sleep(600);
  out.claimReply = reply;
  out.clientDataRewardType1 = M && M.dataReward ? M.dataReward[1] : 'n/a';
  out.engineTaskTiers = JSON.parse(JSON.stringify(eng.state.taskTiers || {}));
  /* 第二档还没达成 -> 应被拒 */
  var r2 = null;
  sm.send('task_get_list_reward', new core.Action2(function (r) { r2 = r; }), 201);
  await sleep(500);
  out.secondClaim = r2;
  /* 客户端自己算的"可领档位"（getNextListReward 读的就是 dataReward[type]） */
  try { out.getNextListReward_type1 = M.getNextListReward(1); } catch (e) { out.nextErr = String(e); }
  return out;
})()
