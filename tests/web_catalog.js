// Catalog source selection and search-toggle behavior, without NAS changes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const elements = new Map(), requests = [];
function element(id) {
  if (!elements.has(id)) {
    const classes = new Set(), attributes = {}, listeners = {};
    elements.set(id,{dataset:{},attributes,listeners,addEventListener:(type,fn)=>listeners[type]=fn,
      setAttribute:(key,value)=>attributes[key]=value,removeAttribute:key=>delete attributes[key],
      classList:{contains:key=>classes.has(key),remove:key=>classes.delete(key),toggle:(key,on)=>{
        const next=on===undefined?!classes.has(key):on; if(next)classes.add(key);else classes.delete(key);return next;
      }},focus:()=>{ elements.get(id).focused=true; },blur:()=>{ elements.get(id).focused=false; }});
  }
  return elements.get(id);
}
const nav = ['home','movie','tv','cartoon','library','downloads'].map(view=>{
  const e=element(view);e.dataset.view=view;return e;
});
const rows = [
  {title:'Film One 1080p',clean_title:'Film One',magnet:'magnet:one',size_label:'2 GB'},
  {title:'Film One 2160p',clean_title:'Film One',magnet:'magnet:two',size_label:'5 GB'},
  {title:'Film Two',clean_title:'Film Two',magnet:'magnet:three'},
];
const context={console,URL,Date,Map,Set,Promise,JSON,Number,
  document:{body:{dataset:{serverView:'home'}},getElementById:element,querySelector:()=>element('topbar'),querySelectorAll:()=>nav,addEventListener:()=>{}},
  libraryItems:[{id:'Library only',title:'Library only'}],libraryPanel:element('libraryPanel'),librarySection:'favorites',
  detailsState:null,personState:null,discoverMode:false,closeSearchDropdown:()=>{},renderLibrary:()=>{},renderViewToggleBtn:()=>{},window:{scrollTo:()=>{}},
  roughTitle:value=>value,plainText:value=>value.toLowerCase(),
  fetch:async url=>{requests.push(url);return {ok:true,json:async()=>({results:rows})};},
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(require('node:path').join(__dirname,'../static/server-home.js'),'utf8'),context);
context.renderCatalogPage=()=>{};
context.renderServerHome=()=>{};
(async()=>{
  await Promise.all([context.loadCatalogFeed('movies'),context.loadCatalogFeed('movies')]);
  assert.equal(requests.length,1,'Concurrent catalog loads must reuse the request');
  const movies=context.catalogEntries('movies');
  assert.equal(movies.length,2,'Copies of one torrent title are versions of a single card');
  assert.equal(movies[0].releases.length,2);
  assert.ok(!movies.some(item=>item.title==='Library only'),'Browsing uses torrent feeds, not library files');
  assert.equal(context.catalogFeedForView('movie'),'movies');
  assert.equal(context.catalogFeedForView('tv'),'tv');
  assert.equal(context.catalogFeedForView('cartoon'),'cartoons');
  assert.equal(context.catalogFeedForView('library'),undefined);
  context.setServerView('movie');
  assert.equal(context.librarySection,'favorites','Catalog navigation must not change the Library chip');
  assert.equal(context.libraryPanel.hidden,true);
  context.setServerView('favorites');
  assert.equal(context.document.body.dataset.serverView,'library');
  assert.equal(context.libraryPanel.hidden,false);
  assert.equal(element('library').attributes['aria-current'],'page');
  context.setServerView('downloads');
  assert.equal(element('downloads').attributes['aria-current'],'page');
  const toggle=element('searchToggleBtn');
  toggle.listeners.click();
  assert.equal(toggle.attributes['aria-expanded'],'true');
  assert.equal(toggle.attributes['aria-label'],'Close search');
  assert.equal(element('mainInput').focused,true);
  toggle.listeners.click();
  assert.equal(toggle.attributes['aria-expanded'],'false');
  assert.equal(toggle.attributes['aria-label'],'Search');
  assert.equal(element('mainInput').focused,false);
  console.log('Catalog checks passed: torrent sources, version grouping, request reuse, Library isolation, Downloads navigation, and search open/close');
})().catch(e=>{console.error(e);process.exitCode=1;});
