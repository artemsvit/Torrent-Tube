// Shared library and history, presented like the Apple clients. Download
// controls remain in the existing Discover, search and Downloads screens.
let serverHistory = [], homeFeaturedIndex = 0, homeRenderKey = "", homeHeroRequest = 0;
let serverOnline = false, homeLibraryError = '', serverOverviewKey = '';
const homeMetadata = new Map();

function updateServerNavigation(view) {
  document.getElementById('browseDiscoverBtn').setAttribute('aria-pressed', String(view === 'discover'));
  document.querySelectorAll('#serverNavigation [data-view]').forEach(button => {
    if (button.dataset.view === view) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  });
}

function setServerView(view) {
  closeSearchDropdown();
  if (detailsState || personState) closeDetails();
  if (view === 'discover') { enterDiscover(); return; }
  if (discoverMode) exitDiscover();
  document.body.dataset.serverView = view;
  updateServerNavigation(view);
  renderViewToggleBtn();
  if (['movie', 'tv', 'cartoon', 'favorites'].includes(view)) librarySection = view;
  renderLibrary();
  // The Library destination stays useful when the optional split-view
  // library setting was disabled or there are no titles yet.
  if (['library', 'movie', 'tv', 'cartoon', 'favorites'].includes(view)) libraryPanel.hidden = false;
  window.scrollTo({top:0});
}

function updateServerOverview(online) {
  if (online !== undefined) serverOnline = online;
  const speed = currentTorrents.reduce((sum, item) => sum + (item.download_rate || 0), 0);
  const key = JSON.stringify([serverOnline,currentTorrentCount,libraryItems.length,speed,lastConfig.download_dir_host,lastConfig.download_dir,searchEnabled]);
  if (key === serverOverviewKey) return;
  serverOverviewKey = key;
  document.getElementById('serverHost').textContent = location.host;
  document.getElementById('serverFolder').textContent = lastConfig.download_dir_host || lastConfig.download_dir || '';
  document.getElementById('serverStatusDot').classList.toggle('is-online', serverOnline);
  const stats = document.getElementById('serverOverviewStats');
  stats.innerHTML = `<span>${serverOnline ? 'Connected' : 'Connecting…'}</span><span><b>${libraryItems.length}</b> titles</span><span><b>${currentTorrentCount}</b> active downloads</span>${speed ? `<span><b>${formatBytes(speed)}/s</b></span>` : ''}<span>Search ${searchEnabled ? 'enabled' : 'not configured'}</span>`;
}

function featuredLibraryItems(items) {
  // Start with the newest title, then mix the content types in the banner.
  const result = items.slice(0, 1);
  for (const kind of ['movie', 'tv', 'cartoon']) {
    for (const item of items.filter(i => i.kind === kind).slice(0, 2)) {
      if (!result.some(i => i.id === item.id)) result.push(item);
    }
  }
  return result.slice(0, 7);
}

