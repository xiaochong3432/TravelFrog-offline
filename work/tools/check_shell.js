const fs=require('fs');
const t=fs.readFileSync(process.argv[2],'utf8');
try { new Function(t); console.log('shell parses OK; ball:', t.includes('__save_ball'), 'panel:', t.includes('__save_panel'), 'travel_now:', t.includes('travel_now')); }
catch (e) { console.log('SYNTAX ERROR: ' + e.message); process.exit(1); }
