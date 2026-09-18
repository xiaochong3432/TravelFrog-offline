/* Dedicated test profile only. Exercise the room's newly-finished craft icons,
 * not the collection-page path (which receives a different payload). */
(async function () {
    const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
    const tap=node=>node.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);
    const results=[];
    const check=(id,passed,detail)=>results.push({id,passed:!!passed,detail});
    document.getElementById('__notice_ok')?.click();
    const engine=window.__engine,models=core.ModelManage.getInstance(),pages=core.PageManage.getInstance();
    const craft=models.getModel(HandCraftModel),role=models.getModel(RoleModel);
    const now=Math.floor(Date.now()/1000);
    engine.state.frog.status=0;
    engine.state.frog.motion=0;
    engine.state.frog.motionNextAt=now+10000;
    engine.state.travel.nextDepartAt=now+10000;
    engine.state.items.house=engine.state.items.house.filter(row=>![7000,8000].includes(row.item_id));
    engine.state.items.house.push({item_id:7000,count:1},{item_id:8000,count:2});
    engine.state.craft={seq:9101,pending:[],
        wishes:[{id:1,state:3,body:'',paper:'',content:1,make_time:1,u_id:9001}],
        stamps:[{id:109,state:2,time:1,u_id:9101}]};
    role.client_load_role(JSON.parse(JSON.stringify(engine.dispatch('client_load_role',{}).reply)));
    const load=()=>new Promise(resolve=>core.SocketManage.getInstance().send('pray_load_grays',new core.Action2(resolve)));
    const reply=await load();
    // Do not wait for the unrelated generic craft-announcement animation.
    core.String.setCookie('show_stamp_new','9101');
    core.String.setCookie('show_pray_new','9001');
    await wait(1300);
    check('finished-wish-payload',reply.wish_new?.id===1 && reply.wish_new?.state===4,reply.wish_new);
    check('finished-stamp-payload',reply.stamp_new?.id===109 && reply.stamp_new?.state===3,reply.stamp_new);
    pages.addViewControl(MainInController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(1000);
    const room=pages.getControl(MainInController,core.ViewLayerType.SceneLayer).view;
    // The original room only displays the prayer item when the frog is away.
    engine.state.frog.status=1;
    engine.state.travel.returnAt=now+10000;
    role.client_load_role(JSON.parse(JSON.stringify(engine.dispatch('client_load_role',{}).reply)));
    room.checkHandCraft();
    await wait(500);
    const images=node=>{
        const found=[];
        (function walk(n){if(n instanceof eui.Image)found.push({source:n.source,texture:!!n.texture});
            for(const child of n.$children||[])walk(child);})(node);
        return found;
    };
    for(const [kind,button] of [['stamp',room.i_stampcraf],['wish',room.i_praycraft]]){
        const art=images(button);
        check(kind+'-room-icon',button.visible && !!button.icon && art.some(i=>i.source===button.icon && i.texture),
            {visible:button.visible,icon:button.icon,art});
    }
    tap(room.i_stampcraf);
    await wait(700);
    const stampView=pages.getControl(StampCraftDetailViewController,core.ViewLayerType.NoticeLayer)?.view;
    const stamp=stampView?.list.$children.find(child=>child.g_stamp)?.g_stamp;
    check('stamp-completion-detail',stamp?.i_layer0.texture && stamp?.i_layer1.texture,stamp&&images(stamp));
    stampView?.close();
    tap(room.i_praycraft);
    await wait(700);
    const wishView=pages.getControl(PrayCraftDetailViewController,core.ViewLayerType.NoticeLayer)?.view;
    const wish=wishView?.list.$children.find(child=>child.g_prayCraft);
    check('wish-completion-detail',wish?.g_prayCraft.i_layer1.texture && wish?.g_prayCraft.i_layer2.texture && wish?.i_stamp.texture,
        wish&&images(wish.g_prayCraft));
    check('wish-date',!!wish?.l_date.text && !/NaN/.test(wish.l_date.text),wish?.l_date.text);
    const restored=FrogEngine.createEngine({savePath:'save.json',verbose:false});
    const reloaded=restored.dispatch('pray_load_grays',{}).reply;
    check('reload-completion-records',reloaded.wish_new?.id===1 && reloaded.stamp_new?.id===109);
    return {passed:results.every(r=>r.passed),results};
})()
