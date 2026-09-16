/* Uses an isolated cdp_drive.js profile; replaces its test inventory. */
(async function () {
    const check = (ok, message) => { if (!ok) throw new Error(message); };
    const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
    document.getElementById('__notice_ok')?.click();
    const engine = window.__engine;
    const models = core.ModelManage.getInstance();
    const items = models.getModel(ItemModel);
    const user = models.getModel(UserModel);
    user.getClientSettings().guideStep = GuideStep.Complete;
    user.getClientSettings().hasOpenedDesk = true;
    engine.state.travel.nextDepartAt = Math.floor(Date.now()/1000) + 3600;
    engine.state.travel.plan = null;
    engine.state.frog.status = 0;
    engine.state.items.bag = [-1,-1,-1,-1];
    engine.state.items.desk = Array(8).fill(-1);
    engine.state.items.bagCompleted = 0;
    engine.state.items.house = [0,1,1000,1001,2000,2001].map(item_id=>({item_id,count:2}));
    const refresh = () => items.item_load_items(JSON.parse(JSON.stringify(engine.dispatch('item_load_items',{}).reply)));
    refresh();
    const stage = egret.MainContext.instance.stage;
    const view = new BagTable();
    view.width = stage.stageWidth;
    view.height = stage.stageHeight;
    stage.addChild(view);
    try {
        await wait(500);
        check(!!view.bag && !!view.playerBag, 'packing view missing');
        const select = async (storage, slot, id) => {
            const target = storage === 'bag' ? view.bag : view.table;
            target.tapItem(target.items[slot], slot);
            await wait(80);
            const rows = view.playerBag.list.dataProvider.source.flat();
            const row = rows.find(x=>x.id===id);
            check(row && row.tap, 'item must be selectable: ' + id);
            view.playerBag.list.dispatchEventWith('PlayerBagItemRenderTap', false, row);
            await wait(80);
            const packed = storage === 'bag' ? items.getBagDataList() : items.getDeskDataList();
            check(packed[slot]===id && engine.state.items[storage][slot]===id, 'client/server slot mismatch');
            check(items.getHouseItemCount(id)===(engine.state.items.house.find(x=>x.item_id===id)?.count || 0),
                'house count mismatch');
        };
        // Deliberately fill out of order, through the actual item selector event.
        for (const [slot,id] of [[2,2000],[0,0],[3,2001],[1,1000]]) await select('bag',slot,id);
        check(JSON.stringify(items.getBagDataList())==='[0,1000,2000,2001]', 'wrong bag order');
        for (const slot of [0,1]) {
            view.bag.selectionIndex = slot;
            const beforeImage = view.bag.items[slot].image.source;
            view.bag.select(2000);
            check(view.bag.items[slot].image.source===beforeImage, 'rejected tool changed picture');
        }
        check(JSON.stringify(items.getBagDataList())==='[0,1000,2000,2001]', 'tool entered food/amulet slot');
        await select('bag',0,1);
        check(items.getHouseItemCount(0)===2 && items.getHouseItemCount(1)===1, 'replacement failed to return food');
        await select('desk',4,2000);
        check(items.getHouseItemCount(2000)===0, 'bag plus desk must reserve both copies');
        check(items.setDeskData(0,2000)===false, 'desk accepted tool as food');
        items.setDeskData(4,-1);
        check(items.getHouseItemCount(2000)===1, 'takeout must return one');
        const packed = items.getBagDataList().slice();
        items.setBagLock(true);
        check(engine.state.frog.status===1, 'prepared bag must depart');
        check(items.getHouseItemCount(1000)===1, 'carried clover is reserved, spare remains');
        engine.state.travel.returnAt = 1;
        engine.tick();
        refresh();
        const returned = items.getBagDataList().slice();
        check(JSON.stringify(returned)==='[-1,-1,2000,2001]', 'tools returned to wrong slots');
        check(!items.getBagLock(), 'return must unlock the client bag');
        items.setBagLock(true);
        check(!items.getBagLock() && engine.state.frog.status===0, 'gear alone must not lock or depart');
        check(items.getHouseItemCount(1000)===1, 'spent clover was returned to stock');
        // Koi jade remains reusable over two further trips.
        for (let trip=0; trip<2; trip++) {
            if (trip===0) check(items.setBagData(1,1001), 'cannot pack koi jade');
            engine.state.items.house.push({item_id:14,count:1});
            refresh();
            check(items.setBagData(0,14), 'cannot pack lunch');
            engine.state.travel.nextDepartAt = 1;
            engine.tick();
            engine.state.travel.returnAt = 1;
            engine.tick();
            refresh();
            check(items.getBagDataList()[1]===1001 && items.getHouseItemCount(1001)===1,
                'koi jade lost or duplicated');
        }
        const reload = FrogEngine.createEngine({savePath:'save.json',verbose:false});
        check(JSON.stringify(reload.state.items.bag)===JSON.stringify(engine.state.items.bag), 'packing save mismatch');
        return {passed:true,packed,returned,koiTrips:2,inventory:true,persisted:true};
    } finally { if(view.parent) view.parent.removeChild(view); }
})()
