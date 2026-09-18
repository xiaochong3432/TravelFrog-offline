/* Dedicated profile only. Exercise notification, feeding, departure and mail. */
(async function () {
    document.getElementById('__notice_ok')?.click();
    const wait=ms=>new Promise(r=>setTimeout(r,ms)),clone=x=>JSON.parse(JSON.stringify(x));
    const engine=window.__engine,models=core.ModelManage.getInstance(),pages=core.PageManage.getInstance();
    const travel=models.getModel(TravelModel),items=models.getModel(ItemModel),user=models.getModel(UserModel);
    user.setClientSettings('hasFriendVisit',true);
    pages.addViewControl(MainOutController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(1000);
    const scene=pages.getControl(MainOutController,core.ViewLayerType.SceneLayer).view;
    function findNotice(node){
        if(node instanceof Result.MainOutNotification)return node;
        for(const child of node.$children||[]){const found=findNotice(child);if(found)return found;}
    }
    for(let i=0;i<8;i++){
        const notice=findNotice(egret.MainContext.instance.stage);if(!notice)break;
        notice.cover.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);await wait(200);
    }
    const results=[];
    for(let id=0;id<3;id++){
        const now=Math.floor(Date.now()/1000), expires=now+1200;
        engine.state.guest={id,confirmed:false,served:false,pos:0,startAt:now-300,expire_time:expires};
        engine.state.visitor=null;
        travel.guest_load(clone(engine.dispatch('guest_load',{}).reply));
        scene.reset();await wait(500);
        const notice=findNotice(egret.MainContext.instance.stage);
        if(!notice)throw new Error('guest arrival notification missing for '+id);
        notice.cover.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);await wait(300);
        const afterNotice=engine.state.guest?.id===id&&engine.state.guest.confirmed;
        const itemId=Tabikaeru.DataManager.instance().ItemDB.list().find(x=>x.type===3).id;
        engine.state.items.house=engine.state.items.house.filter(x=>x.item_id!==itemId);
        engine.state.items.house.push({item_id:itemId,count:2});
        items.item_load_items(clone(engine.dispatch('item_load_items',{}).reply));
        const before={clover:engine.state.clover,four:items.getHouseItemCount(1000),mails:engine.state.mails.length};
        travel.sendGuestServed(itemId);await wait(300);
        const stayed=engine.state.guest?.served&&engine.state.guest.expire_time===expires;
        const reserved=clone(engine.state.guest?.pendingGift);
        const noEarlyPayout=engine.state.clover===before.clover&&items.getHouseItemCount(1000)===before.four;
        engine.state.guest.expire_time=now-1;
        // The normal server timer broadcasts tick pushes; wait for that path.
        await wait(5500);
        const mail=engine.state.mails.find(m=>m.senderCharaId===id&&m.title==='小伙伴的回礼');
        const delivered=!!mail&&travel.getMailInfoList().some(m=>m.id===mail.id);
        scene.updateMail();
        const redDot=scene.mailNotification.visible;
        scene.openMail();await wait(300);
        const opened=!!scene.mailView?.parent;
        if(scene.mailView?.parent)scene.mailView.parent.removeChild(scene.mailView);
        if(mail)travel.openMailInfo(mail.id);await wait(300);
        const claimed=!!mail&&!engine.state.mails.some(m=>m.id===mail.id)&&
            engine.state.clover===before.clover+reserved.clover&&
            items.getHouseItemCount(1000)===before.four+(reserved.items[0]?.count||0);
        results.push({id,afterNotice,stayed,noEarlyPayout,delivered,redDot,opened,claimed,gift:reserved});
    }
    return {passed:results.every(r=>r.afterNotice&&r.stayed&&r.noEarlyPayout&&r.delivered&&r.redDot&&r.opened&&r.claimed),results};
})()