function homeTime(seconds) {
  const value = Math.max(0, Math.floor(seconds));
  return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, '0')}`;
}

function renderHomeHero() {
  const hero = document.getElementById('homeFeatured');
  const items = featuredLibraryItems(libraryItems);
  if (!items.length) {
    if (!libraryLoaded) {
      hero.innerHTML = `<div class="home-loading" role="status">${homeLibraryError ? `${escapeHtml(homeLibraryError)} <button type="button" class="btn-secondary" id="homeLibraryRetry">Try again</button>` : 'Loading your library…'}</div>`;
      const retry = document.getElementById('homeLibraryRetry');
      if (retry) retry.onclick = () => loadLibrary(true);
      return;
    }
    hero.innerHTML = `<div class="home-hero-copy home-empty"><span class="home-eyebrow">Your server</span><h2>Your next watch starts here</h2><p>Your library, favorites and viewing history in one place. Search for a title or add a torrent to grow your library.</p><div class="home-hero-actions"><button type="button" class="btn-primary btn-pill" data-home-view="discover">Discover</button><button type="button" class="btn-secondary" data-home-view="downloads">Downloads</button></div></div>`;
    return;
  }
  homeFeaturedIndex %= items.length;
  const item = items[homeFeaturedIndex], data = homeMetadata.get(item.id) || item;
  const title = libraryTitle(item), art = data.backdrop || data.banner;
  hero.innerHTML = `${art ? `<img class="home-hero-art" src="${escapeHtml(art)}" alt="">` : `<div class="home-hero-placeholder">${brandArt(title, true)}</div>`}
    <div class="home-hero-shade"></div><div class="home-hero-copy"><span class="home-eyebrow">In your library</span>
    <h2 data-no-i18n>${escapeHtml(title)}</h2><div class="home-hero-meta"><span>${{movie:'Movie',tv:'TV show',cartoon:'Cartoon'}[item.kind] || 'Movie'}</span>${data.year || item.year ? `<span>${escapeHtml(String(data.year || item.year))}</span>` : ''}${item.rating ? `<span class="home-rating">★ ${item.rating.toFixed(1)}</span>` : ''}${item.seasons ? `<span>${item.seasons} seasons</span>` : ''}</div>
    <p data-no-i18n>${escapeHtml(data.overview || item.overview || '')}</p>
    <div class="home-hero-actions"><button type="button" class="btn-primary btn-pill" id="homeHeroPlay">${ICONS.play}Watch</button><button type="button" class="btn-secondary" id="homeHeroDetails">Details</button><button type="button" class="btn-secondary home-hero-favorite" id="homeHeroFavorite" aria-pressed="${isFavorite(item.id)}" aria-label="${isFavorite(item.id) ? 'Remove from Favorites' : 'Add to Favorites'}">${isFavorite(item.id) ? ICONS.heartFilled : ICONS.heart}</button></div></div>
    <div class="home-hero-pages" role="group" aria-label="Featured titles">${items.map((i,n)=>`<button type="button" data-featured="${n}" aria-label="${escapeHtml(libraryTitle(i))}" aria-pressed="${n === homeFeaturedIndex}"></button>`).join('')}</div>`;
  document.getElementById('homeHeroDetails').onclick = () => openLibraryTitle(item);
  document.getElementById('homeHeroPlay').onclick = async () => {
    try {
      const data = await fetch('/api/playback/prepare', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({path:item.id})}).then(r=>r.json());
      if (!data.files?.length) throw new Error(data.error || 'No video files were found');
      const file = data.files.find(f=>f.index === data.selected) || data.files[0];
      playLibraryFile(item.kind === 'tv' || item.kind === 'cartoon' ? data.files[0] : file);
    } catch (e) { showToast(e.message, true); }
  };
  document.getElementById('homeHeroFavorite').onclick = () => toggleFavorite({library:item,item:{title,poster:item.poster},data:{tmdb_id:item.tmdb_id,media_type:item.media_type,title}});
  const request = ++homeHeroRequest;
  if (!homeMetadata.has(item.id) && item.tmdb_id && item.media_type) {
    fetch(`/api/details?type=${encodeURIComponent(item.media_type)}&id=${item.tmdb_id}`).then(r=>r.json()).then(data=>{
      if (data.error) return;
      homeMetadata.set(item.id, data);
      if (request === homeHeroRequest) renderHomeHero();
    }).catch(()=>{});
  }
}

function appendHomeShelf(root, title, view, items, buildCard) {
  if (!items.length) return;
  const shelf = document.createElement('section');
  shelf.className = 'home-shelf';
  shelf.innerHTML = `<div class="home-shelf-heading"><h2>${title}</h2>${view ? `<button type="button" class="home-see-all" data-home-view="${view}">See all ${CHEVRON_DOWN}</button>` : '<span class="home-sync-note">Synced across devices</span>'}</div><div class="home-shelf-track"></div>`;
  const track = shelf.querySelector('.home-shelf-track');
  items.slice(0, 20).forEach(item => track.appendChild(buildCard(item)));
  root.appendChild(shelf);
}

function buildContinueCard(entry) {
  const card = document.createElement('button');
  card.type = 'button'; card.className = 'home-continue-card';
  card.innerHTML = `<div class="home-continue-art">${entry.artwork ? `<img src="${escapeHtml(entry.artwork)}" alt="" loading="lazy">` : brandArt(entry.title,true)}<progress max="${entry.duration}" value="${entry.seconds}" aria-label="Playback progress"></progress><span class="home-resume-icon">${ICONS.play}</span></div><strong data-no-i18n>${escapeHtml(entry.title)}</strong><span>Resume at ${homeTime(entry.seconds)}</span>`;
  card.onclick = () => resumeServerEntry(entry);
  return card;
}

function renderServerHome() {
  updateServerOverview();
  const key = JSON.stringify([libraryLoaded,homeLibraryError,libraryItems,favorites,serverHistory]);
  if (key === homeRenderKey) return;
  homeRenderKey = key;
  renderHomeHero();
  const root = document.getElementById('homeShelves');
  root.replaceChildren();
  appendHomeShelf(root,'Continue Watching',null,serverHistory,buildContinueCard);
  appendHomeShelf(root,'Recently added','library',libraryItems,buildLibraryCard);
  for (const [kind,label] of LIBRARY_KINDS) appendHomeShelf(root,label,kind,libraryItems.filter(i=>i.kind === kind),buildLibraryCard);
  appendHomeShelf(root,'Favorites','favorites',favorites,buildFavoriteCard);
}

async function loadServerHistory() {
  try {
    const response = await fetch('/api/continue-watching');
    if (!response.ok) return;
    const data = await response.json();
    serverHistory = data.items || [];
    renderServerHome();
  } catch (e) {}
}

async function resumeServerEntry(entry) {
  // Native history uses a folder path plus the explicit file index.
  // Resolve it again, rather than guessing an episode from its title.
  if (!entry.source.path) {
    openDetails({title:entry.title,poster:entry.artwork,...entry.source});
    return;
  }
  try {
    const response = await fetch('/api/playback/prepare', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({path:entry.source.path})});
    const prepared = await response.json();
    const file = prepared.files?.find(f=>f.index === entry.file);
    if (!response.ok || !file) throw new Error(prepared.error || 'That title is no longer on the server');
    const url = libraryMediaUrl(file);
    if (currentPlayer() !== 'infuse') { playLibraryFile(file); return; }
    location.href = infusePlaybackLink(url,null,[{url,name:file.name,position:Math.floor(entry.seconds)}]);
  } catch (e) { showToast(e.message, true); }
}

async function handleServerResumeReturn() {
  const url = new URL(location.href), token = url.searchParams.get('resume_return');
  if (!token) return;
  try {
    const saved = JSON.parse(localStorage.getItem(`server-resume:${token}`) || 'null');
    const raw = url.searchParams.get('position'), seconds = raw === null ? NaN : Number(raw);
    if (saved && url.searchParams.get('lastPlayedUrl') === saved.url && Number.isFinite(seconds) && seconds >= 0) {
      const change = {...saved.entry,seconds,updated_at:Date.now()/1000,removed:seconds >= saved.entry.duration - 15};
      const response = await fetch('/api/continue-watching',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({items:[change]})});
      if (!response.ok) throw new Error('Could not save playback position');
      await loadServerHistory();
    }
    localStorage.removeItem(`server-resume:${token}`);
  } catch (e) { showToast('Could not save playback position',true); }
  for (const key of ['resume_return','position','lastPlayedUrl','failedUrl','errorCode','errorMessage']) url.searchParams.delete(key);
  history.replaceState(history.state,'',url);
}

document.getElementById('serverNavigation').addEventListener('click',e=>{
  const button = e.target.closest('[data-view]');
  if (button) setServerView(button.dataset.view);
});
document.getElementById('browseDiscoverBtn').addEventListener('click',()=>setServerView('discover'));
const browseSearch = document.getElementById('mainInput');
browseSearch.addEventListener('focus',()=>{ browseSearch.placeholder = 'Search torrents, library, or paste a magnet link'; });
browseSearch.addEventListener('blur',()=>{ browseSearch.placeholder = 'Search'; });
browseSearch.addEventListener('keydown',e=>{ if (e.key === 'Escape') browseSearch.blur(); });
document.getElementById('serverHome').addEventListener('click',e=>{
  const view = e.target.closest('[data-home-view]');
  if (view) setServerView(view.dataset.homeView);
  const featured = e.target.closest('[data-featured]');
  if (featured) { homeFeaturedIndex = Number(featured.dataset.featured); renderHomeHero(); }
});
document.getElementById('homeServerSettings').addEventListener('click',async()=>{
  await openSettings();
  switchSettingsTab('server');
});
document.addEventListener('visibilitychange',()=>{ if (!document.hidden) loadServerHistory(); });
