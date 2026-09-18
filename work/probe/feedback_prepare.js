/* Dedicated profile only. Reload after seeding, so tutorial overlays cannot
 * survive an artificial mid-session transition from New to Complete. */
(function () {
    const engine=window.__engine;
    if(!engine)throw new Error('game engine not ready');
    engine.state.settings=Object.assign(engine.state.settings || {}, {guideStep:GuideStep.Complete,guideFurniture:6,
        guideFurnitureNotice:true,guideAnnualReview:true,guideDrawing:3,guideHandCraft:true,
        hasAchieve:true,guideCamera:true});
    engine.state.travel.nextDepartAt=Math.floor(Date.now()/1000)+10000;
    if(!engine.save())throw new Error('cannot seed the isolated test save');
    setTimeout(()=>location.reload(),300);
    return {seeded:true};
})()
