const fs=require('fs'),path=require('path'),vm=require('vm');

// 仓库根：按本文件自身位置推导，不写死绝对路径
const PROJECT_ROOT = require('path').resolve(__dirname, '..', '..');
const BUNDLE=path.join(PROJECT_ROOT + '/work/run/web/__offline-engine.js');
const map=new Map();
const store={getItem:k=>map.has(String(k))?map.get(String(k)):null,setItem:(k,v)=>{map.set(String(k),String(v));return true},removeItem:k=>map.delete(String(k)),key:i=>{const ks=Array.from(map.keys());return i<ks.length?ks[i]:null},get length(){return map.size}};
function boot(){const sb={console:{log(){},warn(){},error(){}},setTimeout,clearTimeout,setInterval,clearInterval,localStorage:store};sb.window=sb;sb.globalThis=sb;sb.self=sb;vm.createContext(sb);vm.runInContext(fs.readFileSync(BUNDLE,'utf8'),sb);return sb.window.FrogEngine.createEngine({savePath:'save.json',verbose:false});}
let e=boot();
e.dispatch('client_gm',{cmd:'set_clover 1111'});
e.dispatch('client_gm',{cmd:'set_clover 2222'});
const broken=store.getItem('frog.offline.save').slice(0,40);
store.setItem('frog.offline.save',broken);
console.log('--- keys after corruption:',JSON.stringify(Array.from(map.keys())));
e=boot();
console.log('boot2 action',e.state.__saveReport.action,e.state.__saveReport.restoredFrom,'kept',e.state.__saveReport.corruptKept);
console.log('--- keys:',JSON.stringify(Array.from(map.keys())));
e=boot();
console.log('boot3 action',e.state.__saveReport.action,e.state.__saveReport.restoredFrom,'kept',e.state.__saveReport.corruptKept);
console.log('--- keys:',JSON.stringify(Array.from(map.keys())));
console.log('primary now:',JSON.stringify(store.getItem('frog.offline.save')).slice(0,60));
