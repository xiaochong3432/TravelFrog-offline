/* Dedicated test profile only. Drive real model requests and let the normal
 * five-second engine timer deliver completion to the open compost window. */
(async function () {
    const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
    const clone=x=>JSON.parse(JSON.stringify(x)), results=[];
    const check=(id,passed,detail)=>results.push({id,passed:!!passed,detail});
    document.getElementById('__notice_ok')?.click();
    const engine=window.__engine, models=core.ModelManage.getInstance(),pages=core.PageManage.getInstance();
    const fm=models.getModel(FurnitureModel),inventory=models.getModel(ItemModel);
    const ids=Tabikaeru.DataManager.instance().ItemDB.list().filter(i=>i.type===3).slice(0,3).map(i=>i.id);
    engine.state.furniture.compost={showIndex:1,replaceIndex:0,boxIndex:0,boxes:[0,0,0,0,0,0],list:[21000],job:null,fertility:0};
    engine.state.items.house=ids.map(item_id=>({item_id,count:3}));
    inventory.item_load_items(clone(engine.dispatch('item_load_items',{}).reply));
    fm.furniture_load_compost(clone(engine.dispatch('furniture_load_compost',{}).reply));
    pages.addViewControl(MainOutController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(1000);
    const scene=pages.getControl(MainOutController,core.ViewLayerType.SceneLayer).view;
    scene.on_compost_tap();await wait(400);
    const view=pages.getControl(CompostViewControl,core.ViewLayerType.WindowLayer).view;
    check('idle-six-editable',view.itemGrids.every(grid=>grid.touchEnabled));
    fm.setCompostItem(2,ids[0]);await wait(400);
    const c=engine.state.furniture.compost;
    check('occupied-slot-ferments',fm.compostData.box_index===2 && c.job?.index===2);
    check('active-slot-locked-with-image',!view.itemGrids[1].touchEnabled && !!view.itemGrids[1].image.texture);
    check('first-empty-slot-editable',view.itemGrids[0].touchEnabled);
    check('inventory-reserved-once',inventory.getHouseItemCount(ids[0])===2);
    fm.setCompostItem(5,ids[1]);await wait(250);
    fm.setCompostItem(5,ids[2]);await wait(250);
    check('queued-swap-atomic',fm.compostData.box_list[4]===ids[2] && view.itemGrids[4].touchEnabled &&
        inventory.getHouseItemCount(ids[1])===3 && inventory.getHouseItemCount(ids[2])===2);
    check('five-minute-cycle',c.job.finishAt-c.job.startedAt===300);
    check('status-small-text-hidden',!view.offlineFertilityLabel || !view.offlineFertilityLabel.visible);
    // Simulate elapsed time only in this fixture. The live timer must finish it.
    c.job.startedAt=Math.floor(Date.now()/1000)-301;c.job.finishAt=c.job.startedAt+300;
    engine.save();await wait(5600);
    check('completion-consumes-reserved-item',fm.compostData.box_list[1]===0 && view.itemGrids[1].touchEnabled);
    check('fertility-updated',c.fertility===1 && fm.compostData.fertility===1);
    check('next-slot-ferments',fm.compostData.box_index===5 && !view.itemGrids[4].touchEnabled && !!view.itemGrids[4].image.texture);
    check('no-second-inventory-charge',inventory.getHouseItemCount(ids[0])===2 && inventory.getHouseItemCount(ids[2])===2);
    const restored=FrogEngine.createEngine({savePath:'save.json',verbose:false});
    const payload=restored.dispatch('furniture_load_compost',{}).reply;
    check('job-and-fertility-persist',payload.fertility===1 && payload.box_index===5 && payload.finish_at===c.job.finishAt);
    check('plain-furniture-default',Tabikaeru.DataManager.instance().FurnitureDB.list().filter(row=>row.style===1)
        .every(row=>engine.state.furniture.owned.includes(row.id)));
    return {passed:results.every(r=>r.passed),results};
})()
