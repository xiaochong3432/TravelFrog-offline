(async function () {
  /* 复核：三个不同的 id 分别回什么（101 已领 / 201 未达成 / 99999 非法），
     并打印引擎侧的相关状态，确认"回包到底对应哪一次请求"。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w = 0; w < 60 && !window.__engine; w++) await sleep(500);
  var eng = window.__engine;
  if (!eng) return { error: 'no engine' };
  var sm = core.SocketManage.getInstance();
  var out = {};
  eng.state.travel.tripCount = 5;
  eng.state.taskTiers = {};
  out.pictures = (eng.state.pictures || []).length;
  out.type2Rows = [];
  var T = null;
  try { T = Tabikaeru.DataManager.instance().TaskDB.get('list_map'); } catch (e) { out.taskDbErr = String(e); }
  if (T) { for (var k in T) if (Number(T[k].type) === 2) out.type2Rows.push({ id: k, count: T[k].count }); }

  async function claim(id) {
    var got = null;
    sm.send('task_get_list_reward', new core.Action2(function (r) { got = r; }), id);
    await sleep(700);
    return got;
  }
  out.claim101 = await claim(101);
  out.tiersAfter = JSON.parse(JSON.stringify(eng.state.taskTiers || {}));
  out.claim201 = await claim(201);
  out.tiersAfter2 = JSON.parse(JSON.stringify(eng.state.taskTiers || {}));
  out.claim99999 = await claim(99999);
  out.claim101again = await claim(101);
  out.picturesAfter = (eng.state.pictures || []).length;
  return out;
})()
