// Shared library and history, presented like the Apple clients. Download
// controls remain in the existing Discover, search and Downloads screens.
let serverHistory = [], homeFeaturedIndex = 0, homeRenderKey = "", homeHeroRequest = 0;
let homeLibraryError = '';
const homeMetadata = new Map();
const catalogFeeds = new Map(), catalogRequests = new Map(), catalogEnriched = new Set(), catalogErrors = new Map();
const CATALOG_SECTIONS = [['new','New releases'],['popular','Popular'],['movies','Movies'],['tv','TV Shows'],['cartoons','Cartoons']];
let catalogLoaded = false, catalogError = '', catalogPage = 0, catalogLoading = false, catalogUpdatedAt = 0;

function updateServerNavigation(view) {
  const navigationView = view === 'favorites' ? 'library' : view;
  document.querySelectorAll('#serverNavigation [data-view]').forEach(button => {
    if (button.dataset.view === navigationView) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  });
}

function setServerView(view) {
  closeSearchDropdown();
  if (detailsState || personState) closeDetails();
  if (view === 'discover') view = 'home';
  if (view === 'favorites') { librarySection = 'favorites'; view = 'library'; }
  if (discoverMode) exitDiscover();
  document.body.dataset.serverView = view;
  updateServerNavigation(view);
  renderViewToggleBtn();
  renderLibrary();
  // The Library destination stays useful when the optional split-view
  // library setting was disabled or there are no titles yet.
  libraryPanel.hidden = view !== 'library';
  catalogPage = 0;
  renderCatalogPage();
  setHeaderSearch(false);
  window.scrollTo({top:0});
}

function catalogFeedForView(view) { return {movie:'movies',tv:'tv',cartoon:'cartoons'}[view]; }

function catalogEntries(feed) {
  const groups = new Map();
  for (const row of catalogFeeds.get(feed) || []) {
    const kind = feed === 'tv' ? 'tv' : feed === 'cartoons' ? 'cartoon'
      : /cartoon|animation|мульт/i.test(row.suggested_category || '') ? 'cartoon'
      : /\bS\d+E?\d*|season|сезон/i.test(row.title || '') || /tv|series|серіал/i.test(row.suggested_category || '') ? 'tv' : 'movie';
    const title = row.clean_title || roughTitle(row.title);
    const key = `${kind}:${plainText(title)}`;
    const known = groups.get(key);
    if (known) { known.releases.push(row); continue; }
    groups.set(key,{...row,id:row.download_link || row.magnet || row.details_link || row.title,
      display_title:title,kind,media_type:kind === 'tv' ? 'tv' : 'movie',releases:[row]});
  }
  return [...groups.values()];
}

async function loadCatalogFeed(feed) {
  if (catalogRequests.has(feed)) return catalogRequests.get(feed);
  const request = (async()=>{
    const response = await fetch(`/api/discover?feed=${encodeURIComponent(feed)}`);
    const data = await response.json();
    if (!response.ok || data.error) throw new Error(data.error || 'Could not load the torrent catalog');
    catalogFeeds.set(feed,data.results || []);
    return data.results || [];
  })();
  catalogRequests.set(feed,request);
  try { const rows = await request; catalogErrors.delete(feed); return rows; }
  catch (e) { catalogRequests.delete(feed); catalogErrors.set(feed,'Could not load the torrent catalog. Check Search in Settings.'); throw e; }
}

async function loadServerCatalog(refresh = false) {
  if (catalogLoading) return;
  catalogLoading = true;
  if (refresh) catalogRequests.clear();
  catalogError = '';
  const results = await Promise.allSettled(CATALOG_SECTIONS.map(([feed])=>loadCatalogFeed(feed)));
  catalogLoaded = true;
  catalogLoading = false;
  catalogUpdatedAt = Date.now();
  if (results.every(r=>r.status === 'rejected')) catalogError = 'Could not load the torrent catalog. Check Search in Settings.';
  renderServerHome(); renderCatalogPage();
  enrichCatalogItems(CATALOG_SECTIONS.flatMap(([feed])=>catalogEntries(feed).slice(0,20)));
}

