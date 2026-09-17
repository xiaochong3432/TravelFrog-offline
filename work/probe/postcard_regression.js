/* Run only in an isolated browser profile via cdp_drive.js. */
(async function () {
    const check = (ok, message) => { if (!ok) throw new Error(message); };
    const engine = window.__engine;
    check(engine && window.Tabikaeru, 'game engine not loaded');
    const savedPictures = engine.state.pictures;
    const ids = [2000,2003,1003,107,108,201,202,203,204,205,206,207,101,102,103,104];
    const captures = [];
    try {
        engine.state.pictures = ids.map((pic_id, i) => ({id:i+1,pic_id,read:1,new:0}));
        const reply = engine.dispatch('album_load_by_id_list', {id_list:ids.map((_,i)=>i+1)}).reply;
        check(reply.pic_list.length === ids.length, 'album returned incomplete pictures');
        for (const pic of reply.pic_list) {
            await Tabikaeru.loadPicture(pic);
            const texture = Tabikaeru.getPictureTexture(pic);
            check(texture, 'missing texture: '+pic.pic_id);
            check(texture.textureWidth === 500 && texture.textureHeight === 350, 'incorrect frame');
            const second = Tabikaeru.getPictureTexture(pic);
            check(texture === second, 'unchanged composition should reuse its texture');
            captures.push({id:pic.pic_id,png:texture.toDataURL('image/png'),layers:pic.layers});
            Tabikaeru.releasePictureTexture(second);
            Tabikaeru.releasePictureTexture(texture);
        }
        // Same resources and positions with different dimensions must not share
        // a cached render. This is used by the undersized sky backgrounds.
        const pic = reply.pic_list.find(p => p.layers.some(l => l.size));
        check(pic, 'fixture must exercise sky size');
        const first = Tabikaeru.getPictureTexture(pic);
        const other = JSON.parse(JSON.stringify(pic));
        other.layers.find(l => l.size).size[1] -= 20;
        const changed = Tabikaeru.getPictureTexture(other);
        check(first !== changed, 'size change reused stale cached texture');
        Tabikaeru.releasePictureTexture(first);
        Tabikaeru.releasePictureTexture(changed);
        window.__postcardCaptures = captures;
        return {passed:true,captures};
    } finally {
        engine.state.pictures = savedPictures;
    }
})()
