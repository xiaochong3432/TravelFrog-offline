/* Run on an isolated profile loaded with a copy of an affected save. */
(async function () {
    document.getElementById('__notice_ok')?.click();
    const wait=ms=>new Promise(r=>setTimeout(r,ms));
    const engine=window.__engine,travel=core.ModelManage.getInstance().getModel(TravelModel);
    const pending=engine.state.albumPending.map(p=>({id:p.id,pic_id:p.pic_id}));
    const client=travel.newPictureInfoList.map(p=>({id:p.id,pic_id:p.pic_id}));
    function find(node,type){
        if(node instanceof type)return node;
        for(const child of node.$children||[]){const result=find(child,type);if(result)return result;}
    }
    let card;
    for(let i=0;i<15;i++){
        card=find(egret.MainContext.instance.stage,Result.ReceivePostcard);
        if(card)break;
        const notice=find(egret.MainContext.instance.stage,Result.MainOutNotification);
        if(notice)notice.cover.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);
        await wait(350);
    }
    if(!card)return {passed:false,pending,client,reason:'No automatic receive-postcard UI'};
    await wait(1200);
    const id=card.pic.id,textureReady=!!card.picture.texture;
    card.saveBtn.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);await wait(250);
    if(!engine.state.pictures.some(p=>p.id===id)){
        card.saveBtn.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);await wait(400);
    }
    const filed=engine.state.pictures.some(p=>p.id===id);
    const removed=!engine.state.albumPending.some(p=>p.id===id);
    const restored=FrogEngine.createEngine({savePath:'save.json',verbose:false});
    const persisted=restored.state.pictures.some(p=>p.id===id);
    return {passed:pending.length>0&&pending.every(p=>client.some(q=>q.id===p.id))&&
        textureReady&&filed&&removed&&persisted,pending,client,photoId:id,textureReady,filed,removed,persisted};
})()
