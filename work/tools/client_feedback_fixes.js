/* Offline replacements for channel features whose TestChannel implementations are empty. */
(function () {
    // The offline payload exposes all six clover packs. RechargeView's field page
    // has a fixed, non-scrolling 679px list designed for at most three 182px plots,
    // so rows four through six overflow the dialog and cover the watering button.
    // The shipped client also contains RechargeSimpleView: a compact scrollable
    // list made for these same rechargeDB rows. Use that complete layout here.
    RechargeViewController.prototype.open = function () {
        if (this.getModel(UserModel).isBagayalu) {
            core.DisplayManage.getInstance().popupLayer.addChild(new ModalAlert('充值功能仅在中国大陆地区适用'));
            core.PageManage.getInstance().removeControl(RechargeViewController, this.getViewLayerType());
            return;
        }
        var fresh = false;
        if (!(this.view instanceof RechargeSimpleView)) {
            if (this.view && this.view.parent) this.view.parent.removeChild(this.view);
            this.view = new RechargeSimpleView(this);
            fresh = true;
        }
        this.getParent().addChild(this.view);
        if (!fresh) this.view.open();
        Music.play('SE_Popup');
        this.getModel(ShareModel).reportBlog('recharge.click');
    };

    // Compost mutations are authoritative and atomic. The old client removed
    // then inserted in separate calls and overwrote a newer server push locally.
    FurnitureModel.prototype.setCompostItem = function (index, id) {
        var callback = new core.Action2(function (reply) {
            if (reply && reply.code === 6) GuideHelpView.getInstance().show('该格正在发酵，完成后才能操作');
        });
        if (id) core.SocketManage.getInstance().send('furniture_putin_box', callback, index, id);
        else core.SocketManage.getInstance().send('furniture_takeout_box', callback, index);
    };
    var saving = false;
    TestChannel.prototype.save_texture_to_album = async function (texture) {
        if (saving || !texture) return false;
        saving = true;
        try {
            var data = texture.toDataURL('image/png');
            if (!data || data.indexOf('data:image/png;base64,') !== 0) return false;
            var name = 'frog-photo-' + Date.now() + '.png';
            if (window.FrogNative) {
                if (!FrogNative.exportImage) return false;
                // Register before opening SAF: its result arrives asynchronously.
                var finish;
                var result = new Promise(function (resolve) { finish = resolve; });
                window.__frogImageExportResult = function (where) { finish(!!where); };
                var where = String(FrogNative.exportImage(name, data) || '');
                if (where === 'PICKER') return await result;
                return !!where;
            }
            var bytes = atob(data.slice(data.indexOf(',') + 1));
            var buffer = new Uint8Array(bytes.length);
            for (var i = 0; i < bytes.length; i++) buffer[i] = bytes.charCodeAt(i);
            var url = URL.createObjectURL(new Blob([buffer], {type:'image/png'}));
            var link = document.createElement('a');
            link.href = url; link.download = name;
            document.body.appendChild(link); link.click(); link.remove();
            setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
            return true;
        } catch (error) {
            console.warn('Photo export failed', error);
            return false;
        } finally {
            saving = false;
            delete window.__frogImageExportResult;
        }
    };
})();
