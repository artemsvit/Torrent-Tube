// Check real history identities and callback handling; no live NAS writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const app = fs.readFileSync(path.join(__dirname,'../static/app.js'),'utf8');
const home = fs.readFileSync(path.join(__dirname,'../static/server-home.js'),'utf8');
const stored = new Map(), calls = [], errors = [];
const entry = {torrent_id:'lib:TV Shows/Friends',file:172,title:'Friends',seconds:82.7,duration:1348,updated_at:1,source:{path:'TV Shows/Friends',file:172}};
const selected = {index:172,path:'TV Shows/Friends/Season 8/Friends.S08E04 & 174.mkv',name:'Friends.S08E04 & 174.mkv'};
const context = {
  URL, URLSearchParams, console, Date, Number, crypto:{randomUUID:()=> 'test-token'},
  document:{addEventListener:()=>{},getElementById:()=>({addEventListener:()=>{}})},
  location:{href:'http://nas.test:5058/',origin:'http://nas.test:5058',pathname:'/'},
  localStorage:{getItem:key=>stored.get(key),setItem:(key,value)=>stored.set(key,value),removeItem:key=>stored.delete(key)},
  currentPlayer:()=> 'infuse', libraryMediaUrl:file=> 'http://nas.test:5058/media/'+file.path.split('/').map(encodeURIComponent).join('/'),
  showToast:message=>errors.push(message),
  history:{state:{},replaceState:(state,title,url)=>calls.push({kind:'route',url:String(url)})},
  fetch:async(url,options)=>{
    calls.push({kind:'fetch',url,body:options && JSON.parse(options.body)});
    return {ok:true,json:async()=>({files:[{index:0,path:'wrong.mkv'},selected]})};
  },
};
vm.createContext(context);
vm.runInContext(app.slice(app.indexOf('function infusePlaybackLink('),app.indexOf('const PLAYERS =')),context);
vm.runInContext(home,context);
context.loadServerHistory=async()=>{};
(async()=>{
  const mixed=context.featuredLibraryItems([{id:'tv1',kind:'tv'},{id:'tv2',kind:'tv'},{id:'movie1',kind:'movie'},{id:'kid1',kind:'cartoon'}]);
  assert.equal(new Set(mixed.map(i=>i.id)).size,mixed.length);
  assert.equal(mixed[0].id,'tv1');
  assert.ok(mixed.some(i=>i.kind==='movie') && mixed.some(i=>i.kind==='cartoon'));
  await context.resumeServerEntry(entry);
  const link=new URL(context.location.href);
  assert.equal(link.searchParams.get('url'),context.libraryMediaUrl(selected),'Resume must use the native history file index');
  assert.equal(link.searchParams.get('position'),'82');
  assert.equal(link.searchParams.get('filename'),selected.name);
  assert.equal(link.searchParams.has('x-success'),false,'Resume must not open another server tab on close');
  assert.equal(link.searchParams.has('x-error'),false);
  assert.equal(stored.size,0);
  assert.equal(calls[0].body.path,'TV Shows/Friends');
  // Old, already issued callbacks remain readable during the transition.
  stored.set('server-resume:test-token',JSON.stringify({entry,url:context.libraryMediaUrl(selected)}));
  context.location.href='http://nas.test:5058/?'+new URLSearchParams({resume_return:'test-token',lastPlayedUrl:context.libraryMediaUrl(selected),position:'110'});
  await context.handleServerResumeReturn();
  const update=calls.find(c=>c.url==='/api/continue-watching').body.items[0];
  assert.equal(update.file,172);
  assert.equal(update.torrent_id,entry.torrent_id);
  assert.equal(update.seconds,110);
  assert.ok(update.updated_at>entry.updated_at);
  assert.equal(update.removed,false);
  assert.equal(stored.size,0);

  // A callback for a different URL must never update another episode.
  calls.length=0;
  stored.set('server-resume:test-token',JSON.stringify({entry,url:context.libraryMediaUrl(selected)}));
  context.location.href='http://nas.test:5058/?resume_return=test-token&lastPlayedUrl=wrong&position=999';
  await context.handleServerResumeReturn();
  assert.ok(!calls.some(c=>c.url==='/api/continue-watching'));

  // Completed episodes leave Continue Watching with a dated removal.
  calls.length=0;
  stored.set('server-resume:test-token',JSON.stringify({entry,url:context.libraryMediaUrl(selected)}));
  context.location.href='http://nas.test:5058/?'+new URLSearchParams({resume_return:'test-token',lastPlayedUrl:context.libraryMediaUrl(selected),position:'1340'});
  await context.handleServerResumeReturn();
  assert.equal(calls.find(c=>c.url==='/api/continue-watching').body.items[0].removed,true);
  assert.deepEqual(errors,[]);
  console.log('Home checks passed: mixed featured titles, exact episode resume, Infuse position, shared history update, mismatched callback rejection and completion removal');
})().catch(e=>{console.error(e);process.exitCode=1;});