async function enrichCatalogItems(items) {
  const titles = [...new Set(items.flatMap(i=>i.releases || [i]).map(i=>i.title))].filter(t=>!catalogEnriched.has(t));
  if (!titles.length) return;
  titles.forEach(t=>catalogEnriched.add(t));
  for (let start=0;start<titles.length;start+=64) {
    const batch = titles.slice(start,start+64);
    try {
      const response = await fetch('/api/discover/enrich',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({titles:batch})});
      if (!response.ok) throw new Error('Metadata unavailable');
      const metadata = await response.json();
      for (const rows of catalogFeeds.values()) for (const row of rows) if (metadata[row.title]) Object.assign(row,metadata[row.title]);
      renderServerHome(); renderCatalogPage();
    } catch (e) { batch.forEach(t=>catalogEnriched.delete(t)); }
  }
}

function buildCatalogCard(item) {
  const card = document.createElement('button');
  card.type = 'button'; card.className = 'lib-card catalog-card';
  card.innerHTML = `<div class="lib-poster">${item.poster ? `<img src="${escapeHtml(item.poster.replace('/w200/','/w342/'))}" alt="" loading="lazy">` : brandArt(libraryTitle(item))}</div><div class="lib-title" data-no-i18n>${escapeHtml(libraryTitle(item))}</div><div class="lib-sub">${item.rating ? `★ ${item.rating.toFixed(1)} · ` : ''}${escapeHtml(item.size_label || '')}</div>`;
  card.onclick = ()=>openDetails(item);
  return card;
}

