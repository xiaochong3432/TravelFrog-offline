/* Dedicated profile only: feeding -> departure -> courtyard icon -> accept. */
(async function () {
    document.getElementById('__notice_ok')?.click();
    const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
    const tap=node=>node.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);
    const engine=window.__engine,models=core.ModelManage.getInstance(),pages=core.PageManage.getInstance();
    const drawing=models.getModel(DrawingModel),travel=models.getModel(TravelModel),items=models.getModel(ItemModel);
    const results=[],check=(id,passed,detail)=>results.push({id,passed:!!passed,detail});
    models.getModel(UserModel).setClientSettings('guideDrawing',3);
    pages.addViewControl(MainOutController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(800);
    const scene=pages.getControl(MainOutController,core.ViewLayerType.SceneLayer).view;
    for(const guest of [0,1,2]) {
        const now=Math.floor(Date.now()/1000),itemId=guest===0?3001:3000;
        engine.state.items.house=[{item_id:7001,count:1},{item_id:itemId,count:2}];
        engine.state.drawing.state=0;engine.state.drawing.guest=-1;
        drawing.guest_load_drawing(engine.dispatch('guest_load_drawing',{}).reply);
        engine.state.guest={id:guest,served:false,confirmed:true,pos:0,startAt:now-300,expire_time:now+600};
        items.item_load_items(engine.dispatch('item_load_items',{}).reply);
        travel.guest_load(engine.dispatch('guest_load',{}).reply);
        travel.sendGuestServed(itemId);await wait(250);
        check('feed-before-departure-'+guest,engine.state.guest.servedFeeling>=60&&drawing.data.state===0&&!scene.inviteBtn.visible);
        engine.state.guest.expire_time=1;
        const original=Math.random;
        try {
            Math.random=()=>0.74;
            core.SocketManage.getInstance().send('guest_finish');
        } finally {Math.random=original;}
        await wait(450);
        check('same-neighbour-door-invite-'+guest,drawing.data.state===1&&drawing.data.guest===guest&&scene.inviteBtn.visible,
            {state:drawing.data.state,guest:drawing.data.guest,icon:scene.inviteBtn.icon});
        check('mail-also-delivered-'+guest,engine.state.mails.some(m=>m.senderCharaId===guest&&m.title==='小伙伴的回礼'));
        tap(scene.inviteBtn);await wait(300);
        const view=pages.getControl(InviteViewControl,core.ViewLayerType.WindowLayer)?.view;
        check('invitation-card-'+guest,view?.imgFace.texture&&view.imgFace.source===
            ['neighbor_invite_wugui_png','neighbor_invite_maotouying_png','neighbor_invite_songshu_png'][guest]);
        if(!view)throw new Error('invitation view did not open');
        tap(view.btnConfirm);await wait(250);
        check('accepted-'+guest,engine.state.drawing.state===2&&drawing.data.state===2&&!scene.inviteBtn.visible);
        // Remove the informational modal so the next independent fixture can open.
        const layer=core.DisplayManage.getInstance().getPopupLayer();
        for(const node of (layer.$children||[]).slice())if(node instanceof ModalAlert)layer.removeChild(node);
    }
    return {passed:results.every(r=>r.passed),results};
})()
