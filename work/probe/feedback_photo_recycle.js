/* Dedicated profile only: decline via the postcard dialog, then recover in UI. */
(async function () {
    document.getElementById('__notice_ok')?.click();
    const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms)),tap=node=>node.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);
    const engine=window.__engine,models=core.ModelManage.getInstance(),pages=core.PageManage.getInstance();
    const travel=models.getModel(TravelModel),results=[];
    const check=(id,passed,detail)=>results.push({id,passed:!!passed,detail});
    const find=(node,type)=>{
        if(node instanceof type)return node;
        for(const child of node.$children||[]){const found=find(child,type);if(found)return found;}
    };
    const id=120001;
    engine.state.pictures=[];engine.state.albumDeleted=[];engine.state.albumPendingVisit=[];
    engine.state.albumPending=[{id,pic_id:100,read:0,new:1}];engine.state.pictureSeq=id;engine.save();
    const pending=engine.dispatch('album_load_new',{}).reply;
    travel.album_load_new(pending);
    const card=new Result.ReceivePostcard(pending.pictures[0]);
    core.DisplayManage.getInstance().getPopupLayer().addChild(card);
    await wait(1400);
    check('received-photo-renders',!!card.picture.texture);
    tap(card.close);await wait(200);
    let confirm=find(card,ModalConfirm);
    if(!confirm){tap(card.close);await wait(550);tap(card.close);await wait(250);confirm=find(card,ModalConfirm);}
    if(!confirm)throw new Error('discard confirmation missing');
    tap(confirm.confirmBtn);await wait(400);
    check('discard-dialog-closes',!card.parent);
    check('discard-goes-to-recycle',engine.state.albumPending.length===0&&engine.state.albumDeleted.some(p=>p.id===id));
    const restored=FrogEngine.createEngine({savePath:'save.json',verbose:false});
    check('discard-survives-reload',restored.state.albumDeleted.some(p=>p.id===id)&&restored.state.albumPending.length===0);
    pages.addViewControl(AlbumController,core.ViewLayerType.WindowLayer,core.RemoveViewType.HideBefore);
    await wait(700);
    const album=pages.getControl(AlbumController,core.ViewLayerType.WindowLayer).view;
    album.on_RecoverBtn();await wait(1200);
    const bin=album.recoverView,row=bin.CacheList.find(row=>row.visible&&row.pic?.id===id);
    check('recycle-ui-has-photo',!!row&&travel.getDeletePictureInfoList().some(p=>p.id===id));
    if(!row)throw new Error('discarded photo missing from recycle UI');
    tap(row);tap(bin.btnPut);await wait(250);
    confirm=find(bin,ModalConfirm);if(!confirm)throw new Error('recovery confirmation missing');
    tap(confirm.confirmBtn);await wait(600);
    check('recover-back-to-album',engine.state.pictures.some(p=>p.id===id)&&travel.getPictureInfoList().some(p=>p.id===id));
    check('recover-removes-from-bin',!engine.state.albumDeleted.some(p=>p.id===id)&&!travel.getDeletePictureInfoList().some(p=>p.id===id));
    const reloaded=FrogEngine.createEngine({savePath:'save.json',verbose:false});
    check('recovery-persists',reloaded.state.pictures.some(p=>p.id===id)&&reloaded.state.albumDeleted.length===0);
    return {passed:results.every(r=>r.passed),results};
})()