function renderCatalogPage() {
  const feed = catalogFeedForView(document.body.dataset.serverView), panel = document.getElementById('cataloguePanel');
  panel.hidden = !feed;
  if (!feed) return;
  const items = catalogEntries(feed), size = 36;
  catalogPage = Math.min(catalogPage,Math.max(0,Math.ceil(items.length/size)-1));
  document.getElementById('catalogueTitle').textContent = CATALOG_SECTIONS.find(([id])=>id === feed)[1];
  document.getElementById('catalogueCount').textContent = `${items.length} titles`;
  const grid = document.getElementById('catalogueGrid'); grid.replaceChildren();
  const visible = items.slice(catalogPage*size,(catalogPage+1)*size);
  visible.forEach(item=>grid.appendChild(buildCatalogCard(item)));
  if (!visible.length) grid.innerHTML = `<div class="library-empty" role="status">${catalogErrors.get(feed) || catalogError || (catalogLoaded ? 'Nothing here right now.' : 'Loading…')}</div>`;
  const pagination = document.getElementById('cataloguePagination');
  pagination.innerHTML = items.length > size ? `<button type="button" class="btn-secondary" data-catalog-page="-1"${catalogPage ? '' : ' disabled'}>Prev</button><span>Page ${catalogPage+1} of ${Math.ceil(items.length/size)}</span><button type="button" class="btn-secondary" data-catalog-page="1"${(catalogPage+1)*size >= items.length ? ' disabled' : ''}>Next</button>` : '';
  enrichCatalogItems(visible);
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
  const items = featuredLibraryItems(catalogEntries('new').concat(catalogEntries('movies').slice(0,2),catalogEntries('tv').slice(0,2),catalogEntries('cartoons').slice(0,2)));
  if (!items.length) {
    if (!catalogLoaded || catalogError) {
      hero.innerHTML = `<div class="home-loading" role="status">${catalogError ? `${escapeHtml(catalogError)} <button type="button" class="btn-secondary" id="homeLibraryRetry">Try again</button>` : 'Loading the torrent catalog…'}</div>`;
      const retry = document.getElementById('homeLibraryRetry');
      if (retry) retry.onclick = () => loadServerCatalog();
      return;
    }
    hero.innerHTML = `<div class="home-hero-copy home-empty"><span class="home-eyebrow">Your server</span><h2>Your next watch starts here</h2><p>Your library, favorites and viewing history in one place. Search for a title or add a torrent to grow your library.</p><div class="home-hero-actions"><button type="button" class="btn-primary btn-pill" data-home-search>Search</button><button type="button" class="btn-secondary" data-home-view="downloads">Downloads</button></div></div>`;
    return;
  }
  homeFeaturedIndex %= items.length;
  const item = items[homeFeaturedIndex], data = homeMetadata.get(item.id) || item;
  const title = libraryTitle(item), art = data.backdrop || data.banner;
  hero.innerHTML = `${art ? `<img class="home-hero-art" src="${escapeHtml(art)}" alt="">` : `<div class="home-hero-placeholder">${brandArt(title, true)}</div>`}
    <div class="home-hero-shade"></div><div class="home-hero-copy"><span class="home-eyebrow">New releases</span>
    <h2 data-no-i18n>${escapeHtml(title)}</h2><div class="home-hero-meta"><span>${{movie:'Movie',tv:'TV show',cartoon:'Cartoon'}[item.kind] || 'Movie'}</span>${data.year || item.year ? `<span>${escapeHtml(String(data.year || item.year))}</span>` : ''}${item.rating ? `<span class="home-rating">★ ${item.rating.toFixed(1)}</span>` : ''}${item.seasons ? `<span>${item.seasons} seasons</span>` : ''}</div>
    <p data-no-i18n>${escapeHtml(data.overview || item.overview || '')}</p>
    <div class="home-hero-actions"><button type="button" class="btn-primary btn-pill" id="homeHeroPlay">${ICONS.play}Watch</button><button type="button" class="btn-secondary" id="homeHeroDetails">Details</button><button type="button" class="btn-secondary home-hero-favorite" id="homeHeroFavorite" aria-pressed="${isFavorite(item.id)}" aria-label="${isFavorite(item.id) ? 'Remove from Favorites' : 'Add to Favorites'}">${isFavorite(item.id) ? ICONS.heartFilled : ICONS.heart}</button></div></div>
    <div class="home-hero-pages" role="group" aria-label="Featured titles">${items.map((i,n)=>`<button type="button" data-featured="${n}" aria-label="${escapeHtml(libraryTitle(i))}" aria-pressed="${n === homeFeaturedIndex}"></button>`).join('')}</div>`;
  document.getElementById('homeHeroDetails').onclick = () => openDetails(item);
  document.getElementById('homeHeroPlay').onclick = () => {
    openDetails(item);
    if (!detailsState.library && (item.magnet || item.download_link)) playRelease(item);
  };
  document.getElementById('homeHeroFavorite').onclick = () => toggleFavorite({library:null,item,data:{tmdb_id:item.tmdb_id,media_type:item.media_type,title}});
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
  shelf.innerHTML = `<div class="home-shelf-heading"><h2>${title}</h2>${view ? `<button type="button" class="home-see-all" data-home-view="${view}">See all ${CHEVRON_DOWN}</button>` : ''}</div><div class="home-shelf-track"></div>`;
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

function buildHomeLibraryCard(item) {
  const card = document.createElement('button');
  card.type = 'button'; card.className = 'lib-card catalog-card';
  const poster = item.poster ? `<img src="${escapeHtml(item.poster.replace('/w200/','/w342/'))}" alt="" loading="lazy">` : brandArt(libraryTitle(item));
  const sub = [item.year, item.rating > 0 ? `★ ${item.rating.toFixed(1)}` : ''].filter(Boolean).join(' · ');
  card.innerHTML = `<div class="lib-poster">${poster}</div><div class="lib-title" data-no-i18n>${escapeHtml(libraryTitle(item))}</div>${sub ? `<div class="lib-sub">${escapeHtml(sub)}</div>` : ''}`;
  card.onclick = () => {
    if (typeof openLibraryTitle === 'function') openLibraryTitle(item);
    else openDetails(item);
  };
  return card;
}

function renderServerHome() {
  const libItems = typeof libraryItems !== 'undefined' ? libraryItems : [];
  const key = JSON.stringify([catalogLoaded,catalogError,[...catalogFeeds],favorites,serverHistory,libItems.length,libItems[0]?.id]);
  if (key === homeRenderKey) return;
  homeRenderKey = key;
  renderHomeHero();
  const root = document.getElementById('homeShelves');
  root.replaceChildren();
  appendHomeShelf(root,'Continue Watching',null,serverHistory,buildContinueCard);
  for (const [feed,label] of CATALOG_SECTIONS) appendHomeShelf(root,label,{movies:'movie',tv:'tv',cartoons:'cartoon'}[feed] || null,catalogEntries(feed),buildCatalogCard);
  if (libItems.length) {
    appendHomeShelf(root,'New on your server','library',libItems,buildHomeLibraryCard);
  }
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

function closeServerNavigation() {
  const nav = document.getElementById('serverNavigation');
  const toggle = document.getElementById('navToggleBtn');
  if (nav?.classList) nav.classList.remove('is-open');
  if (toggle?.setAttribute) toggle.setAttribute('aria-expanded', 'false');
}

document.getElementById('navToggleBtn').addEventListener('click',e=>{
  const nav = document.getElementById('serverNavigation');
  const toggle = e.currentTarget;
  const open = nav.classList.toggle('is-open');
  toggle.setAttribute('aria-expanded', String(open));
});
document.getElementById('serverNavigation').addEventListener('click',e=>{
  const button = e.target.closest('[data-view]');
  if (button) {
    closeServerNavigation();
    setServerView(button.dataset.view);
  }
});
document.addEventListener('click',e=>{
  if (!e.target?.closest) return;
  if (!e.target.closest('#serverNavigation') && !e.target.closest('#navToggleBtn')) closeServerNavigation();
});
document.addEventListener('keydown',e=>{
  if (e.key === 'Escape') closeServerNavigation();
});
const browseSearch = document.getElementById('mainInput');
function searchPlaceholderForScreen(expanded = false) {
  const isMobile = typeof window !== 'undefined' && typeof window.innerWidth === 'number' ? window.innerWidth <= 640 : false;
  const isUk = typeof document !== 'undefined' && document.documentElement ? document.documentElement.lang === 'uk' : false;
  if (isMobile) return isUk ? 'Пошук' : 'Search';
  if (!expanded) return isUk ? 'Пошук' : 'Search';
  return isUk ? 'Пошук у бібліотеці й торентах або magnet' : 'Search torrents, library, or paste a magnet link';
}

function setHeaderSearch(open) {
  document.querySelector('.top-bar').classList.toggle('header-search-open',open);
  const button = document.getElementById('searchToggleBtn');
  button.setAttribute('aria-expanded',String(open));
  button.setAttribute('aria-label',open ? 'Close search' : 'Search');
  button.title = open ? 'Close search' : 'Search';
  button.innerHTML = open ? '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="m6 6 12 12M18 6 6 18"/></svg>' : '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4-4"/></svg>';
  if (open) {
    closeServerNavigation();
    browseSearch.placeholder = searchPlaceholderForScreen(true);
    browseSearch.focus();
  } else {
    browseSearch.blur();
    closeSearchDropdown();
  }
}
document.getElementById('searchToggleBtn').addEventListener('click',()=>setHeaderSearch(!document.querySelector('.top-bar').classList.contains('header-search-open')));
browseSearch.addEventListener('focus',()=>{ closeServerNavigation(); browseSearch.placeholder = searchPlaceholderForScreen(true); });
browseSearch.addEventListener('blur',()=>{ browseSearch.placeholder = searchPlaceholderForScreen(false); });
browseSearch.addEventListener('keydown',e=>{ if (e.key === 'Escape') { setHeaderSearch(false); document.getElementById('searchToggleBtn').focus(); } });
document.getElementById('serverHome').addEventListener('click',e=>{
  if (e.target.closest('[data-home-search]')) setHeaderSearch(true);
  const view = e.target.closest('[data-home-view]');
  if (view) setServerView(view.dataset.homeView);
  const featured = e.target.closest('[data-featured]');
  if (featured) { homeFeaturedIndex = Number(featured.dataset.featured); renderHomeHero(); }
});
document.addEventListener('visibilitychange',()=>{ if (!document.hidden) loadServerHistory(); });
document.getElementById('cataloguePagination').addEventListener('click',e=>{
  const button = e.target.closest('[data-catalog-page]');
  if (button) { catalogPage += Number(button.dataset.catalogPage); renderCatalogPage(); window.scrollTo({top:0}); }
});
