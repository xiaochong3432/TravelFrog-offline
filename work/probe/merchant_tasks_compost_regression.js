/* Run only in an isolated cdp_drive.js profile: replaces test progress and stock. */
(async function () {
    const check = (ok,message) => { if(!ok) throw new Error(message); };
    const wait = ms => new Promise(resolve=>setTimeout(resolve,ms));
    const clone = value => JSON.parse(JSON.stringify(value));
    document.getElementById('__notice_ok')?.click();
    const engine = window.__engine;
    const models = core.ModelManage.getInstance();
    const tasks = models.getModel(GuideTaskModel);
    engine.state.travel.tripCount = 5;
    engine.state.travel.nextDepartAt = Math.floor(Date.now()/1000)+3600;
    engine.state.taskTiers = {};
    tasks.dataReward = {};
    tasks.task_load(clone(engine.dispatch('task_load',{}).reply));
    tasks.task_load_list(clone(engine.dispatch('task_load_list',{}).reply));
    let rewards = 0;
    tasks.req_list_reward(1,0,new core.Action(()=>rewards++));
    check(rewards===1 && tasks.getNextListReward(1)===1, 'first route reward failed');
    const reloaded = FrogEngine.createEngine({savePath:'save.json',verbose:false});
    tasks.dataReward = {}; // what a fresh page sees after restart
    tasks.task_load_list(clone(reloaded.dispatch('task_load_list',{}).reply));
    check(tasks.getNextListReward(1)===1, 'route reward reappeared after reload');
    tasks.req_list_reward(1,0,new core.Action(()=>rewards++));
    check(rewards===1, 'duplicate request displayed a reward again');

    const user = models.getModel(UserModel);
    for (const [key,value] of Object.entries({guideStep:GuideStep.Complete,
        guideFurniture:6,guideFurnitureNotice:true,guideAnnualReview:true,guideDrawing:3})) {
        user.setClientSettings(key,value);
    }
    const pages = core.PageManage.getInstance();
    const fm = models.getModel(FurnitureModel);
    pages.addViewControl(MainOutController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(1200);
    const scene = pages.getControl(MainOutController,core.ViewLayerType.SceneLayer).view;
    fm.furniture_load_compost(clone(engine.dispatch('furniture_load_compost',{}).reply));
    await wait(200);
    check(fm.compostData.compost_list[fm.compostData.show_index-1]===21000,'starter compost missing');
    check(!!scene.compost.source && !!scene.compost.texture,'compost has no courtyard image');
    scene.on_compost_tap();
    await wait(500);
    const compost = pages.getControl(CompostViewControl,core.ViewLayerType.WindowLayer);
    check(compost?.view.itemGrids.length===6,'compost window did not open');
    pages.removeControl(CompostViewControl,core.ViewLayerType.WindowLayer);

    // Sell the last repeatable item through the real merchant request/callback.
    const db = Tabikaeru.DataManager.instance().FurnitureShopDB;
    engine.state.furniture.shopBought = {};
    engine.state.furniture.shopDailyBought = {};
    for (const row of db.list()) {
        engine.state.furniture.shopBought[row.id] = Number(row.limit)||1;
        engine.state.furniture.shopDailyBought[row.id] = Number(row.shop_limit)||1;
    }
    engine.state.furniture.shopDailyBought[2001] = 0;
    engine.state.clover = 1000000;
    fm.furniture_load_furniture(clone(engine.dispatch('furniture_load_furniture',{}).reply));
    pages.addViewControl(FurnitureShopController,core.ViewLayerType.WindowLayer);
    await wait(500);
    const shop = pages.getControl(FurnitureShopController,core.ViewLayerType.WindowLayer);
    check(shop?.view.shopItems.length===1,'expected the last merchant item');
    let purchases = 0;
    fm.requestBuy(2001,new core.Action1(()=>purchases++));
    await wait(500);
    check(purchases===1,'last merchant purchase failed');
    check(!pages.getControl(FurnitureShopController,core.ViewLayerType.WindowLayer),'empty green shop stayed open');
    check(!fm.isOpenShop() && !scene.shop_mc.visible,'sold-out merchant did not leave');
    engine.state.furniture.shopDay -= 86400;
    fm.furniture_load_furniture(clone(engine.dispatch('furniture_load_furniture',{}).reply));
    await wait(200);
    check(fm.isOpenShop() && scene.shop_mc.visible,'restocked merchant did not return');
    check(fm.getShopData().shop_list.some(x=>x.shop_id===2001),'repeatable item did not restock');
    check(!fm.getShopData().shop_list.some(x=>x.shop_id===1),'one-time item restocked');
    return {passed:true,routeRewardCallbacks:rewards,compostVisible:true,compostSlots:6,
        soldOutClosed:true,merchantLeft:true,restocked:true};
})()
