// Fast regressions for the production title-page helpers, without browser writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../static/app.js'), 'utf8');
function section(start, end) { return source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start))); }
const calls = [], pending = [];
const state = {
  item: {title:'MobLand', clean_title:'MobLand', tmdb_id:247718, media_type:'tv', size_label:'50 GB', magnet:'magnet:whole-show', releases:[]},
  data: {title:'MobLand', original_title:'MobLand', tmdb_id:247718, media_type:'tv', year:'2025', last_air_date:'2026-10-01', season_list:[{number:1},{number:2}]},
  library:{id:'TV Shows/MobLand'}, browseSeason:2, releaseRequest:0,
  episodeNames:{2:{1:{number:1,name:'First',overview:'One'},2:{number:2,name:'Second',overview:'Two'}}},
  libraryFiles:[{files:[{path:'TV Shows/MobLand/S02E01.mkv',name:'S02E01.mkv',season:2,episode:1}]}], added:new Set(),category:'TV Shows'
};
state.item.library=state.library;
const context={URL, console, detailsState:state, detailsRequestId:1, searchEnabled:true, releasesCache:new Map(),
  location:{href:'http://server.test/?title=MobLand&type=tv&id=247718'},
  history:{state:{ttTitle:{item:state.item},ttDepth:1},replaceState:(s,t,url)=>calls.push({kind:'route',url:String(url),state:s})},
  document:{getElementById:()=>({scrollIntoView:()=>calls.push({kind:'scroll'})})},
  libraryFileList:()=>context.detailsState.libraryFiles.flatMap(g=>g.files),
  episodeOf:f=>f.season!=null&&f.episode!=null?{season:f.season,episode:f.episode,last:f.last_episode||f.episode}:null,
  loadEpisodeNames:()=>{}, escapeHtml:s=>String(s??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;'),
  PLAY_ICON:'play',renderDetailsBody:()=>{},renderDetailsHero:()=>{},matchMedia:()=>({matches:true}),
  playLibraryFrom:file=>calls.push({kind:'play',file}),rememberCategory:()=>{},refresh:()=>{},showToast:()=>{},
  fetch:(url,options)=> options ? Promise.resolve({json:async()=>{calls.push({kind:'download',url,body:JSON.parse(options.body)});return {};}})
    :new Promise(resolve=>pending.push({url,resolve:data=>resolve({json:async()=>data})}))
};
vm.createContext(context);
vm.runInContext(section('function titlePageURL(', 'function openDetails('),context);
vm.runInContext(section('function releaseKey(', 'function categoryForKind('),context);
vm.runInContext(section('function releaseMatches(', 'async function loadReleases('),context);
vm.runInContext(section('async function loadReleases(', 'function primaryRelease('),context);
vm.runInContext(section('function titleEpisodeFiles(', 'function renderDetailsBody('),context);
vm.runInContext(section('async function postSearchResult(', 'async function addSearchResult('),context);
vm.runInContext(section('async function downloadRelease(', 'detailsBody.addEventListener('),context);
(async()=>{
  context.currentCategories = ['Movies', 'TV Shows', 'Kids & <Family>'];
  context.ICONS = {check:'<svg></svg>'};
  const picker = context.renderTitleFolderPicker(state);
  assert.match(picker, /aria-haspopup="menu" aria-expanded="false"/);
  assert.match(picker, /aria-checked="true"[^>]*data-category="TV Shows"/);
  assert.match(picker, /Kids &amp; &lt;Family>/);
  assert.doesNotMatch(picker, /<select/);
  const html=context.renderTitleEpisodes(state);
  assert.match(html,/Play episode: 1\. First/);
  assert.match(html,/Find a version: 2\. Second/);
  assert.match(html,/On your server/);
  context.selectTitleSeason(1);
  assert.equal(new URL(calls.find(c=>c.kind==='route').url).searchParams.get('season'),'1');
  state.browseSeason=2; context.renderTitleEpisodes(state);
  context.findTitleEpisode(1);
  assert.equal(calls.find(c=>c.kind==='play').file.path,'TV Shows/MobLand/S02E01.mkv');
  const old=context.loadReleases('MobLand',1,true);
  context.findTitleEpisode(2);
  const episode=pending.find(p=>decodeURIComponent(p.url).includes('S02E02'));
  assert.ok(episode,'Missing episode must search for the selected episode, without downloading');
  episode.resolve({results:[{title:'MobLand S02E02 (2026)',magnet:'magnet:episode',seeders:5,size_label:'2 GB'}]});
  await new Promise(resolve=>setImmediate(resolve));
  pending.find(p=>!decodeURIComponent(p.url).includes('S02E02')).resolve({results:[{title:'MobLand whole show (2026)',magnet:'magnet:old',seeders:10}]});
  await old;
  assert.equal(state.releases.length,1);
  assert.equal(state.releases[0].magnet,'magnet:episode','A late whole-show search must not overwrite the episode choice');
  await context.downloadRelease(state.releases[0]);
  const download=calls.find(c=>c.kind==='download');
  assert.equal(download.url,'/api/torrents');
  assert.equal(download.body.category,'TV Shows');
  assert.equal(download.body.magnet,'magnet:episode');
  console.log('Title-page checks passed: seasons, one-file episode availability, playback source, release race, download folder and source');
})().catch(e=>{console.error(e);process.exitCode=1;});
