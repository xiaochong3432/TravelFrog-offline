/* Appended by patch_game.py after the original classes have been defined. */
(function () {
    // The old home framing stopped 80px before the right edge, putting the
    // mailbox under the fixed activity buttons on narrow screens.
    MainOutView.prototype.scroll = function (keepPosition) {
        if (!keepPosition) this.scroller.viewport.scrollH = Math.max(0, this.background.width - this.scroller.width);
        this.update_fg();
    };
    var weatherLoad = WeatherModel.prototype.weather_load;
    WeatherModel.prototype.weather_load = function (data) {
        var before = JSON.stringify(this.data);
        weatherLoad.call(this, data);
        this.dispatchEvent(new core.Event('offlineWeatherChanged'));
        if (before !== JSON.stringify(data)) {
            var controller = core.PageManage.getInstance().getControl(MainOutController, core.ViewLayerType.SceneLayer);
            var view = controller && controller.view;
            if (view && view.background) {
                view.hoursType = data.hours_type;
                view.seasonKey = this.getSeasonKey();
                view.update_season();
                view.updateFurniture();
                view.updateHouseLight();
            }
        }
    };
    var roomEvents = MainInController.prototype.totalCustomEvents;
    MainInController.prototype.totalCustomEvents = function (event) {
        roomEvents.call(this, event);
        if (!this.view || !this.view.flower) return;
        if (event.getEventType() === RoleEventType.loadRole) this.view.updateFlogStatus();
        if (event.getEventType() === 'offlineWeatherChanged') this.view.updateFurnitureAni();
    };
    var frogUpdate = MainInView.prototype.updateFlogStatus;
    var handcraftLoad = HandCraftModel.prototype.pray_load_grays;
    HandCraftModel.prototype.pray_load_grays = function (data, reply) {
        handcraftLoad.call(this, data, reply);
        var controller = core.PageManage.getInstance().getControl(MainInController, core.ViewLayerType.SceneLayer);
        if (controller && controller.view && controller.view.i_stampcraf) controller.view.checkHandCraft();
    };
    MainInView.prototype.updateFlogStatus = function () {
        this.fs_9_1.visible = true;
        this.curAnimName = '';
        frogUpdate.call(this);
        this.frogCap.visible = Tabikaeru.Game.instance().isHome && this.curAnimName !== 'egg_1_dress';
        this.updateFurnitureAni();
    };
    var furnitureAnimation = MainInView.prototype.updateFurnitureAni;
    MainInView.prototype.updateFurnitureAni = function () {
        furnitureAnimation.call(this);
        this.updateSeason();
    };
    // Re-entrant: switching time, furniture or activity never stacks night effects.
    MainInView.prototype.updateSeason = function () {
        this.hoursType = this.getModel(WeatherModel).data.hours_type;
        var night = this.hoursType >= 2;
        this.fs_5_1_bg.source = night ? 'mainin_ch_hy1_png' : 'mainin_ch_bt1_png';
        this.fs_5_2_bg.source = night ? 'mainin_ch_hy2_png' : 'mainin_ch_bt2_png';
        if (night && !this.offlineNightParticles) {
            var particles = this.offlineNightParticles = new SpineView();
            particles.touchEnabled = particles.touchChildren = false;
            particles.verticalCenter = particles.horizontalCenter = 0;
            particles.load('lizi', 'lizi', 'lizi');
            particles.play('1');
        }
        var effect = this.offlineNightParticles;
        if (night && effect && !effect.parent) this.group_5_1.addChild(effect);
        if (!night && effect && effect.parent) effect.parent.removeChild(effect);
        var lit = false;
        for (var i = 1; i <= 2; i++) {
            var slot = this.getFurnitureSlot('ani_25_' + i);
            var on = !!slot && slot.numChildren > 0;
            this['cover_25_' + i].visible = on;
            lit = lit || on;
        }
        this.cover_light.visible = lit;
        var matrix = night && Tabikaeru.DefineExtra.SeasonInColorMatrix[lit ? 'light' : 'default'];
        var nodes = [this.bgGroup, this.c_player_bed, this.c_player_out, this.frogCap];
        nodes.forEach(function (node) { if (node) node.filters = matrix ? [new egret.ColorMatrixFilter(matrix)] : []; });
    };
    var decorationUpdate = MainInView.prototype.updateDecoration;
    MainInView.prototype.updateDecoration = function () {
        this.flower.source = '';
        decorationUpdate.call(this);
    };
    // A plant update must not reset the whole garden and move the camera home.
    var flowerpotLoad = FurnitureModel.prototype.furniture_load_flowerpot;
    FurnitureModel.prototype.furniture_load_flowerpot = function (data) {
        flowerpotLoad.call(this, data);
        var controller = core.PageManage.getInstance().getControl(MainOutController, core.ViewLayerType.SceneLayer);
        var view = controller && controller.view;
        if (view && view.plantList) view.update_flowerpot();
    };
    // Track only seasonal overlays so refreshing weather cannot remove gameplay nodes.
    MainOutView.prototype.update_season = function () {
        var view = this, weather = this.getModel(WeatherModel);
        var generation = this.offlineSeasonGeneration = (this.offlineSeasonGeneration || 0) + 1;
        (this.offlineSeasonNodes || []).forEach(function (node) {
            if (node.stop) node.stop();
            if (node.destroy) node.destroy();
            if (node.parent) node.parent.removeChild(node);
        });
        this.offlineSeasonNodes = [];
        function add(group, node) {
            group.addChild(node);
            view.offlineSeasonNodes.push(node);
            node.touchEnabled = node.touchChildren = false;
        }
        this.seasonKey = weather.getSeasonKey();
        this.hoursType = weather.data.hours_type;
        var prefix = 'mainout_season' + this.seasonKey;
        this.background.source = prefix + '_bg_png';
        this.imgHouse.source = prefix + '_fz_png';
        this.imgFurnitureBenchEmpty.source = prefix + '_zw_png';
        this.imgWater.source = prefix + '_ct_png';
        this.imgLightCover.source = this.hoursType >= 3 ? prefix + '_light_cover_png' : '';
        weather.getSeasonCover().forEach(function (row) {
            var node = new eui.Image();
            add(row.is_mid ? view.groupCoverMid : row.is_bg ? view.bgGroup : view.groupCoverDown, node);
            node.source = row.png; node.x = row.x; node.y = row.y;
        });
        weather.getSeasonSpine().forEach(function (row) {
            var node = new SpineView();
            add(view.groupCoverMid, node);
            node.bottom = row.bottom; node.horizontalCenter = row.horizontalCenter;
            node.verticalCenter = row.verticalCenter; node.load(row.name);
        });
        weather.getSeasonPartical().forEach(function (row) {
            Promise.all([RES.getResAsync(row.name + '_png'), RES.getResAsync(row.name + '_json')]).then(function (resources) {
                if (view.offlineSeasonGeneration !== generation || !resources[0] || !resources[1]) return;
                var node = new particle.GravityParticleSystem(resources[0], resources[1]);
                add(view.groupCoverMid, node);
                node.x = row.x; node.y = row.y; node.start();
            }).catch(function (error) { console.warn('Weather effect unavailable', error); });
        });
        var matrix = Tabikaeru.DefineExtra.SeasonColorMatrix[this.seasonKey];
        [this.groupTumber,this.compost,this.imgPocket,this.groupMid,this.groupPot1].forEach(function (node) {
            if (node) node.filters = matrix ? [new egret.ColorMatrixFilter(matrix)] : [];
        });
    };
})();
