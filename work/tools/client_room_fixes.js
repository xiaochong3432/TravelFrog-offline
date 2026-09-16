/* Appended by patch_game.py after the original classes have been defined. */
(function () {
    var weatherLoad = WeatherModel.prototype.weather_load;
    WeatherModel.prototype.weather_load = function (data) {
        weatherLoad.call(this, data);
        this.dispatchEvent(new core.Event('offlineWeatherChanged'));
    };
    var roomEvents = MainInController.prototype.totalCustomEvents;
    MainInController.prototype.totalCustomEvents = function (event) {
        roomEvents.call(this, event);
        if (!this.view || !this.view.flower) return;
        if (event.getEventType() === RoleEventType.loadRole) this.view.updateFlogStatus();
        if (event.getEventType() === 'offlineWeatherChanged') this.view.updateFurnitureAni();
    };
    var frogUpdate = MainInView.prototype.updateFlogStatus;
    MainInView.prototype.updateFlogStatus = function () {
        this.fs_9_1.visible = true;
        this.curAnimName = '';
        frogUpdate.call(this);
        this.frogCap.visible = Tabikaeru.Game.instance().isHome && !this.roleModel.isFrogSleep();
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
            var on = night && !!slot && slot.numChildren > 0;
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
})();
