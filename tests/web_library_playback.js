// Exercise the production player links and library episode launch together.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../static/app.js'), 'utf8');
function section(start, end) {
  return source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));
}
const requests = [];
let player = 'infuse';
const files = [
  {path:'TV Shows/Friends/Season 8/S08E03.mkv', name:'S08E03.mkv', season:8, episode:3},
  {path:'TV Shows/Friends/Season 8/S08E04 Друзі & #1.mkv', name:'S08E04 Друзі & #1.mkv', season:8, episode:4},
  {path:'TV Shows/Friends/Season 8/S08E05.mkv', name:'S08E05.mkv', season:8, episode:5},
];
const context = {
  location:{origin:'http://nas.test:5058', href:'http://nas.test:5058/?title=Friends&season=8'},
  currentPlayer:()=>player, libraryFileList:()=>files,
  VLC_HELPER_OS:null, IS_IOS:true, IS_ANDROID:false,
  hashHex:()=> '0123456789abcdef',
  fetch:(url, options)=>{ requests.push({url, body:JSON.parse(options.body)}); return Promise.resolve({}); },
};
vm.createContext(context);
vm.runInContext(section('function infusePlaybackLink(', '// One player for the whole app'), context);
vm.runInContext(section('function libraryMediaUrl(', '// TMDB\'s names and stills'), context);
vm.runInContext(section('function playLibraryFrom(', '// Library titles matching a search'), context);

context.playLibraryFrom(files[1]);
let link = new URL(context.location.href);
assert.equal(link.protocol, 'infuse:');
assert.deepEqual(link.searchParams.getAll('url'), [context.libraryMediaUrl(files[1]), context.libraryMediaUrl(files[2])]);
assert.deepEqual(link.searchParams.getAll('filename'), [files[1].name, files[2].name]);
assert.equal(link.searchParams.has('x-success'), false, 'Closing Infuse must not open another server tab');
assert.equal(link.searchParams.has('x-error'), false);
assert.equal(requests.length, 0, 'Infuse must not race playlist registration or open an M3U');

// A file outside the deduplicated queue must play itself, not episode one.
const alternate = {...files[1], path:'TV Shows/Friends/Alternate/S08E04.mkv'};
context.playLibraryFrom(alternate);
link = new URL(context.location.href);
assert.deepEqual(link.searchParams.getAll('url'), [context.libraryMediaUrl(alternate)]);
context.playLibraryFrom(undefined);

// Movies and a one-episode library also use a direct link.
const movie = {path:'Movies/A & B.mp4', name:'A & B.mp4'};
context.playLibraryFile(movie);
link = new URL(context.location.href);
assert.equal(link.searchParams.get('url'), context.libraryMediaUrl(movie));
assert.equal(link.searchParams.get('filename'), movie.name);

// Buffered torrent callers retain their existing single URL and callbacks.
const torrentUrl = 'http://nas.test:5058/stream/abc/1/episode.mkv';
link = new URL(context.infusePlaybackLink(torrentUrl, 'http://nas.test:5058/played/abc'));
assert.deepEqual(link.searchParams.getAll('url'), [torrentUrl]);
assert.equal(link.searchParams.get('x-success'), 'http://nas.test:5058/played/abc');

const largeQueue = Array.from({length:1000}, (_, i)=>({url:`http://nas.test/${'long-path/'.repeat(20)}${i}.mkv`, name:`${i}.mkv`}));
const bounded = context.infusePlaybackLink(largeQueue[0].url, 'http://nas.test/', largeQueue);
assert.ok(bounded.length <= 16000);
link = new URL(bounded);
assert.equal(link.searchParams.getAll('url')[0], largeQueue[0].url);
assert.ok(link.searchParams.getAll('url').length > 1);
assert.ok(link.searchParams.getAll('url').length < largeQueue.length);

// VLC keeps the existing registered playlist and episode order.
player = 'vlc';
context.playLibraryFrom(files[1]);
assert.equal(requests[0].url, '/api/library/playlist');
assert.deepEqual(Array.from(requests[0].body.files), files.slice(1).map(f=>f.path));
link = new URL(context.location.href);
assert.equal(link.protocol, 'vlc-x-callback:');
assert.equal(link.searchParams.get('url'), 'http://nas.test:5058/playlist/0123456789abcdef.m3u');
assert.equal(link.searchParams.has('x-success'),false,'Mobile VLC must not open another server tab either');
assert.equal(link.searchParams.has('x-error'),false);

// Torrent playback must also rely on connection cleanup, not a browser URL.
player = 'infuse';
context.detailsState = {torrent:{id:'abc'}};
context.playLink = () => ({token:'d-abc',url:torrentUrl,closedUrl:'http://nas.test:5058/played/d-abc'});
context.registerPlayLink = () => {};
context.watchPlayStart = () => {};
context.watchAppOpened = () => {};
vm.runInContext(section('function playRelease(', '// ---------- VLC helper'),context);
context.playRelease(null);
link = new URL(context.location.href);
assert.equal(link.searchParams.get('url'),torrentUrl);
assert.equal(link.searchParams.has('x-success'),false);
assert.equal(link.searchParams.has('x-error'),false);
console.log('Library playback checks passed: selected episode, direct Infuse queue, Unicode paths, single files, bounded queues, torrent links and VLC playlists');
