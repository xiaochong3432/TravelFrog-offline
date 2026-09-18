/* Dedicated profile only: real client inventory and handcraft protocol updates. */
(async function () {
    document.getElementById('__notice_ok')?.click();
    const engine=window.__engine,models=core.ModelManage.getInstance();
    const items=models.getModel(ItemModel),craft=models.getModel(HandCraftModel);
    const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
    const send=cmd=>new Promise(resolve=>core.SocketManage.getInstance().send(cmd,new core.Action2(resolve)));
    const results=[],check=(id,passed,detail)=>results.push({id,passed:!!passed,detail});
    engine.state.frog.status=0;engine.state.travel.nextDepartAt=Math.floor(Date.now()/1000)+10000;
    engine.state.craft={wishes:[],stamps:[],pending:[],seq:0};
    engine.state.items.house=[{item_id:8000,count:2},{item_id:8001,count:1}];
    items.item_load_items(engine.dispatch('item_load_items',{}).reply);
    let reply=await send('pray_load_grays');
    check('no-tool-no-production',reply.wishs.length===0&&reply.stamps.length===0&&!engine.state.craft.wood
        &&items.getHouseItemCount(8000)===2&&items.getHouseItemCount(8001)===1);
    engine.state.items.house.push({item_id:7000,count:1});
    items.item_load_items(engine.dispatch('item_load_items',{}).reply);
    reply=await send('pray_load_grays');
    const job=engine.state.craft.wood;
    check('start-charges-client-inventory',items.getHouseItemCount(8000)===0&&items.getHouseItemCount(8001)===0,
        {material:items.getHouseItemCount(8000),wood:items.getHouseItemCount(8001)});
    check('one-job-per-payment',reply.wishs.length===1&&reply.stamps.length===1&&!!job);
    await send('pray_load_grays');
    check('refresh-no-double-charge',engine.state.craft.seq===2&&engine.state.craft.wood.itemId===job.itemId);
    engine.state.craft.wood.finishAt=1;
    engine.state.craft.wishes[0].state=3;engine.state.craft.wishes[0].make_time=1;
    engine.state.craft.stamps[0].state=2;engine.state.craft.stamps[0].time=1;
    // Exercise the background timer, not a second explicit load request.
    await wait(5500);
    check('timer-delivers-wood-to-client',items.getHouseItemCount(job.itemId)===1,job.itemId);
    reply=await send('pray_load_grays');
    check('finished-records',reply.wish_new?.state===4&&reply.stamp_new?.state===3);
    check('no-free-follow-up',engine.state.craft.seq===2&&!engine.state.craft.wood);
    const restored=FrogEngine.createEngine({savePath:'save.json',verbose:false});
    restored.dispatch('pray_load_grays',{});
    check('reload-keeps-single-output',(restored.state.items.house.find(i=>i.item_id===job.itemId)||{}).count===1
        &&restored.state.craft.seq===2);
    return {passed:results.every(r=>r.passed),results};
})()
