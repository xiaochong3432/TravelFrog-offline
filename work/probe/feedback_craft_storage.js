/* Dedicated test profile: tool-gated entry, existing collection, real return timer. */
(async function () {
    document.getElementById('__notice_ok')?.click();
    const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms)),tap=node=>node.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);
    const engine=window.__engine,models=core.ModelManage.getInstance(),pages=core.PageManage.getInstance();
    const craft=models.getModel(HandCraftModel),role=models.getModel(RoleModel),items=models.getModel(ItemModel);
    const results=[],check=(id,passed,detail)=>results.push({id,passed:!!passed,detail});
    engine.state.items.house=[];
    engine.state.craft={seq:2,pending:[],wishes:[{id:1,state:4,body:102,paper:1001,content:1,make_time:1,stamp_time:1,stamp:1,stamp_state:3,u_id:1}],
        stamps:[{id:109,state:3,time:1,u_id:2}]};
    engine.state.frog.status=1;engine.state.travel.returnAt=Math.floor(Date.now()/1000)+10000;
    engine.state.travel.plan={stray:true};
    items.item_load_items(engine.dispatch('item_load_items',{}).reply);
    craft.pray_load_grays(engine.dispatch('pray_load_grays',{}).reply);
    role.client_load_role(engine.dispatch('client_load_role',{}).reply);
    core.String.setCookie('show_stamp_new','2');core.String.setCookie('show_pray_new','1');
    pages.addViewControl(LumberroomViewControl,core.ViewLayerType.WindowLayer,core.RemoveViewType.HideBefore);
    await wait(600);
    const warehouse=pages.getControl(LumberroomViewControl,core.ViewLayerType.WindowLayer).view;
    check('entry-hidden-without-tool',items.getHaveItem(7000)===0&&!warehouse.handCraftBtn.visible&&!warehouse.handCraftBtn.includeInLayout);
    engine.state.items.house.push({item_id:7000,count:1});
    items.item_load_items(engine.dispatch('item_load_items',{}).reply);
    warehouse.update();await wait(200);
    check('entry-visible-with-tool',warehouse.handCraftBtn.visible&&warehouse.handCraftBtn.includeInLayout);
    if(warehouse.handCraftBtn.visible){
        tap(warehouse.handCraftBtn);await wait(500);
        const collection=pages.getControl(HandCraftViewController,core.ViewLayerType.WindowLayer)?.view;
        check('collection-opens',!!collection?.parent&&craft.getPrayCraftList().length===1&&craft.getStampCraftList().length===1);
        collection?.close();
    } else warehouse.close();
    pages.addViewControl(MainInController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(600);
    const room=pages.getControl(MainInController,core.ViewLayerType.SceneLayer).view;
    room.checkHandCraft();
    check('completed-crafts-on-desk-before-return',room.i_stampcraf.visible&&room.i_praycraft.visible);
    engine.state.travel.returnAt=1;engine.save();
    await wait(5500);
    check('return-clears-desk',engine.state.frog.status===0&&!room.i_stampcraf.visible&&!room.i_praycraft.visible&&!room.i_praying.visible);
    check('collection-preserved',craft.getPrayCraftList().length===1&&craft.getStampCraftList().length===1);
    const restored=FrogEngine.createEngine({savePath:'save.json',verbose:false});
    const saved=restored.dispatch('pray_load_grays',{}).reply;
    check('stored-after-reload',!saved.wish_new&&!saved.stamp_new&&saved.wishs.length===1&&saved.stamps.length===1);
    engine.state.frog.status=1;engine.state.travel.returnAt=Math.floor(Date.now()/1000)+10000;
    role.client_load_role(engine.dispatch('client_load_role',{}).reply);
    room.checkHandCraft();
    check('next-departure-does-not-redisplay',!room.i_stampcraf.visible&&!room.i_praycraft.visible);
    return {passed:results.every(r=>r.passed),results};
})()
