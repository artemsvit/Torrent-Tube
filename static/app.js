// Torrent Tube web page - the script of templates/index.html (loaded at the
// end of <body>, so the page's elements exist when it runs).
// Every icon carries explicit width/height on the <svg> itself (not just a
// CSS rule) - some places inject these with no sizing class around them
// (e.g. the "Added" state below), and without an attribute fallback,
// browsers size an unconstrained inline SVG at its native/default size,
// which can render enormous and misplaced (seen in Safari).
const ICONS = {
  download: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="M6 11l6 6 6-6"/><path d="M5 21h14"/></svg>`,
  heart: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20.5s-7.5-4.6-9.3-9.2C1.5 8 3.6 4.5 7.2 4.5c2 0 3.6 1.1 4.8 2.8 1.2-1.7 2.8-2.8 4.8-2.8 3.6 0 5.7 3.5 4.5 6.8-1.8 4.6-9.3 9.2-9.3 9.2z"/></svg>`,
  heartFilled: `<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 20.5s-7.5-4.6-9.3-9.2C1.5 8 3.6 4.5 7.2 4.5c2 0 3.6 1.1 4.8 2.8 1.2-1.7 2.8-2.8 4.8-2.8 3.6 0 5.7 3.5 4.5 6.8-1.8 4.6-9.3 9.2-9.3 9.2z"/></svg>`,
  check: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>`,
  pause: `<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>`,
  play: `<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7-11-7z"/></svg>`,
  trash: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16"/><path d="M10 11v6M14 11v6"/><path d="M6 7l1 13a1 1 0 001 1h8a1 1 0 001-1l1-13"/><path d="M9 7V4a1 1 0 011-1h4a1 1 0 011 1v3"/></svg>`,
  peers: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="8" r="3"/><path d="M2 20c0-3.3 3.1-6 7-6s7 2.7 7 6"/><circle cx="17" cy="9" r="2.5"/><path d="M15.5 14.2c2.6.5 4.5 2.5 4.5 5.8"/></svg>`,
  down: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v13"/><path d="M6 12l6 6 6-6"/></svg>`,
  up: `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V6"/><path d="M6 12l6-6 6 6"/></svg>`,
  star: `<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.9 6.6 7.1.6-5.4 4.7 1.6 7-6.2-3.9-6.2 3.9 1.6-7-5.4-4.7 7.1-.6z"/></svg>`,
};

const mainInput = document.getElementById("mainInput");
const clearMainInputBtn = document.getElementById("clearMainInput");
const goBtn = document.getElementById("goBtn");
const goBtnIcon = document.getElementById("goBtnIcon");
const goBtnLabel = document.getElementById("goBtnLabel");
const uploadBtn = document.getElementById("uploadBtn");
const fileInput = document.getElementById("fileInput");
const listEl = document.getElementById("list");
const listEmptyEl = document.getElementById("listEmpty");
const clearAllBtn = document.getElementById("clearAllBtn");
const countEl = document.getElementById("count");
const toastStack = document.getElementById("toastStack");
const themeToggleBtn = document.getElementById("themeToggle");
const dropZone = document.getElementById("dropZone");
const searchDropdown = document.getElementById("searchDropdown");

const downloadsTab = document.getElementById("downloadsTab");
const streamsPanel = document.getElementById("streamsPanel");
const streamsList = document.getElementById("streamsList");
const streamsCount = document.getElementById("streamsCount");
const downloadsHeader = document.getElementById("downloadsHeader");
const discoverHeader = document.getElementById("discoverHeader");
const discoverTabs = document.getElementById("discoverTabs");
const discoverTabsSelect = document.getElementById("discoverTabsSelect");
const discoverList = document.getElementById("discoverList");
const discoverPagination = document.getElementById("discoverPagination");
const discoverPrevBtn = document.getElementById("discoverPrevBtn");
const discoverPageInfo = document.getElementById("discoverPageInfo");
const discoverNextBtn = document.getElementById("discoverNextBtn");
const topBarEl = document.querySelector(".top-bar");

const uploadModal = document.getElementById("uploadModal");
const uploadModalPoster = document.getElementById("uploadModalPoster");
const uploadModalFilename = document.getElementById("uploadModalFilename");
const uploadModalSub = document.getElementById("uploadModalSub");
const uploadModalCategory = document.getElementById("uploadModalCategory");
const uploadModalCancel = document.getElementById("uploadModalCancel");
const uploadModalConfirm = document.getElementById("uploadModalConfirm");
let pendingFile = null;

const confirmModal = document.getElementById("confirmModal");
const confirmModalTitle = document.getElementById("confirmModalTitle");
const confirmModalText = document.getElementById("confirmModalText");
const confirmModalCancel = document.getElementById("confirmModalCancel");
const confirmModalOk = document.getElementById("confirmModalOk");
const confirmModalCheckRow = document.getElementById("confirmModalCheckRow");
const confirmModalCheck = document.getElementById("confirmModalCheck");
const confirmModalCheckLabel = document.getElementById("confirmModalCheckLabel");
let confirmResolve = null;

// Promise-based stand-in for the native confirm() - same centered overlay
// as every other modal in this app instead of the browser's own styling.
// `check` adds a checkbox (read confirmModalCheck.checked after OK);
// `onCheck` lets the caller restyle the dialog as it's ticked.
function showConfirm({ title, text, confirmLabel = "OK", danger = false, check = null, checked = false, onCheck = null }) {
  confirmModalCheckRow.hidden = !check;
  confirmModalCheckLabel.textContent = check || "";
  confirmModalCheck.checked = !!checked;
  confirmModalCheck.onchange = onCheck ? () => onCheck(confirmModalCheck.checked) : null;
  confirmModalTitle.textContent = title;
  confirmModalText.textContent = text || "";
  confirmModalText.style.display = text ? "" : "none";
  confirmModalOk.textContent = confirmLabel;
  confirmModalOk.classList.toggle("is-danger", danger);
  confirmModal.classList.add("is-open");
  return new Promise(resolve => { confirmResolve = resolve; });
}
function closeConfirm(result) {
  confirmModal.classList.remove("is-open");
  if (confirmResolve) { confirmResolve(result); confirmResolve = null; }
}
confirmModalCancel.addEventListener("click", () => closeConfirm(false));
confirmModalOk.addEventListener("click", () => closeConfirm(true));
confirmModal.addEventListener("click", e => { if (e.target === confirmModal) closeConfirm(false); });

const settingsBtn = document.getElementById("settingsBtn");
const settingsModal = document.getElementById("settingsModal");
const settingsTabs = document.getElementById("settingsTabs");
const settingsSave = document.getElementById("settingsSave");
const settingsReset = document.getElementById("settingsReset");
const settingsDefaultCategory = document.getElementById("settingsDefaultCategory");
const settingsPlayer = document.getElementById("settingsPlayer");
const settingsDownloadDir = document.getElementById("settingsDownloadDir");
const settingsCategories = document.getElementById("settingsCategories");
const settingsSearch = document.getElementById("settingsSearch");
const settingsTmdb = document.getElementById("settingsTmdb");
const settingsJackettUrl = document.getElementById("settingsJackettUrl");
const settingsJackettApiKey = document.getElementById("settingsJackettApiKey");
const settingsJackettIndexer = document.getElementById("settingsJackettIndexer");
const settingsTmdbApiKey = document.getElementById("settingsTmdbApiKey");
const settingsTmdbLanguage = document.getElementById("settingsTmdbLanguage");
const settingsDownloadLimit = document.getElementById("settingsDownloadLimit");
const settingsDownloadLimitValue = document.getElementById("settingsDownloadLimitValue");
const settingsUploadLimit = document.getElementById("settingsUploadLimit");
const settingsUploadLimitValue = document.getElementById("settingsUploadLimitValue");
const settingsSeedAfterDownload = document.getElementById("settingsSeedAfterDownload");
const settingsRemoveAfterDownload = document.getElementById("settingsRemoveAfterDownload");
const settingsMaxConnections = document.getElementById("settingsMaxConnections");
const settingsMaxConnectionsValue = document.getElementById("settingsMaxConnectionsValue");
const settingsMaxConnectionsPerTorrent = document.getElementById("settingsMaxConnectionsPerTorrent");
const settingsMaxConnectionsPerTorrentValue = document.getElementById("settingsMaxConnectionsPerTorrentValue");
const settingsMaxUploadSlots = document.getElementById("settingsMaxUploadSlots");
const settingsMaxUploadSlotsValue = document.getElementById("settingsMaxUploadSlotsValue");

let searchEnabled = false;
let currentCategories = [];
let lastConfig = {};
let lastLimits = {};

let dragCounter = 0;

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str || "";
  return div.innerHTML;
}

function formatBytes(n) {
  if (!n || n <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.min(units.length - 1, Math.floor(Math.log(n) / Math.log(1024)));
  return `${(n / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

function formatRate(n) {
  return n > 0 ? `${formatBytes(n)}/s` : "";
}

function formatEta(secs) {
  if (secs === null || secs === undefined) return "";
  if (secs < 60) return `${secs}s left`;
  if (secs < 3600) return `${Math.round(secs / 60)}m left`;
  if (secs < 86400) return `${Math.round(secs / 3600)}h left`;
  return `${Math.round(secs / 86400)}d left`;
}

// ---------- Theme ----------

themeToggleBtn.addEventListener("click", () => {
  const current = document.documentElement.getAttribute("data-theme");
  const next = current === "dark" ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", next);
  try { localStorage.setItem("torrenttube-theme", next); } catch (e) {}
});

// ---------- Toasts ----------

const TOAST_ICONS = {
  ok: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>`,
  error: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><path d="M12 6v8"/><path d="M12 18.5v.01"/></svg>`,
};

function showToast(message, isError) {
  const el = document.createElement("div");
  el.className = "toast" + (isError ? " is-error" : "");
  el.setAttribute("role", isError ? "alert" : "status");
  el.innerHTML = `<span class="toast-icon">${TOAST_ICONS[isError ? "error" : "ok"]}</span><span class="toast-text"></span>`;
  el.querySelector(".toast-text").textContent = message;
  const dismiss = () => {
    if (el.classList.contains("is-leaving")) return;
    el.classList.add("is-leaving");
    setTimeout(() => el.remove(), 200);
  };
  el.addEventListener("click", dismiss);
  toastStack.appendChild(el);
  // Long enough to read: about 60ms a character, at least 3.5s (6s for errors).
  setTimeout(dismiss, Math.max(isError ? 6000 : 3500, message.length * 60));
}

// ---------- Adding torrents ----------

function closeSearchDropdown() {
  searchDropdown.classList.remove("is-open");
}

function getDefaultCategory() {
  let remembered = null;
  try { remembered = localStorage.getItem("torrenttube-category"); } catch (e) {}
  if (remembered && currentCategories.includes(remembered)) return remembered;
  return currentCategories[0] || "";
}

function rememberCategory(category) {
  try { localStorage.setItem("torrenttube-category", category); } catch (e) {}
}

async function addMagnet(magnet) {
  const category = getDefaultCategory();
  const res = await fetch("/api/torrents", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ magnet, category })
  });
  const data = await res.json();
  if (data.error) { showToast(data.error, true); return; }
  rememberCategory(category);
  mainInput.value = "";
  updateGoLabel();
  closeSearchDropdown();
  refresh();
}

async function addFile(file, category) {
  const form = new FormData();
  form.append("file", file);
  form.append("category", category);
  const res = await fetch("/api/torrents", { method: "POST", body: form });
  const data = await res.json();
  if (data.error) { showToast(data.error, true); return; }
  rememberCategory(category);
  refresh();
}

function isMagnet(value) {
  return value.toLowerCase().startsWith("magnet:?");
}

function updateGoLabel() {
  const magnet = isMagnet(mainInput.value.trim());
  goBtnLabel.textContent = magnet ? "Add" : "Search";
  goBtn.setAttribute('aria-label', magnet ? 'Add' : 'Search');
  goBtnIcon.innerHTML = magnet ? ICONS.download : `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>`;
  clearMainInputBtn.classList.toggle("is-visible", mainInput.value.length > 0);
}

function handleGo() {
  const value = mainInput.value.trim();
  if (!value) return;
  if (isMagnet(value)) {
    addMagnet(value);
  } else {
    if (!searchEnabled) {
      showToast("Search isn't set up on this server yet", true);
      return;
    }
    runSearch(value);
  }
}

document.addEventListener("click", (e) => {
  // A details popup opened from a search result sits outside .searchbar -
  // clicking around in it shouldn't close the results underneath.
  if (e.target.closest("#searchCloseBtn")) { closeSearchDropdown(); window.scrollTo({ top: 0 }); }
});
document.addEventListener("keydown", (e) => {
  if (e.key !== "Escape") return;
  // One layer at a time: Escape in a popup opened from search results
  // closes just the popup, not the results list too.
  if (getAppModal.classList.contains("is-open")) { closeGetApp(); return; }
  if (helperModal.classList.contains("is-open")) { closeVlcHelper(); return; }
  if (playerModal.classList.contains("is-open")) { closePlayerPicker(); return; }
  if (settingsModal.classList.contains("is-open")) { closeSettings(); return; }
  if (uploadModal.classList.contains("is-open")) { closeUploadModal(); return; }
  if (confirmModal.classList.contains("is-open")) { closeConfirm(false); return; }
  if (detailsModal.classList.contains("is-open")) { detailsGoBack(); return; }
  closeSearchDropdown(); closeUploadModal(); closeSettings(); closeConfirm(false);
});

goBtn.addEventListener("click", handleGo);
mainInput.addEventListener("input", updateGoLabel);
mainInput.addEventListener("keydown", e => { if (e.key === "Enter") handleGo(); });
clearMainInputBtn.addEventListener("click", () => {
  mainInput.value = "";
  updateGoLabel();
  closeSearchDropdown();
  mainInput.focus();
});
updateGoLabel();

// ---------- Upload modal (used for both the + button and drag & drop) ----------

async function openUploadModal(file) {
  pendingFile = file;
  uploadModalFilename.textContent = file.name;
  uploadModalPoster.innerHTML = `<div class="result-poster-fallback">${ICONS.download}</div>`;
  uploadModalSub.innerHTML = "";
  uploadModalCategory.innerHTML = currentCategories.map(c => `<option value="${escapeHtml(c)}">${escapeHtml(c)}</option>`).join("");
  uploadModalCategory.value = getDefaultCategory();
  uploadModal.classList.add("is-open");

  // Peek at the torrent's own internal name (more reliable than the OS
  // filename) and, when TMDB is configured, fetch a poster/rating/overview -
  // same enrichment the search results get - to suggest a better folder than
  // "whatever was used last" and give the user something to recognize it by.
  try {
    const form = new FormData();
    form.append("file", file);
    const res = await fetch("/api/torrents/inspect", { method: "POST", body: form });
    const data = await res.json();
    if (pendingFile !== file) return; // superseded by a different file

    if (data.suggested_category && currentCategories.includes(data.suggested_category)) {
      uploadModalCategory.value = data.suggested_category;
    }
    uploadModalFilename.textContent = data.clean_title || data.name || file.name;
    uploadModalPoster.innerHTML = data.poster
      ? `<img class="result-poster" src="${escapeHtml(data.poster)}" alt="" loading="lazy">`
      : `<div class="result-poster-fallback">${ICONS.download}</div>`;
    const rating = (data.rating && data.rating > 0) ? `<span class="rating-badge">${ICONS.star}${data.rating.toFixed(1)}</span>` : "";
    uploadModalSub.innerHTML = (rating ? `<div>${rating}</div>` : "") +
      (data.overview ? `<div class="item-overview">${escapeHtml(data.overview)}</div>` : "");
  } catch (e) {
    // Keep the fallback preview; not worth failing the modal over.
  }
}

function closeUploadModal() {
  uploadModal.classList.remove("is-open");
  pendingFile = null;
  fileInput.value = "";
}

uploadBtn.addEventListener("click", () => fileInput.click());
fileInput.addEventListener("change", () => {
  if (fileInput.files[0]) openUploadModal(fileInput.files[0]);
});
uploadModalCancel.addEventListener("click", closeUploadModal);
uploadModal.addEventListener("click", e => { if (e.target === uploadModal) closeUploadModal(); });
uploadModalConfirm.addEventListener("click", () => {
  if (!pendingFile) return;
  addFile(pendingFile, uploadModalCategory.value);
  closeUploadModal();
});

// ---------- Drag & drop anywhere on the page ----------

window.addEventListener("dragenter", e => {
  if (!e.dataTransfer || !Array.from(e.dataTransfer.types || []).includes("Files")) return;
  e.preventDefault();
  dragCounter++;
  dropZone.classList.add("is-active");
});
window.addEventListener("dragover", e => {
  if (!e.dataTransfer || !Array.from(e.dataTransfer.types || []).includes("Files")) return;
  e.preventDefault();
});
window.addEventListener("dragleave", () => {
  dragCounter = Math.max(0, dragCounter - 1);
  if (dragCounter === 0) dropZone.classList.remove("is-active");
});
window.addEventListener("drop", e => {
  e.preventDefault();
  dragCounter = 0;
  dropZone.classList.remove("is-active");
  const file = e.dataTransfer.files && e.dataTransfer.files[0];
  if (file) openUploadModal(file);
});

// ---------- Actions ----------

async function pauseTorrent(id) {
  await fetch(`/api/torrents/${id}/pause`, { method: "POST" });
  refresh();
}
async function resumeTorrent(id) {
  await fetch(`/api/torrents/${id}/resume`, { method: "POST" });
  refresh();
}
// A checkbox, not only Shift+click, so files can be deleted from a phone.
async function removeTorrent(id, deleteFiles) {
  const look = (del) => {
    confirmModalTitle.textContent = del ? "Remove torrent and delete its files?" : "Remove torrent from the list?";
    confirmModalText.textContent = del ? "The downloaded files will be permanently deleted." : "The downloaded files are kept on disk.";
    confirmModalOk.textContent = del ? "Delete" : "Remove";
    confirmModalOk.classList.toggle("is-danger", del);
  };
  const shown = showConfirm({ title: "", text: " ", check: "Also delete the downloaded files", checked: deleteFiles, onCheck: look });
  look(deleteFiles);
  const ok = await shown;
  if (!ok) return;
  deleteFiles = confirmModalCheck.checked;
  await fetch(`/api/torrents/${id}?delete_files=${deleteFiles ? "1" : "0"}`, { method: "DELETE" });
  refresh();
}

async function clearAllTorrents() {
  if (!currentTorrents.length) return;
  const ok = await showConfirm({
    title: "Clear all downloads?",
    text: `Removes all ${currentTorrents.length} item${currentTorrents.length === 1 ? "" : "s"} from this list. The downloaded files are kept on disk.`,
    confirmLabel: "Clear all",
    danger: true,
  });
  if (!ok) return;
  await Promise.all(currentTorrents.map(t => fetch(`/api/torrents/${t.id}?delete_files=0`, { method: "DELETE" })));
  refresh();
}

// ---------- Rendering ----------

const STATE_LABELS = {
  fetching_metadata: "Fetching metadata…",
  checking: "Checking files…",
  downloading: "Downloading",
  finished: "Finished",
  seeding: "Seeding",
};

// Not "Playing"/"Paused": a player reading ahead and one paused look the
// same from the server. It keeps downloading either way, and the stream
// goes when the player is closed.
function streamActivityText(st) {
  if (!st.opened) return "Waiting for the player";
  return st.connections ? "Open in the player" : "Player closed · stopped, deleting";
}

// A stream's row in the Buffering block - the one place it can be seen,
// saved or stopped once the popup is closed.
function renderStreamItem(st) {
  const div = document.createElement("div");
  div.className = "item is-stream";
  const sub = [`${st.progress}% buffered`, streamActivityText(st)].filter(Boolean).join(" · ");
  const stats = [];
  // Player closed: the download has stopped, so no speed (libtorrent's
  // average would take a while to fall to zero).
  const closed = st.opened && !st.connections;
  if (!closed && st.download_rate > 0) stats.push(`<span>${ICONS.down}${formatRate(st.download_rate)}</span>`);
  if (!closed && st.num_peers > 0) stats.push(`<span>${ICONS.peers}${st.num_peers} peers</span>`);
  div.innerHTML = `
    <div class="item-top">
      <div class="item-icon">${ICONS.play}</div>
      <div class="item-meta">
        <div class="item-title">${escapeHtml(st.name)}</div>
        <div class="item-sub">${escapeHtml(sub)}</div>
      </div>
      <div class="item-actions">
        ${st.cached ? `<button class="action-btn save-stream-btn" title="Save it as a download in your default folder" aria-label="Save as a download">${ICONS.download}</button>` : ""}
        <button class="action-btn danger stop-stream-btn" title="Stop and delete it now" aria-label="Stop and delete">${CLOSE_ICON}</button>
      </div>
    </div>
    <div class="progress-track"><div class="progress-fill" style="width:${st.progress}%"></div></div>
    ${stats.length ? `<div class="item-stats">${stats.join("")}</div>` : ""}`;
  div.querySelector(".stop-stream-btn").addEventListener("click", () => stopStreamById(st.id));
  const saveBtn = div.querySelector(".save-stream-btn");
  if (saveBtn) saveBtn.addEventListener("click", () => saveStream(st.id));
  return div;
}

// The Buffering block under Downloads - shown only while something plays,
// and not over Discover.
function renderStreams(streams) {
  // Only while something plays, and not over Discover.
  streamsPanel.hidden = discoverMode || !streams.length;
  streamsCount.textContent = streams.length;
  if (streams.length) streamsList.replaceChildren(...streams.map(renderStreamItem));
  else streamsList.innerHTML = `<div class="empty-state">Nothing is playing. Films you play in Infuse or VLC buffer here.</div>`;
}

function render(torrents) {
  countEl.textContent = torrents.length;
  listEmptyEl.style.display = torrents.length ? "none" : "block";
  listEl.querySelectorAll(".item").forEach(el => el.remove());

  torrents.forEach(t => {
    const div = document.createElement("div");
    const isDone = t.state === "finished" || t.state === "seeding";
    const isPaused = t.is_paused && !isDone;
    const isError = !!t.error;
    div.className = "item" + (isDone ? " is-done" : "") + (isPaused ? " is-paused" : "") + (isError ? " is-error" : "") + (t.state === "seeding" ? " is-seeding" : "");

    const stateLabel = isError ? "Error" : isPaused ? "Paused" : (STATE_LABELS[t.state] || t.state);
    const icon = isDone ? ICONS.check : (isPaused ? ICONS.pause : ICONS.download);

    const stats = [];
    if (t.category) stats.push(`<span class="category-badge">${escapeHtml(t.category)}</span>`);
    if (t.has_metadata) stats.push(`<span>${formatBytes(t.downloaded)} / ${formatBytes(t.size)}</span>`);
    if (!isDone && !isPaused && t.download_rate > 0) stats.push(`<span>${ICONS.down}${formatRate(t.download_rate)}</span>`);
    if (t.upload_rate > 0) stats.push(`<span>${ICONS.up}${formatRate(t.upload_rate)}</span>`);
    if (!isDone && !isPaused && t.num_peers > 0) stats.push(`<span>${ICONS.peers}${t.num_peers} peers</span>`);
    if (!isDone && !isPaused) {
      const eta = formatEta(t.eta);
      if (eta) stats.push(`<span>${eta}</span>`);
    }

    let actionsHtml = "";
    if (!isDone) {
      actionsHtml += isPaused
        ? `<button class="action-btn resume-btn" title="Resume">${ICONS.play}</button>`
        : `<button class="action-btn pause-btn" title="Pause">${ICONS.pause}</button>`;
    }
    actionsHtml += `<button class="action-btn danger remove-btn" title="Remove (or delete its files)">${ICONS.trash}</button>`;

    div.innerHTML = `
      <div class="item-top">
        <div class="item-icon">${icon}</div>
        <div class="item-meta">
          <div class="item-title">${escapeHtml(t.name)}</div>
          <div class="item-sub${isError ? " is-error-text" : ""}">${isError ? escapeHtml(t.error) : `${stateLabel}${t.has_metadata ? " · " + t.progress + "%" : ""}`}</div>
        </div>
        <div class="item-actions">${actionsHtml}</div>
      </div>
      ${t.has_metadata ? `<div class="progress-track"><div class="progress-fill" style="width:${t.progress}%"></div></div>` : ""}
      ${stats.length ? `<div class="item-stats">${stats.join("")}</div>` : ""}
    `;

    const pauseBtn = div.querySelector(".pause-btn");
    if (pauseBtn) pauseBtn.addEventListener("click", () => pauseTorrent(t.id));
    const resumeBtn = div.querySelector(".resume-btn");
    if (resumeBtn) resumeBtn.addEventListener("click", () => resumeTorrent(t.id));
    div.querySelector(".remove-btn").addEventListener("click", (e) => removeTorrent(t.id, e.shiftKey));
    if (t.has_metadata) {
      div.addEventListener("click", (e) => {
        if (!e.target.closest("button")) openDetails({ title: t.name }, t);
      });
    }

    listEl.appendChild(div);
  });
}

// "Remove when finished" takes a torrent off the list server-side - say so
// once per torrent rather than having its row just disappear.
const announcedRemovals = new Set();
function announceAutoRemoved(removed) {
  removed.forEach(r => {
    if (announcedRemovals.has(r.id)) return;
    announcedRemovals.add(r.id);
    showToast(`Downloaded: ${r.name}`);
  });
}

// One request at a time: a call while one runs asks for one more after it
// (so a pause/remove shows at once). An answer equal to the last one, on the
// same screen, changes nothing on the page - so no rows are rebuilt.
let refreshRunning = false, refreshAgain = false, lastRefreshKey = "";
async function refresh() {
  if (refreshRunning) { refreshAgain = true; return; }
  refreshRunning = true;
  try {
    await refreshOnce();
  } finally {
    refreshRunning = false;
    if (refreshAgain) { refreshAgain = false; refresh(); }
  }
}

async function refreshOnce() {
  try {
    const res = await fetch("/api/torrents");
    if (!res.ok) throw new Error('Could not reach the server');
    const body = await res.text();
    const key = `${discoverMode}|${body}`;
    if (key === lastRefreshKey) return;
    const data = JSON.parse(body);
    const torrents = data.torrents || [];
    currentStreams = data.streams || [];
    announceAutoRemoved(data.auto_removed || []);
    // The view-toggle button's badge reflects the download count regardless
    // of which screen is showing, so this keeps polling either way - only
    // the #list DOM itself is skipped while Discover has it hidden. Only
    // count active (not finished/seeding) downloads - a completed torrent
    // isn't something that still needs attention.
    currentTorrentCount = torrents.filter(t => t.state !== "finished" && t.state !== "seeding").length;
    renderViewToggleBtn();
    currentTorrents = torrents;
    clearAllBtn.disabled = torrents.length === 0;
    layoutEl.classList.toggle("downloads-empty", torrents.length === 0 && !currentStreams.length);
    layoutEl.classList.toggle("no-downloads", torrents.length === 0);
    if (!discoverMode) render(torrents);
    renderStreams(currentStreams);
    lastRefreshKey = key;  // only once it is on the page: a failed render tries again
  } catch (e) {
    // Transient network hiccup; the next poll will retry.
  }
}

// ---------- Discover ----------
// Discover keeps the torrent feeds and their download controls. The round
// shortcut opens Downloads from browsing, or Home from Downloads.

let currentTorrentCount = 0;
let currentTorrents = [];
let currentStreams = [];

const HOME_ICON = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-8H9v8H4a1 1 0 0 1-1-1z"/></svg>`;

function renderViewToggleBtn() {
  const badge = document.getElementById('navDownloadCount');
  badge.hidden = !currentTorrentCount;
  badge.textContent = currentTorrentCount;
}

let discoverMode = false;
let discoverEnabled = false;
let discoverFeeds = [];
let currentDiscoverFeed = null;
// The tracker's Jackett feed caps out around ~50-100 items and doesn't
// support real pagination (offset=20 just comes back empty) - there's no
// server-side "next page" to fetch. The whole feed is retrieved once and
// paged through client-side instead, which is also just more honest about
// it being a fixed, finite list rather than infinite scroll that
// mysteriously stops partway through.
let discoverAllResults = [];
let discoverPage = 0;
// Titles already sent to (or in flight to) /api/discover/enrich, so
// re-rendering a page already on screen doesn't re-request its metadata.
let discoverEnrichedTitles = new Set();
const DISCOVER_PAGE_SIZE = 16;

async function loadDiscoverFeeds() {
  try {
    const res = await fetch("/api/discover/feeds");
    const data = await res.json();
    discoverEnabled = !!data.enabled;
    discoverFeeds = data.feeds || [];
    if (discoverFeeds.length && !currentDiscoverFeed) currentDiscoverFeed = discoverFeeds[0].id;
  } catch (e) {}
}

function renderDiscoverTabs() {
  discoverTabs.innerHTML = discoverFeeds.map(f =>
    `<button type="button" class="discover-tab${f.id === currentDiscoverFeed ? " is-active" : ""}" data-feed="${escapeHtml(f.id)}">${escapeHtml(f.label)}</button>`
  ).join("");
  discoverTabsSelect.innerHTML = discoverFeeds.map(f =>
    `<option value="${escapeHtml(f.id)}"${f.id === currentDiscoverFeed ? " selected" : ""}>${escapeHtml(f.label)}</option>`
  ).join("");
}

function discoverTotalPages() {
  return Math.max(1, Math.ceil(discoverAllResults.length / DISCOVER_PAGE_SIZE));
}

function renderDiscoverPage() {
  const total = discoverTotalPages();
  discoverPage = Math.min(Math.max(0, discoverPage), total - 1);
  const start = discoverPage * DISCOVER_PAGE_SIZE;
  const slice = discoverAllResults.slice(start, start + DISCOVER_PAGE_SIZE);
  renderResultCards(discoverList, slice, "Nothing here right now.");
  discoverList.scrollTop = 0;

  discoverPageInfo.textContent = `Page ${discoverPage + 1} of ${total}`;
  discoverPrevBtn.disabled = discoverPage === 0;
  discoverNextBtn.disabled = discoverPage >= total - 1;
  discoverPagination.style.display = discoverAllResults.length > DISCOVER_PAGE_SIZE ? "flex" : "none";

  enrichDiscoverPage(slice);
}

// Posters/ratings/overviews for the whole feed aren't fetched up front -
// /api/discover returns fast with just what's needed to list and page
// through results. Only once a page is actually about to be shown does
// its handful of titles get sent off for the real TMDB lookup.
async function enrichDiscoverPage(items) {
  const need = items.filter(r => !discoverEnrichedTitles.has(r.title));
  if (!need.length) return;
  need.forEach(r => discoverEnrichedTitles.add(r.title));
  try {
    const res = await fetch("/api/discover/enrich", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ titles: need.map(r => r.title) }),
    });
    const data = await res.json();
    let changed = false;
    for (const r of discoverAllResults) {
      const meta = data[r.title];
      if (meta) {
        Object.assign(r, meta);
        changed = true;
      }
    }
    // Only the page still on screen needs a repaint - if the user has
    // already paged away, the next renderDiscoverPage() call picks up
    // these now-cached results anyway.
    if (changed) renderDiscoverPage();
  } catch (e) {
    // Cards just keep their placeholder icon; not worth a toast for this.
  }
}

async function loadDiscoverFeed(feedId) {
  currentDiscoverFeed = feedId;
  renderDiscoverTabs();
  discoverList.innerHTML = `<div class="empty-state" style="padding:24px;">Loading...</div>`;
  discoverPagination.style.display = "none";
  discoverAllResults = [];
  discoverPage = 0;
  discoverEnrichedTitles = new Set();
  try {
    const res = await fetch(`/api/discover?feed=${encodeURIComponent(feedId)}`);
    const data = await res.json();
    if (data.error) {
      discoverList.innerHTML = `<div class="empty-state" style="padding:24px;">${escapeHtml(data.error)}</div>`;
      return;
    }
    discoverAllResults = data.results || [];
    renderDiscoverPage();
  } catch (e) {
    discoverList.innerHTML = `<div class="empty-state" style="padding:24px;">Couldn't load this feed. Try again.</div>`;
  }
}

function enterDiscover() {
  if (!discoverEnabled) {
    showToast("Search isn't set up on this server yet", true);
    return;
  }
  discoverMode = true;
  document.body.dataset.serverView = "discover";
  updateServerNavigation("discover");
  renderViewToggleBtn();
  document.body.classList.add("discover-active");
  downloadsTab.classList.add("discover-mode");
  downloadsHeader.style.display = "none";
  discoverHeader.style.display = "flex";
  listEl.style.display = "none";
  clearAllBtn.style.display = "none";
  discoverList.classList.add("is-open");
  streamsPanel.hidden = true;
  loadDiscoverFeed(currentDiscoverFeed || (discoverFeeds[0] && discoverFeeds[0].id));
}

function exitDiscover() {
  discoverMode = false;
  document.body.dataset.serverView = "downloads";
  updateServerNavigation("downloads");
  renderViewToggleBtn();
  document.body.classList.remove("discover-active");
  downloadsTab.classList.remove("discover-mode");
  downloadsHeader.style.display = "";
  discoverHeader.style.display = "none";
  listEl.style.display = "";
  clearAllBtn.style.display = "";
  discoverList.classList.remove("is-open");
  discoverList.innerHTML = "";
  discoverPagination.style.display = "none";
  refresh();
}

clearAllBtn.addEventListener("click", clearAllTorrents);
discoverTabs.addEventListener("click", (e) => {
  const btn = e.target.closest(".discover-tab");
  if (btn && btn.dataset.feed !== currentDiscoverFeed) loadDiscoverFeed(btn.dataset.feed);
});
discoverTabsSelect.addEventListener("change", () => {
  if (discoverTabsSelect.value !== currentDiscoverFeed) loadDiscoverFeed(discoverTabsSelect.value);
});
discoverPrevBtn.addEventListener("click", () => { discoverPage--; renderDiscoverPage(); });
discoverNextBtn.addEventListener("click", () => { discoverPage++; renderDiscoverPage(); });

async function loadConfig() {
  try {
    const res = await fetch("/api/config");
    const data = await res.json();

    currentCategories = data.categories || [];
    searchEnabled = !!data.search_enabled;
    lastConfig = data;
    if (data.default_player) defaultPlayerId = data.default_player;
  } catch (e) {}
}

// ---------- Settings ----------

function renderSettings() {
  settingsDefaultCategory.innerHTML = currentCategories
    .map(c => `<option value="${escapeHtml(c)}">${escapeHtml(c)}</option>`)
    .join("");
  settingsDefaultCategory.value = getDefaultCategory();
  settingsPlayer.innerHTML = availablePlayers()
    .map(id => `<option value="${id}">${escapeHtml(PLAYERS[id].name)}</option>`)
    .join("");
  settingsPlayer.value = currentPlayer();

  // The server's real folder when known; the container's own path (e.g.
  // /downloads) says little, so it's only shown as a fallback, labelled.
  const hostDir = lastConfig.download_dir_host;
  settingsDownloadDir.textContent = hostDir || (lastConfig.download_dir ? `${lastConfig.download_dir} (inside the container)` : "—");
  settingsDownloadDir.title = hostDir && lastConfig.download_dir && hostDir !== lastConfig.download_dir
    ? `${lastConfig.download_dir} inside the container` : "";
  settingsCategories.innerHTML = currentCategories
    .map(c => `<span class="category-badge">${escapeHtml(c)}</span>`)
    .join("");

  settingsSearch.innerHTML = lastConfig.search_enabled
    ? `<span class="status-badge is-on">Enabled${lastConfig.search_indexer ? ` &middot; ${escapeHtml(lastConfig.search_indexer)}` : ""}</span>`
    : `<span class="status-badge is-off">Not configured</span>`;

  settingsTmdb.innerHTML = lastConfig.tmdb_enabled
    ? `<span class="status-badge is-on">Enabled${lastConfig.tmdb_language ? ` &middot; ${escapeHtml(lastConfig.tmdb_language)}` : ""}</span>`
    : `<span class="status-badge is-off">Not configured</span>`;

  renderLimits();
}

function formatSpeed(kbps) {
  kbps = Number(kbps) || 0;
  if (kbps <= 0) return "Unlimited";
  return kbps >= 1024 ? `${(kbps / 1024).toFixed(1)} MB/s` : `${kbps} KB/s`;
}

// The sliders don't move linearly through KB/s - a straight 0-100000 range
// would make anything under a few MB/s impossible to land on precisely, and
// a straight 0-5000 range would cap out well under what a fast connection
// can use. A cubic curve gives most of the slider's travel to the low end
// (where fine control actually matters for a home connection) while still
// reaching a 250 MB/s ceiling at the far right - comfortably past a full
// 1 Gbps line (~125 MB/s) with headroom for 2.5 GbE too.
const SPEED_SLIDER_MAX_KBPS = 256000; // 250 MB/s
function sliderToKbps(raw) {
  raw = Number(raw) || 0;
  if (raw <= 0) return 0;
  return Math.round(Math.pow(raw / 1000, 3) * SPEED_SLIDER_MAX_KBPS);
}
function kbpsToSlider(kbps) {
  kbps = Number(kbps) || 0;
  if (kbps <= 0) return 0;
  return Math.min(1000, Math.round(1000 * Math.pow(kbps / SPEED_SLIDER_MAX_KBPS, 1 / 3)));
}

// The three connection sliders are linear (their ranges are small enough
// that a curve would just add confusion), but 0 means a different thing
// for each: "use libtorrent's own default" for the two connection counts,
// "no cap at all" for the per-torrent one. Spell that out instead of
// showing a bare 0, which reads as broken/empty rather than intentional.
function formatCount(value, zeroLabel) {
  value = Number(value) || 0;
  return value <= 0 ? zeroLabel : String(value);
}

function renderLimits() {
  settingsDownloadLimit.value = kbpsToSlider(lastLimits.download_rate_limit);
  settingsDownloadLimitValue.textContent = formatSpeed(lastLimits.download_rate_limit);
  settingsUploadLimit.value = kbpsToSlider(lastLimits.upload_rate_limit);
  settingsUploadLimitValue.textContent = formatSpeed(lastLimits.upload_rate_limit);
  settingsSeedAfterDownload.checked = (lastLimits.seed_after_download ?? 1) != 0;
  settingsRemoveAfterDownload.checked = (lastLimits.remove_after_download ?? 0) != 0;
  settingsMaxConnections.value = lastLimits.max_connections ?? 0;
  settingsMaxConnectionsValue.textContent = formatCount(lastLimits.max_connections, "Default");
  settingsMaxConnectionsPerTorrent.value = lastLimits.max_connections_per_torrent ?? 0;
  settingsMaxConnectionsPerTorrentValue.textContent = formatCount(lastLimits.max_connections_per_torrent, "No cap");
  settingsMaxUploadSlots.value = lastLimits.max_upload_slots ?? 0;
  settingsMaxUploadSlotsValue.textContent = formatCount(lastLimits.max_upload_slots, "Default");

  settingsJackettUrl.value = lastLimits.jackett_url ?? "";
  settingsJackettApiKey.value = lastLimits.jackett_api_key ?? "";
  settingsTmdbApiKey.value = lastLimits.tmdb_api_key ?? "";
  renderServiceOptions();
}

// Known choices for the indexer/language dropdowns, from /api/settings/options.
// Until it loads (or when Jackett is unreachable) the saved value is still
// offered on its own, so opening Settings never silently changes it.
let serviceOptions = { jackett_indexers: null, tmdb_languages: [] };
const languageNames = (() => {
  try { return new Intl.DisplayNames(["en"], { type: "language" }); } catch (e) { return null; }
})();

function languageLabel(code) {
  let name = null;
  try { name = languageNames?.of(code); } catch (e) {}
  return name && name !== code ? `${name} · ${code}` : code;
}

function fillSelect(select, options, current) {
  if (current && !options.some(o => o.value === current)) {
    options = [...options, { value: current, label: current }];
  }
  select.replaceChildren(...options.map(o => new Option(o.label, o.value)));
  select.value = current || options[0]?.value || "";
}

function renderServiceOptions() {
  const indexers = serviceOptions.jackett_indexers || [];
  fillSelect(settingsJackettIndexer,
    [{ value: "all", label: "All indexers" }, ...indexers.map(i => ({ value: i.id, label: i.title }))],
    lastLimits.jackett_indexer || "all");

  const languages = serviceOptions.tmdb_languages
    .map(code => ({ value: code, label: languageLabel(code) }))
    .sort((a, b) => a.label.localeCompare(b.label));
  fillSelect(settingsTmdbLanguage, languages, lastLimits.tmdb_language || "uk-UA");
}

async function loadServiceOptions() {
  try {
    const res = await fetch("/api/settings/options");
    serviceOptions = await res.json();
    renderServiceOptions();
  } catch (e) {}
}

async function loadLimits() {
  try {
    const res = await fetch("/api/settings");
    lastLimits = await res.json();
  } catch (e) {}
}

async function saveLimits() {
  const body = {
    download_rate_limit: sliderToKbps(settingsDownloadLimit.value),
    upload_rate_limit: sliderToKbps(settingsUploadLimit.value),
    seed_after_download: settingsSeedAfterDownload.checked ? 1 : 0,
    remove_after_download: settingsRemoveAfterDownload.checked ? 1 : 0,
    max_connections: settingsMaxConnections.value,
    max_connections_per_torrent: settingsMaxConnectionsPerTorrent.value,
    max_upload_slots: settingsMaxUploadSlots.value,
    jackett_url: settingsJackettUrl.value,
    jackett_api_key: settingsJackettApiKey.value,
    jackett_indexer: settingsJackettIndexer.value,
    tmdb_api_key: settingsTmdbApiKey.value,
    tmdb_language: settingsTmdbLanguage.value,
  };
  try {
    const res = await fetch("/api/settings", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    });
    const data = await res.json();
    if (data.error) { showToast(data.error, true); return; }
    lastLimits = data;
    renderLimits();
    loadServiceOptions();
    // Jackett/TMDB keys may have just been added or cleared - refresh the
    // Search/Discover-enabled flags without needing a page reload.
    await loadConfig();
    renderSettings();
    showToast("Settings saved");
  } catch (e) {
    showToast("Couldn't save settings", true);
  }
}

function switchSettingsTab(tabId) {
  settingsTabs.querySelectorAll(".settings-tab").forEach(btn =>
    btn.classList.toggle("is-active", btn.dataset.tab === tabId));
  settingsModal.querySelectorAll(".settings-tab-panel").forEach(panel =>
    panel.hidden = panel.dataset.panel !== tabId);
  if (tabId === "players") watchPlayersTab();
}

async function openSettings() {
  renderSettings();
  switchSettingsTab("general");
  settingsModal.classList.add("is-open");
  await loadLimits();
  renderLimits();
  loadServiceOptions();
}

function closeSettings() {
  settingsModal.classList.remove("is-open");
}

settingsBtn.addEventListener("click", openSettings);
document.getElementById("settingsClose")?.addEventListener("click", closeSettings);
settingsModal.addEventListener("click", e => { if (e.target === settingsModal) closeSettings(); });
settingsTabs.addEventListener("click", e => {
  const btn = e.target.closest(".settings-tab");
  if (btn) switchSettingsTab(btn.dataset.tab);
});
settingsDefaultCategory.addEventListener("change", () => rememberCategory(settingsDefaultCategory.value));
settingsPlayer.addEventListener("change", () => { rememberPlayer(settingsPlayer.value); renderPlayersTab(); });

// A native title-attribute tooltip never fires on touch, so the "i" badges
// are buttons that surface their hint as a toast instead - works the same
// tapped on a phone or clicked with a mouse.
settingsModal.addEventListener("click", e => {
  const btn = e.target.closest(".info-tip");
  if (btn) showToast(btn.dataset.tip);
});

settingsDownloadLimit.addEventListener("input", () => { settingsDownloadLimitValue.textContent = formatSpeed(sliderToKbps(settingsDownloadLimit.value)); });
settingsUploadLimit.addEventListener("input", () => { settingsUploadLimitValue.textContent = formatSpeed(sliderToKbps(settingsUploadLimit.value)); });
settingsMaxConnections.addEventListener("input", () => { settingsMaxConnectionsValue.textContent = formatCount(settingsMaxConnections.value, "Default"); });
settingsMaxConnectionsPerTorrent.addEventListener("input", () => { settingsMaxConnectionsPerTorrentValue.textContent = formatCount(settingsMaxConnectionsPerTorrent.value, "No cap"); });
settingsMaxUploadSlots.addEventListener("input", () => { settingsMaxUploadSlotsValue.textContent = formatCount(settingsMaxUploadSlots.value, "Default"); });

[settingsDownloadLimit, settingsUploadLimit, settingsSeedAfterDownload, settingsRemoveAfterDownload, settingsMaxConnections, settingsMaxConnectionsPerTorrent, settingsMaxUploadSlots,
 settingsJackettUrl, settingsJackettApiKey, settingsJackettIndexer, settingsTmdbApiKey, settingsTmdbLanguage]
  .forEach(el => el.addEventListener("change", saveLimits));

settingsSave.addEventListener("click", async () => {
  await saveLimits();
  closeSettings();
});

settingsReset.addEventListener("click", async () => {
  settingsDownloadLimit.value = 0;
  settingsDownloadLimitValue.textContent = "Unlimited";
  settingsUploadLimit.value = 0;
  settingsUploadLimitValue.textContent = "Unlimited";
  settingsSeedAfterDownload.checked = true;
  settingsRemoveAfterDownload.checked = false;
  settingsMaxConnections.value = 0;
  settingsMaxConnectionsValue.textContent = "Default";
  settingsMaxConnectionsPerTorrent.value = 0;
  settingsMaxConnectionsPerTorrentValue.textContent = "No cap";
  settingsMaxUploadSlots.value = 0;
  settingsMaxUploadSlotsValue.textContent = "Default";
  await saveLimits();
});

// ---------- Search ----------

function formatSeedPeers(seeders, peers) {
  return `<span class="search-item-stats"><span class="seeders">${seeders} seeders</span> &middot; <span class="leechers">${peers} peers</span></span>`;
}

let searchRequestId = 0;
let lastSearchResults = [];

let lastSearchQuery = "";
async function runSearch(query) {
  const requestId = ++searchRequestId;
  lastSearchQuery = query;
  document.getElementById("searchTitle").textContent = `Results for “${query}”`;
  window.scrollTo({ top: 0 });
  if (!libraryLoaded) await loadLibrary();
  // The library answers at once; torrents follow below it.
  const inLibrary = librarySearch(query);
  searchDropdown.innerHTML = "";
  if (inLibrary.length) {
    searchDropdown.appendChild(sectionHead("In your library"));
    inLibrary.forEach(item => searchDropdown.appendChild(buildLibraryResult(item)));
    searchDropdown.appendChild(sectionHead("Torrents"));
  }
  searchDropdown.insertAdjacentHTML("beforeend", `<div class="empty-state search-pending" style="padding:24px;">Searching...</div>`);
  searchDropdown.classList.add("is-open");
  goBtn.disabled = true;
  try {
    const res = await fetch(`/api/search?q=${encodeURIComponent(query)}`);
    const data = await res.json();
    if (requestId !== searchRequestId) return; // a newer search superseded this one
    goBtn.disabled = false;
    if (data.error) {
      const pending = searchDropdown.querySelector(".search-pending");
      if (pending) pending.textContent = data.error;
      else searchDropdown.innerHTML = `<div class="empty-state" style="padding:24px;">${escapeHtml(data.error)}</div>`;
      return;
    }
    lastSearchResults = data.results || [];
    renderSearchResults(lastSearchResults);
  } catch (e) {
    if (requestId !== searchRequestId) return;
    goBtn.disabled = false;
    searchDropdown.innerHTML = `<div class="empty-state" style="padding:24px;">Search failed. Try again.</div>`;
  }
}

// Shared by the search dropdown and the Discover catalog - same card
// markup, same "pick a folder and download" flow either way. `container`
// must carry (or be a descendant of something carrying) the
// .search-dropdown class so the card CSS (mobile grid reflow, the
// description's 50%-width cap, expand/collapse) applies. `allResults` is
// what gets re-rendered into `container` if an add fails.
function buildResultCard(r, container, allResults, emptyMessage) {
  const div = document.createElement("div");
  div.className = "item";
  const poster = `<div class="poster-wrap">${r.poster
    ? `<img class="result-poster" src="${escapeHtml(r.poster)}" alt="" loading="lazy">`
    : `<div class="result-poster-fallback brand-host">${brandArt(r.clean_title || r.title)}</div>`}${FAVORITE_BADGE}</div>`;
  div.dataset.favId = r.download_link ?? r.magnet ?? r.title;
  if (isFavorite(div.dataset.favId)) div.classList.add("is-favorite");
  const rating = (r.rating && r.rating > 0) ? `<span class="rating-badge">${ICONS.star}${r.rating.toFixed(1)}</span>` : "";
  const preferred = (r.suggested_category && currentCategories.includes(r.suggested_category)) ? r.suggested_category : getDefaultCategory();
  const categoryOptions = currentCategories.map(c =>
    `<option value="${escapeHtml(c)}"${c === preferred ? " selected" : ""}>${escapeHtml(c)}</option>`
  ).join("");
  div.innerHTML = `
    <div class="item-top">
      ${poster}
      <div class="item-meta">
        <div class="item-title">${escapeHtml(r.clean_title || r.title)}</div>
        <div class="item-sub">${r.size_label} &middot; ${formatSeedPeers(r.seeders, r.peers)} ${rating}${r.releases && r.releases.length > 1 ? `<span class="release-count" title="Pick one in the details">${r.releases.length} versions</span>` : ""}</div>
        ${r.overview ? `<div class="item-overview">${escapeHtml(r.overview)}</div>` : ""}
        ${r.overview && r.overview.length > 100 ? `<button type="button" class="overview-toggle">Show more</button>` : ""}
      </div>
      <div class="search-result-actions">
        <select class="inline-category-select">${categoryOptions}</select>
        <button class="btn-secondary btn-add-result">${ICONS.download}<span>Download</span></button>
      </div>
    </div>
  `;
  const overviewToggle = div.querySelector(".overview-toggle");
  if (overviewToggle) {
    overviewToggle.addEventListener("click", (e) => {
      e.stopPropagation();
      const expanded = div.classList.toggle("is-expanded");
      overviewToggle.textContent = expanded ? "Show less" : "Show more";
    });
  }
  const actionsEl = div.querySelector(".search-result-actions");
  actionsEl.querySelector("select").addEventListener("click", e => e.stopPropagation());
  actionsEl.querySelector(".btn-add-result").addEventListener("click", (e) => {
    e.stopPropagation();
    addSearchResult(r, actionsEl.querySelector("select").value, actionsEl, container, allResults, emptyMessage);
  });
  div.addEventListener("click", (e) => {
    if (!e.target.closest("button, select, a")) openDetails(r);
  });
  return div;
}

function appendResultCards(container, results, allResults, emptyMessage) {
  results.forEach(r => container.appendChild(buildResultCard(r, container, allResults, emptyMessage)));
}

function renderResultCards(container, results, emptyMessage) {
  container.innerHTML = "";
  if (results.length === 0) {
    container.innerHTML = `<div class="empty-state" style="padding:24px;">${escapeHtml(emptyMessage)}</div>`;
    return;
  }
  appendResultCards(container, results, results, emptyMessage);
}

function renderSearchResults(results) {
  searchDropdown.classList.add("is-open");
  const inLibrary = librarySearch(lastSearchQuery);
  if (!inLibrary.length) { renderResultCards(searchDropdown, results, "No results found."); return; }
  searchDropdown.innerHTML = "";
  searchDropdown.appendChild(sectionHead("In your library"));
  inLibrary.forEach(item => searchDropdown.appendChild(buildLibraryResult(item)));
  searchDropdown.appendChild(sectionHead("Torrents"));
  if (results.length) appendResultCards(searchDropdown, results, results, "No results found.");
  else searchDropdown.insertAdjacentHTML("beforeend", `<div class="empty-state" style="padding:16px 24px;">No torrents found.</div>`);
}

// Adds a search/Discover result to Downloads; shared by the card's own
// Download button and the one in the details popup.
async function postSearchResult(result, category) {
  rememberCategory(category);
  const body = { category };
  if (result.magnet) body.magnet = result.magnet;
  else body.download_link = result.download_link;
  const res = await fetch("/api/torrents", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  return res.json();
}

async function addSearchResult(result, category, actionsEl, container, allResults, emptyMessage) {
  actionsEl.innerHTML = `<span class="hint" style="margin:0; padding:0; border:none;">Adding...</span>`;
  const data = await postSearchResult(result, category);
  if (data.error) {
    showToast(data.error, true);
    renderResultCards(container, allResults, emptyMessage);
    return;
  }
  actionsEl.innerHTML = `${ICONS.check}<span>Added</span>`;
  showToast(`"${result.title}" added to ${category}`);
  refresh();
}

// ---------- Details popup ----------
// Clicking any card opens this. It paints straight away from what the card
// already has (title, poster), then fills in the full TMDB record, and in
// parallel looks up every other release of the same title on the tracker
// so the best one can be picked (or downloaded straight from "More like
// this", which has no release of its own). The hero is rendered separately
// from the body, so body updates never restart a playing trailer.

const detailsModal = document.getElementById("detailsModal");
const detailsBody = document.getElementById("detailsBody");
const detailsBack = document.getElementById("detailsBack");
const PLAY_ICON = `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7-11-7z"/></svg>`;

// ---------- Play in Infuse / VLC ----------
// Play starts the torrent in streaming mode on the server (video file
// only, fetched in playback order, into a temporary cache) and gets back a
// URL with Range support. Infuse or VLC opens that URL through its own
// link scheme and does the playing - every container, codec, audio track
// and subtitle, which a browser <video> can't. The server deletes the
// stream once no player has read it for a while (Settings > Playback).
const IS_ANDROID = /Android/i.test(navigator.userAgent);
const IS_WINDOWS = /Windows/i.test(navigator.userAgent);
// iPadOS reports itself as a Mac - touch points tell them apart.
const IS_IOS = /iPhone|iPad|iPod/i.test(navigator.userAgent) || (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1);
const IS_MAC = /Macintosh/.test(navigator.userAgent) && !IS_IOS;
// Computers the VLC helper can be installed on (templates/helpers/).
const VLC_HELPER_OS = IS_MAC ? "mac" : IS_WINDOWS ? "windows" : null;
function vlcHelperInstalled() {
  try { return localStorage.getItem("torrenttube-vlc-helper") === "1"; } catch (e) { return false; }
}

// Infuse accepts a temporary queue as repeated url/filename parameters.
// Pass videos themselves: an ordinary M3U can fail when opened as a video.
function infusePlaybackLink(url, closed, files) {
  const callbacks = closed ? `&x-success=${encodeURIComponent(closed)}&x-error=${encodeURIComponent(closed)}` : "";
  let link = "infuse://x-callback-url/play?";
  for (const file of files || [{ url }]) {
    const entry = `${link.endsWith("?") ? "" : "&"}url=${encodeURIComponent(file.url)}`
      + (file.name ? `&filename=${encodeURIComponent(file.name)}` : "")
      + (Number.isFinite(file.position) ? `&position=${Math.max(0, Math.floor(file.position))}` : "");
    // Keep large series from creating an enormous app link. Always include
    // the selected episode, then as many following episodes as fit.
    if (!link.endsWith("?") && link.length + entry.length + callbacks.length > 16000) break;
    link += entry;
  }
  return link + callbacks;
}

const PLAYERS = {
  infuse: {
    name: "Infuse",
    icon: "/static/players/infuse.png",
    canOpen: true,
    sub: "iPhone, iPad, Apple TV and Mac",
    store: "https://apps.apple.com/app/id1136220934",
    // Web playback omits HTTP return callbacks: they can open another tab
    // instead of returning to the page that launched the player.
    link: infusePlaybackLink,
  },
  vlc: {
    name: "VLC",
    icon: "/static/players/vlc.png",
    // On a phone VLC has its own link; on a Mac or Windows PC the helper
    // adds one (torrenttube-vlc:); elsewhere the link is copied.
    canOpen: IS_IOS || IS_ANDROID || !!VLC_HELPER_OS,
    sub: IS_IOS || IS_ANDROID ? "Free, plays almost anything"
      : VLC_HELPER_OS ? "Free, plays almost anything - needs a one-time helper on this computer"
      : "Copies the link - paste it in VLC's Open Network",
    store: IS_ANDROID ? "https://play.google.com/store/apps/details?id=org.videolan.vlc" : "https://apps.apple.com/app/id650377962",
    link: (url, closed) => {
      if (IS_IOS) return `vlc-x-callback://x-callback-url/stream?url=${encodeURIComponent(url)}${closed ? `&x-success=${encodeURIComponent(closed)}&x-error=${encodeURIComponent(closed)}` : ""}`;
      if (IS_ANDROID) {
        const u = new URL(url);
        return `intent://${u.host}${u.pathname}#Intent;scheme=${u.protocol.replace(":", "")};package=org.videolan.vlc;type=video/*;end`;
      }
      // Desktop VLC registers no link of its own - the helper's. No close
      // callback here: the server sees VLC's connection close instead.
      if (VLC_HELPER_OS) return `torrenttube-vlc:${url}`;
      return null;
    },
  },
};

// One player for the whole app, saved on the server (Settings > Playback >
// Default player, or the ▾ beside Play) - Infuse unless changed.
let defaultPlayerId = "infuse";
function availablePlayers() {
  return Object.keys(PLAYERS);
}
function currentPlayer() {
  return PLAYERS[defaultPlayerId] ? defaultPlayerId : "infuse";
}
async function rememberPlayer(id) {
  if (!PLAYERS[id] || id === defaultPlayerId) return;
  defaultPlayerId = id;
  lastConfig.default_player = id;
  try {
    const data = await fetch("/api/settings", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ default_player: id }),
    }).then(r => r.json());
    if (data.error) throw new Error(data.error);
    lastLimits = data;
  } catch (e) {
    showToast("Couldn't save the default player", true);
  }
}
function playerLogo(id) {
  return `<img class="player-logo" src="${PLAYERS[id].icon}" alt="" width="20" height="20">`;
}
const CHEVRON_DOWN = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>`;
const CLOSE_ICON = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>`;
const LINK_ICON = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 13a5 5 0 007.5.5l3-3a5 5 0 00-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 00-7.5-.5l-3 3a5 5 0 007 7l1.7-1.7"/></svg>`;

const playerModal = document.getElementById("playerModal");
const playerList = document.getElementById("playerList");
let playerPickerThen = null;

// The picker: each player with its logo, plus Copy link once a stream
// exists. `then` runs after a choice - Play on a device that hasn't
// picked a player yet opens this first, then starts the stream.
function openPlayerPicker(then = null) {
  playerPickerThen = then;
  const current = currentPlayer();
  const s = detailsState;
  const canCopy = !!(s && (s.torrent || primaryRelease()));
  playerList.innerHTML = availablePlayers().map(id => `
    <button type="button" class="player-option${id === current ? " is-current" : ""}" data-player="${id}">
      <img class="player-logo" src="${PLAYERS[id].icon}" alt="" width="40" height="40">
      <div class="player-option-text">
        <div class="player-option-name">${escapeHtml(PLAYERS[id].name)}</div>
        <div class="player-option-sub">${escapeHtml(PLAYERS[id].sub)}</div>
      </div>
      <span class="player-option-check">${ICONS.check}</span>
    </button>`).join("") + (canCopy ? `
    <button type="button" class="player-option" data-player="copy">
      <span class="player-option-icon">${LINK_ICON}</span>
      <div class="player-option-text">
        <div class="player-option-name">Copy link</div>
        <div class="player-option-sub">A play link for any other player</div>
      </div>
    </button>` : "");
  playerModal.classList.add("is-open");
}
function closePlayerPicker() {
  playerModal.classList.remove("is-open");
  playerPickerThen = null;
}
playerModal.addEventListener("click", (e) => {
  if (e.target === playerModal) { closePlayerPicker(); return; }
  const opt = e.target.closest("[data-player]");
  if (!opt) return;
  const id = opt.dataset.player;
  if (id === "copy" && detailsState && detailsState.library) {
    const file = libraryFileList()[0];
    if (file) copyText(libraryMediaUrl(file), "Link copied - open it in any player");
    closePlayerPicker();
    return;
  }
  if (id === "copy") {
    const s = detailsState, link = s && (s.torrent || primaryRelease()) ? playLink(s.torrent ? null : primaryRelease(), s.torrent) : null;
    if (link) {
      registerPlayLink(link, false);
      copyText(link.url, "Play link copied - open it in any player");
    }
    closePlayerPicker();
    return;
  }
  rememberPlayer(id);
  const then = playerPickerThen;
  closePlayerPicker();
  if (detailsState) { renderDetailsBody(); }
  if (then) then();
});

function copyText(text, doneMessage) {
  const done = () => showToast(doneMessage);
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text).then(done, () => showToast(text));
    return;
  }
  // Plain http on the LAN isn't a secure context - no Clipboard API.
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.setAttribute("readonly", "");
  ta.style.position = "fixed";
  ta.style.opacity = "0";
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand("copy") ? done() : showToast(text); } catch (e) { showToast(text); }
  ta.remove();
}

// A short stable hash, so the same release always gets the same play link
// (and the player remembers where you stopped). crypto.subtle isn't there
// on plain http, and this has to be synchronous - see playRelease.
function hashHex(str) {
  let a = 0x811c9dc5, b = 0x01000193 ^ 0x5bd1e995;
  for (let i = 0; i < str.length; i++) {
    const c = str.charCodeAt(i);
    a = Math.imul(a ^ c, 0x01000193);
    b = Math.imul(b ^ c, 0x5bd1e995);
  }
  return (a >>> 0).toString(16).padStart(8, "0") + (b >>> 0).toString(16).padStart(8, "0");
}

// The play link for a release (or something in Downloads): a token the
// server learns from POST /api/play, and the title as the file name the
// player shows and looks its artwork up by.
function playLink(release, torrent) {
  let token, source, title;
  if (torrent) {
    token = `d-${torrent.id.toLowerCase()}`;
    source = { id: torrent.id };
    title = torrent.name;
  } else {
    const btih = (release.magnet || "").match(/xt=urn:btih:([0-9a-f]{40})/i);
    token = btih ? `m-${btih[1].toLowerCase()}` : `l-${hashHex(release.magnet || release.download_link || release.title)}`;
    source = release.magnet ? { magnet: release.magnet } : { download_link: release.download_link };
    title = release.title;
  }
  let name = (title || "video").replace(/[\\/:*?"<>|#%]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 150);
  if (!/\.(mkv|mp4|m4v|avi|mov|ts|webm)$/i.test(name)) name += /\bmp4\b/i.test(name) ? ".mp4" : ".mkv";
  return { token, source, title, url: `${location.origin}/play/${token}/${encodeURIComponent(name).replace(/'/g, "%27")}`, closedUrl: `${location.origin}/played/${token}` };
}

// One tap: the player opens straight away with the play link, and the
// server starts the torrent at the same time. Nothing to wait for or stop
// here - the player's first request waits for the file, and the server
// cleans up after media connections close. Launch and registration both
// happen inside the tap, before any await: iOS only lets a page open an
// app from the tap itself.
// Tells the server what a play link plays. `start` false (a copied link)
// registers it without downloading anything until a player opens it.
function registerPlayLink(link, start) {
  return fetch("/api/play", {
    method: "POST", keepalive: true, headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token: link.token, title: link.title, start, ...link.source }),
  }).then(r => r.json()).then(d => { if (d.error) showToast(d.error, true); setTimeout(refresh, 1500); })
    .catch(() => showToast("Couldn't reach the server", true));
}

function playRelease(release) {
  const s = detailsState;
  if (!s || (!release && !s.torrent)) return;
  const link = playLink(release, s.torrent);
  const id = currentPlayer();
  if (id === "vlc" && VLC_HELPER_OS && !vlcHelperInstalled()) {
    openVlcHelper(() => playRelease(release));
    return;
  }
  const appLink = PLAYERS[id].link(link.url, null);
  registerPlayLink(link, !!appLink);
  if (appLink) watchPlayStart(link.token);
  if (appLink) {
    watchAppOpened(id, () => playRelease(release));
    location.href = appLink;
  } else {
    // Desktop VLC registers no link a page can open - the link is copied.
    copyText(link.url, `Link copied. In ${PLAYERS[id].name}, choose File > Open Network and paste it`);
  }
}

// ---------- VLC helper (Mac / Windows) ----------
// A two-step checklist: 1 VLC itself, 2 the helper. Setting up is one
// paste - the command is copied on the tap that opens this - and the
// installer reports back (under this browser's own random key) that it's
// done and whether it found VLC, which the page can't see by itself.
const helperModal = document.getElementById("helperModal");
const helperCommand = document.getElementById("helperCommand");
const helperDone = document.getElementById("helperDone");
let helperThen = null;
let helperPoll = null;

function vlcHelperKey() {
  let key = null;
  try { key = localStorage.getItem("torrenttube-vlc-helper-key"); } catch (e) {}
  if (!/^[0-9a-f]{24}$/.test(key || "")) {
    key = Array.from(crypto.getRandomValues(new Uint8Array(12)), b => b.toString(16).padStart(2, "0")).join("");
    try { localStorage.setItem("torrenttube-vlc-helper-key", key); } catch (e) {}
  }
  return key;
}

function vlcHelperCommand() {
  const url = `${location.origin}/helper/${VLC_HELPER_OS === "mac" ? "vlc-mac.sh" : "vlc-windows.ps1"}?k=${vlcHelperKey()}`;
  return VLC_HELPER_OS === "mac" ? `curl -fsSL "${url}" | sh` : `irm "${url}" | iex`;
}

function setStep(el, state, mark) {
  el.classList.toggle("is-done", state === "done");
  el.classList.toggle("is-warn", state === "warn");
  el.querySelector(".setup-mark").textContent = state === "done" ? "✓" : state === "warn" ? "!" : mark;
}

// vlc: true / false / null (not known yet - only the installer can tell).
function renderVlcHelper(installed, vlc) {
  const vlcStep = document.getElementById("helperStepVlc");
  const vlcText = document.getElementById("helperVlcText");
  setStep(vlcStep, vlc === true ? "done" : vlc === false ? "warn" : "todo", "1");
  vlcText.textContent = vlc === true ? "VLC is installed."
    : vlc === false ? "VLC isn't on this computer yet. Download and install it, then press Play."
    : "The free player that plays the film. Don't have it yet? Install it first.";
  document.getElementById("helperVlcLink").hidden = vlc === true;

  const helperStep = document.getElementById("helperStepHelper");
  setStep(helperStep, installed ? "done" : "todo", "2");
  document.getElementById("helperHelperText").textContent = installed
    ? "Helper installed - Play now opens VLC."
    : "Your browser can't start VLC by itself. This small helper lets Play open VLC, just like Infuse. It only opens films from this server.";
  for (const id of ["helperSubsteps", "helperCommandBox", "helperWait", "helperFoot"]) document.getElementById(id).hidden = installed;

  const ready = installed && vlc !== false;
  document.getElementById("helperModalTitle").textContent = ready ? "VLC is ready" : installed ? "Almost ready" : "Play in VLC on this computer";
  document.getElementById("helperModalSub").textContent = ready ? "All set on this computer."
    : installed ? "Install VLC, then press Play." : "Two steps, once per computer.";
  helperDone.hidden = !installed;
  helperDone.textContent = helperThen ? "Play" : "Done";
}

function markVlcHelperInstalled(vlc = null) {
  try {
    localStorage.setItem("torrenttube-vlc-helper", "1");
    if (vlc !== null) localStorage.setItem("torrenttube-vlc-found", vlc ? "1" : "0");
  } catch (e) {}
  clearInterval(helperPoll);
  renderVlcHelper(true, vlc);
  if (detailsState) renderDetailsBody();
}

// `then` (Play) runs from the Play button's own tap, so it can open VLC.
function openVlcHelper(then = null) {
  helperThen = then;
  const mac = VLC_HELPER_OS === "mac";
  document.getElementById("helperStepOpen").textContent = mac
    ? "Open Terminal: press ⌘ Space, type Terminal, press Return."
    : "Open PowerShell: press the Windows key, type PowerShell, press Enter.";
  document.getElementById("helperStepPaste").textContent = mac
    ? "Press ⌘ V, then Return - the command below is already copied."
    : "Press Ctrl + V, then Enter - the command below is already copied.";
  helperCommand.textContent = vlcHelperCommand();
  renderVlcHelper(false, null);
  helperModal.classList.add("is-open");
  copyText(vlcHelperCommand(), `Command copied - paste it in ${mac ? "Terminal" : "PowerShell"}`);
  clearInterval(helperPoll);
  helperPoll = setInterval(async () => {
    if (!helperModal.classList.contains("is-open")) { clearInterval(helperPoll); return; }
    try {
      const d = await fetch(`/api/helper/${vlcHelperKey()}`).then(r => r.json());
      if (d.installed) markVlcHelperInstalled(d.vlc);
    } catch (e) {}
  }, 1500);
}
function closeVlcHelper() {
  helperModal.classList.remove("is-open");
  clearInterval(helperPoll);
  helperThen = null;
}
document.getElementById("helperCopy").addEventListener("click", () => copyText(vlcHelperCommand(), "Command copied"));
document.getElementById("helperCancel").addEventListener("click", closeVlcHelper);
document.getElementById("helperAlready").addEventListener("click", () => markVlcHelperInstalled());
helperDone.addEventListener("click", () => {
  const then = helperThen;
  closeVlcHelper();
  if (then) then();
});
helperModal.addEventListener("click", e => { if (e.target === helperModal) closeVlcHelper(); });

// ---------- Settings > Players ----------
// What this device can tell: an app gets ✓ once it has opened from here;
// VLC on a computer from its helper's installer, which also reports
// whether it found VLC. The helper's uninstaller reports too, so the card
// swaps the remove command for the install one by itself.
function lsGet(name) { try { return localStorage.getItem(name); } catch (e) { return null; } }

function vlcHelperUninstallCommand() {
  const url = `${location.origin}/helper/${VLC_HELPER_OS === "mac" ? "vlc-mac-uninstall.sh" : "vlc-windows-uninstall.ps1"}?k=${vlcHelperKey()}`;
  return VLC_HELPER_OS === "mac" ? `curl -fsSL "${url}" | sh` : `irm "${url}" | iex`;
}

function badge(state, text) {
  return `<span class="status-badge ${state}">${escapeHtml(text)}</span>`;
}

let playersTabShown = "";
function renderPlayersTab() {
  const def = currentPlayer();
  // Redrawn only when something changed - the poll calls this every 2s,
  // and a redraw would drop a selection in the command box.
  const state = [def, vlcHelperInstalled(), lsGet("torrenttube-vlc-found"), lsGet("torrenttube-opened-infuse"), lsGet("torrenttube-opened-vlc")].join("|");
  if (state === playersTabShown && document.getElementById("playerCardVlc").innerHTML) return;
  playersTabShown = state;
  const links = list => `<div class="player-card-links">${list.map(([label, href]) =>
    `<a href="${escapeHtml(href)}" target="_blank" rel="noopener">${escapeHtml(label)}</a>`).join("")}</div>`;
  // Download links sit in the header, where the name's row has room.
  const head = id => `<div class="player-card-head"><img class="player-logo" src="${PLAYERS[id].icon}" alt="" width="32" height="32">
    <div class="player-card-name">${escapeHtml(PLAYERS[id].name)}</div>${links(GET_APP[id].links)}</div>`;

  const apple = IS_IOS || IS_MAC;
  const infuseOpened = lsGet("torrenttube-opened-infuse") === "1";
  document.getElementById("playerCardInfuse").innerHTML = head("infuse") + `
    <div class="player-card-row"><span>Infuse app</span>${!apple ? badge("is-off", "Apple devices only")
      : infuseOpened ? badge("is-on", "Installed") : badge("is-off", "Not checked yet")}</div>`;

  const helperInstalled = vlcHelperInstalled();
  const vlcFound = lsGet("torrenttube-vlc-found");
  const vlcOpened = lsGet("torrenttube-opened-vlc") === "1";
  const vlcBadge = vlcFound === "1" || vlcOpened ? badge("is-on", "Installed")
    : vlcFound === "0" ? badge("is-warn", "Not found") : badge("is-off", "Not checked yet");
  let helper = "";
  if (VLC_HELPER_OS) {
    const terminal = VLC_HELPER_OS === "mac" ? "Terminal" : "PowerShell";
    const cmd = helperInstalled ? vlcHelperUninstallCommand() : vlcHelperCommand();
    helper = `
      <div class="player-card-row"><span>Torrent Tube helper</span>${helperInstalled ? badge("is-on", "Installed") : badge("is-off", "Not installed")}</div>
      <div class="helper-block">
        <div class="helper-block-title">${helperInstalled ? "Remove the helper" : "Install the helper"}</div>
        <div class="setup-text">${helperInstalled
          ? `Paste in ${terminal} and press Return. VLC itself stays.`
          : `Lets Play open VLC on this computer, like Infuse. Paste in ${terminal} and press Return.`}</div>
        <div class="helper-command"><code>${escapeHtml(cmd)}</code><button type="button" class="btn-secondary" data-copy="${escapeHtml(cmd)}">Copy</button></div>
        ${helperInstalled ? "" : `<button type="button" class="dt-link-btn" data-act="vlc-setup">Step-by-step setup</button>`}
      </div>`;
  }
  document.getElementById("playerCardVlc").innerHTML = head("vlc") + `
    <div class="player-card-row"><span>VLC app</span>${vlcBadge}</div>
    ${helper}`;
}

let playersPoll = null;
function watchPlayersTab() {
  clearInterval(playersPoll);
  renderPlayersTab();
  if (!VLC_HELPER_OS) return;
  playersPoll = setInterval(async () => {
    const panel = settingsModal.querySelector('[data-panel="players"]');
    if (!settingsModal.classList.contains("is-open") || panel.hidden) { clearInterval(playersPoll); return; }
    try {
      const d = await fetch(`/api/helper/${vlcHelperKey()}`).then(r => r.json());
      if (!d.known) return;  // nothing said since the server started - keep what this browser knows
      try {
        if (d.installed) localStorage.setItem("torrenttube-vlc-helper", "1");
        else localStorage.removeItem("torrenttube-vlc-helper");
        if (d.vlc !== null) localStorage.setItem("torrenttube-vlc-found", d.vlc ? "1" : "0");
      } catch (e) {}
      renderPlayersTab();
    } catch (e) {}
  }, 2000);
}
settingsModal.addEventListener("click", (e) => {
  const copy = e.target.closest("[data-copy]");
  if (copy) copyText(copy.dataset.copy, "Command copied");
  if (e.target.closest('[data-act="vlc-setup"]')) openVlcHelper();
});

// ---------- A player that didn't open ----------
// A page can't see installed apps, only that the app didn't open - then
// this says where to get it (official sites and stores).
const getAppModal = document.getElementById("getAppModal");
let getAppRetry = null;
const GET_APP = {
  infuse: {
    text: "Infuse plays the film from this server. Get it on the App Store - for iPhone, iPad, Apple TV and Mac.",
    links: [["App Store", "https://apps.apple.com/app/id1136220934"], ["firecore.com", "https://firecore.com"]],
  },
  vlc: {
    text: "VLC is a free player that plays the film from this server.",
    links: IS_ANDROID
      ? [["Google Play", "https://play.google.com/store/apps/details?id=org.videolan.vlc"], ["videolan.org", "https://www.videolan.org/vlc/"]]
      : IS_IOS
      ? [["App Store", "https://apps.apple.com/app/id650377962"], ["videolan.org", "https://www.videolan.org/vlc/"]]
      : [["videolan.org", "https://www.videolan.org/vlc/"]],
  },
};

function openGetApp(id, retry) {
  getAppRetry = retry;
  const p = PLAYERS[id];
  document.getElementById("getAppLogo").src = p.icon;
  document.getElementById("getAppTitle").textContent = `${p.name} didn't open`;
  document.getElementById("getAppStepTitle").textContent = `Install ${p.name}`;
  document.getElementById("getAppText").textContent = GET_APP[id].text;
  const links = document.getElementById("getAppLinks");
  links.replaceChildren(...GET_APP[id].links.map(([label, href]) => {
    const a = document.createElement("a");
    Object.assign(a, { href, textContent: label, target: "_blank", rel: "noopener" });
    return a;
  }));
  getAppModal.classList.add("is-open");
}
function closeGetApp() {
  getAppModal.classList.remove("is-open");
  getAppRetry = null;
}
document.getElementById("getAppRetry").addEventListener("click", () => {
  const retry = getAppRetry;
  closeGetApp();
  if (retry) retry();
});
document.getElementById("getAppOther").addEventListener("click", () => { closeGetApp(); openPlayerPicker(); });
getAppModal.addEventListener("click", e => { if (e.target === getAppModal) closeGetApp(); });
// The app opened after all (a slow "Open in …?" prompt) - nothing to say.
document.addEventListener("visibilitychange", () => { if (document.hidden) closeGetApp(); });

// The player only says "can't open" if the stream fails to start (a dead
// tracker link, no peers) - ask the server why for up to a minute and say it.
function watchPlayStart(token) {
  const until = Date.now() + 60000;
  const check = async () => {
    try {
      const d = await fetch(`/api/play/${encodeURIComponent(token)}`).then(r => r.json());
      if (d.error) { showToast(`Couldn't play: ${d.error}`, true); return; }
      if (d.started) return;
    } catch (e) {}
    if (Date.now() < until) setTimeout(check, 2000);
  };
  setTimeout(check, 1500);
}

// No app behind the link: iOS shows "cannot open the page" and the page
// stays visible; on a computer nothing happens. Still visible and in focus
// a few seconds later (the "Open in …?" prompt takes a moment): show how
// to get the app - or, for VLC on a computer, the helper setup again.
function watchAppOpened(id, retry) {
  let left = false;
  const onHide = () => { if (document.hidden) left = true; };
  const onBlur = () => { left = true; };
  document.addEventListener("visibilitychange", onHide);
  window.addEventListener("pagehide", onHide);
  window.addEventListener("blur", onBlur);
  setTimeout(() => {
    document.removeEventListener("visibilitychange", onHide);
    window.removeEventListener("pagehide", onHide);
    window.removeEventListener("blur", onBlur);
    if (left || document.hidden) {
      try { localStorage.setItem(`torrenttube-opened-${id}`, "1"); } catch (e) {}  // Settings > Players
      return;
    }
    if (id === "vlc" && VLC_HELPER_OS) openVlcHelper(retry);
    else openGetApp(id, retry);
  }, 5000);
}

// Save a stream (from its Downloads row) as a download in the default folder.
async function saveStream(id) {
  const category = getDefaultCategory();
  try {
    const data = await fetch(`/api/stream/${encodeURIComponent(id)}/keep`, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ category }),
    }).then(r => r.json());
    if (data.error) throw new Error(data.error);
    showToast(`Saved - it's downloading to ${data.category || category}`);
  } catch (e) {
    showToast(e.message || "Couldn't save it", true);
  }
  refresh();
}

// Stops a stream from its Downloads row: deleted with its files now,
// instead of a couple of minutes after the player closes.
async function stopStreamById(id) {
  try {
    const data = await fetch(`/api/stream/${encodeURIComponent(id)}`, { method: "DELETE" }).then(r => r.json());
    showToast(data.deleted ? "Stopped - the temporary file is deleted" : "Stopped - the download itself continues in Downloads");
  } catch (e) {
    showToast("Couldn't stop it", true);
  }
  refresh();
}
const RELEASES_SHOWN = 5;

let detailsRequestId = 0;
let detailsState = null;
let personState = null;
const personCache = new Map();
let titleReturnFocus = null;
let titleWorkspaceScroll = 0;
const detailsCache = new Map();
const releasesCache = new Map();

function formatRuntime(mins) {
  if (!mins) return "";
  const h = Math.floor(mins / 60), m = mins % 60;
  return h ? `${h}h${m ? ` ${m}m` : ""}` : `${m}m`;
}

function formatDate(str) {
  if (!str) return "";
  const d = new Date(str);
  return isNaN(d) ? "" : d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

function formatMoney(n) {
  try {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", notation: "compact", maximumFractionDigits: 1 }).format(n);
  } catch (e) {
    return `$${n}`;
  }
}

function languageName(code) {
  let name = null;
  try { name = languageNames?.of(code); } catch (e) {}
  return name && name !== code ? name : (code || "");
}

function youtubeSearchUrl(query) {
  return `https://www.youtube.com/results?search_query=${encodeURIComponent(query)}`;
}

// Tracker titles have no structure, but the bits that tell releases apart
// (resolution, source, HDR, dub, season) are standard enough to pick out.
function releaseTags(title) {
  const tags = [];
  const res = /2160p|\b4k\b|\buhd\b/i.test(title) ? "4K" : /1080[pi]/i.test(title) ? "1080p"
    : /720p/i.test(title) ? "720p" : /480p|dvdrip|\bsd\b/i.test(title) ? "SD" : "";
  if (res) tags.push({ label: res, res: true });
  const season = title.match(/\bS(\d{1,2})(?:E\d+)?\b|сезон\s*(\d{1,2})|(\d{1,2})\s*сезон/i);
  if (season) tags.push({ label: `S${Number(season[1] || season[2] || season[3])}` });
  const source = title.match(/\b(remux|bdremux|blu-?ray|bdrip|web-?dl|web-?rip|hdtv|hdrip|dvdrip|camrip)\b/i);
  if (source) tags.push({ label: source[1].toUpperCase().replace("BLU-RAY", "BLURAY") });
  if (/\bhdr(10)?\+?\b/i.test(title)) tags.push({ label: "HDR" });
  if (/dolby\s?vision|\bdv\b/i.test(title)) tags.push({ label: "DV" });
  if (/\bukr\b|укр|українськ/i.test(title)) tags.push({ label: "UKR" });
  return tags;
}

// The tracker page link first: Jackett re-signs download links on every
// request, so the same release from two searches has two different ones.
function releaseKey(r) {
  return r.details_link || r.magnet || r.download_link || r.title;
}

// Picks the folder the way the server's guess_category does - by what the
// category's own name hints at - so it still works if they're renamed.
function categoryForKind(kind) {
  const find = (...hints) => currentCategories.find(c => hints.some(h => c.toLowerCase().includes(h)));
  if (kind === "Cartoon") return find("cartoon", "anim");
  if (kind === "TV show") return find("tv", "show", "series");
  if (kind === "Movie") return find("movie");
  return null;
}

// Best-effort searchable title from a raw tracker/torrent name, for when
// TMDB didn't match - "Дюна / Dune (2021) BDRip" -> "Дюна".
function roughTitle(raw) {
  return (raw || "").split("/")[0].split("|")[0].replace(/[\[(].*$/, "").replace(/[._]/g, " ")
    .replace(/\b(19|20)\d{2}\b.*$/, "").trim() || raw;
}

function titlePageURL(item, torrent, season) {
  const url = new URL(location.href);
  ["title", "type", "id", "library", "torrent", "season", "person", "name", "filter"].forEach(k => url.searchParams.delete(k));
  url.searchParams.set("title", item.clean_title || item.title);
  if (item.tmdb_id && item.media_type) {
    url.searchParams.set("type", item.media_type);
    url.searchParams.set("id", item.tmdb_id);
  }
  if (item.library) url.searchParams.set("library", item.library.id);
  if (torrent) url.searchParams.set("torrent", torrent.id);
  if (season != null) url.searchParams.set("season", season);
  return url;
}

function openDetails(item, torrent = null, { fromHistory = false, season = null } = {}) {
  setHeaderSearch(false);
  if (!item.library && item.tmdb_id) {
    const type = item.media_type || item.mediaType;
    const local = libraryItems.find(t => t.tmdb_id === item.tmdb_id && (!type || t.media_type === type));
    if (local) item = { ...item, library: local };
  }
  if (!detailsState && !personState) {
    titleReturnFocus = document.activeElement;
    titleWorkspaceScroll = window.scrollY;
    if (!fromHistory) history.replaceState({ ...history.state, ttWorkspace: true, ttScroll: titleWorkspaceScroll }, "", location.href);
  } else if (!fromHistory) {
    history.replaceState({ ...history.state, ttScroll: window.scrollY }, "", location.href);
  }
  if (!fromHistory) {
    const depth = (history.state?.ttDepth || 0) + 1;
    history.pushState({ ttTitle: { item, torrent }, ttDepth: depth, ttSeason: season }, "", titlePageURL(item, torrent, season));
  }
  setDetailsBackVisible(true);
  detailsModal.hidden = false;
  document.body.classList.add("has-title-page");

  const requestId = ++detailsRequestId;
  personState = null;
  detailsModal.setAttribute("aria-label", "Title details");
  destroyTrailerPlayer(detailsState);
  detailsBody.innerHTML = "";  // fresh banner (and player slot) per title
  loadYouTubeApi().catch(() => {});
  detailsState = {
    item, torrent,
    data: { title: item.clean_title || item.title, poster: item.poster, rating: item.rating, overview: item.overview, tmdb_id: item.tmdb_id, media_type: item.media_type || item.library?.media_type || (item.library?.kind === "tv" ? "tv" : null) },
    loading: true, error: "",
    trailers: [], trailerSource: null, activeTrailer: null, playing: false, findingTrailer: false, noTrailer: false,
    releases: item.releases || null, showAllReleases: false, added: new Set(),
    category: null, browseSeason: season, releaseRequest: 0,
    library: item.library || null, libraryFiles: null,
  };
  if (item.library) loadLibraryFiles(requestId);
  renderDetailsHero();
  renderDetailsBody();
  detailsModal.classList.add("is-open");
  window.scrollTo({ top: 0 });
  detailsModal.querySelector(".details-box").focus({ preventScroll: true });
  document.title = `${item.clean_title || item.title} · Torrent Tube`;

  const cacheKey = item.tmdb_id && item.media_type ? `${item.media_type}:${item.tmdb_id}` : `title:${item.title}`;
  const params = item.tmdb_id && item.media_type
    ? `type=${encodeURIComponent(item.media_type)}&id=${encodeURIComponent(item.tmdb_id)}`
    : `title=${encodeURIComponent(item.title)}`;
  const request = detailsCache.get(cacheKey) || fetch(`/api/details?${params}`).then(res => res.json());
  detailsCache.set(cacheKey, request);
  request
    .then(data => {
      if (requestId !== detailsRequestId) return;
      if (data.error) throw new Error(data.error);
      Object.assign(detailsState, { data, loading: false, trailers: data.trailers || [], trailerSource: "tmdb" });
      renderDetailsHero();
      renderDetailsBody();
      if (detailsState.trailers.length) prepareTrailerPlayer(detailsState.trailers[0].key);
      loadReleases(data.title, requestId);
      if (fromHistory && history.state?.ttScroll) window.scrollTo({ top: history.state.ttScroll });
    })
    .catch(e => {
      detailsCache.delete(cacheKey);
      if (requestId !== detailsRequestId) return;
      Object.assign(detailsState, { loading: false, error: e.message || "Couldn't load details" });
      renderDetailsHero();  // the branded banner
      renderDetailsBody();
      loadReleases(item.clean_title || roughTitle(item.title), requestId);
    });
}

function updatePageHeader(title = null, subtitle = null) {
  const brand = document.getElementById('pageBrand');
  brand.classList.toggle('has-page-title', !!title);
  brand.querySelector('h1').textContent = title || 'Torrent Tube';
  brand.querySelector('h1').toggleAttribute('data-no-i18n', !!title);
  const secondary = brand.querySelector('p');
  secondary.textContent = title ? (subtitle && subtitle !== title ? subtitle : '') : 'Online library';
  secondary.toggleAttribute('data-no-i18n', !!title && subtitle !== 'Cast & crew');
}

// The box knows whether Back is showing, so the trailer strip can make room.
function setDetailsBackVisible(visible) {
  detailsBack.hidden = !visible;
  document.getElementById("homeLogo").hidden = visible;
  detailsModal.querySelector(".details-box").classList.toggle("has-back", visible);
}

function closeDetails({ updateURL = true } = {}) {
  destroyTrailerPlayer(detailsState);
  detailsModal.classList.remove("is-open");
  detailsModal.hidden = true;
  document.body.classList.remove("has-title-page");
  detailsRequestId++;
  detailsBody.innerHTML = "";
  detailsState = null;
  personState = null;
  setDetailsBackVisible(false);
  updatePageHeader();
  document.title = "Torrent Tube";
  if (updateURL) {
    const url = new URL(location.href);
    ["title", "type", "id", "library", "torrent", "season", "person", "name", "filter"].forEach(k => url.searchParams.delete(k));
    history.replaceState({ ttWorkspace: true, ttScroll: titleWorkspaceScroll }, "", url);
  }
  window.scrollTo({ top: history.state?.ttScroll ?? titleWorkspaceScroll });
  if (titleReturnFocus?.isConnected) titleReturnFocus.focus({ preventScroll: true });
}

function detailsGoBack() {
  if (history.state?.ttDepth > 0) history.back();
  else closeDetails();
}

async function restoreTitleRoute() {
  const params = new URLSearchParams(location.search);
  if (params.has("person")) {
    const id = Number(params.get("person"));
    if (Number.isSafeInteger(id) && id > 0) {
      openPerson({ id, name: params.get("name") || "Cast & crew" }, { fromHistory: true, filter: params.get("filter") });
      return;
    }
  }
  if (!params.has("title")) { closeDetails({ updateURL: false }); return; }
  const previous = history.state?.ttTitle;
  const sameIdentity = params.has("id") ? String(previous?.item.tmdb_id) === params.get("id") && previous?.item.media_type === params.get("type")
    : previous?.item.title === params.get("title") || previous?.item.clean_title === params.get("title");
  const cached = sameIdentity && (!params.has("library") || previous?.item.library?.id === params.get("library")) ? previous : null;
  let item = cached?.item || { title: params.get("title"), clean_title: params.get("title"),
    tmdb_id: Number(params.get("id")) || null, media_type: params.get("type") };
  let torrent = cached?.torrent || null;
  // A share link or reload restores the local playback source from the server.
  if (params.has("library") && !item.library) {
    try {
      const data = await fetch("/api/library").then(r => r.json());
      const local = (data.items || []).find(t => t.id === params.get("library"));
      if (local) item = { ...item, library: local, poster: local.poster, rating: local.rating };
    } catch (e) { showToast("Couldn't read the server library", true); }
  }
  if (params.has("torrent") && !torrent) {
    try {
      const data = await fetch("/api/torrents").then(r => r.json());
      torrent = (data.torrents || []).find(t => t.id === params.get("torrent")) || null;
    } catch (e) { showToast("Couldn't read downloads", true); }
  }
  // Ignore a late restore after the user has already navigated elsewhere.
  if (location.search !== params.toString() && new URLSearchParams(location.search).toString() !== params.toString()) return;
  const rawSeason = params.get("season");
  const season = rawSeason == null ? null : Number(rawSeason);
  openDetails(item, torrent, { fromHistory: true, season: Number.isInteger(season) && season >= 0 ? season : null });
}
window.addEventListener("popstate", restoreTitleRoute);

// Does a tracker row belong to this title? The tracker search is by name,
// so "Дюна" also returns "Дюна: Частина друга (2024)" - the year tells
// them apart (±1 for festival vs. release year; a show's whole run).
function releaseMatches(r, d) {
  const years = (r.title.match(/\b(19|20)\d{2}\b/g) || []).map(Number);
  if (!d.year || !years.length) return true;
  const start = Number(d.year);
  if (d.media_type === "tv") {
    const end = d.last_air_date ? Number(d.last_air_date.slice(0, 4)) : new Date().getFullYear();
    return years.some(y => y >= start - 1 && y <= end + 1);
  }
  return years.some(y => Math.abs(y - start) <= 1);
}

function seasonMatchesRelease(title, season) {
  if (season == null) return true;
  const s = Number(season);
  if (!Number.isFinite(s)) return true;
  const explicit = new RegExp(`\\b(?:s|season|сезон)\\s*0*${s}(?:e\\d+|\\b)`, "i");
  if (explicit.test(title)) return true;
  const rangeRegex = /\b(?:s|season|сезон)?\s*0*(\d+)\s*[-–]\s*(?:s|season|сезон)?\s*0*(\d+)\b/gi;
  let match;
  while ((match = rangeRegex.exec(title)) !== null) {
    const start = Number(match[1]), end = Number(match[2]);
    if (Number.isFinite(start) && Number.isFinite(end) && start <= s && s <= end) return true;
  }
  return false;
}

function episodeMatchesRelease(title, season, episode) {
  const s = Number(season), e = Number(episode);
  if (!Number.isFinite(s) || !Number.isFinite(e)) return false;
  const explicit = new RegExp(`\\b(?:s\\s*0*${s}\\s*e\\s*0*${e}|0*${s}\\s*x\\s*0*${e})\\b`, "i");
  if (explicit.test(title)) return true;
  const rangeRegex = new RegExp(`\\b(?:s\\s*0*${s}\\s*)?e\\s*0*(\\d+)\\s*[-–]\\s*(?:e\\s*)?0*(\\d+)\\b`, "gi");
  let match;
  while ((match = rangeRegex.exec(title)) !== null) {
    const start = Number(match[1]), end = Number(match[2]);
    if (Number.isFinite(start) && Number.isFinite(end) && start <= e && e <= end) return true;
  }
  return false;
}

async function loadReleases(query, requestId, force = false) {
  if (detailsState && detailsState.library && !force) return;  // its own files instead
  // A grouped search card already carries every version of its title -
  // show those straight away, then add whatever the title search finds.
  const state = detailsState;
  const releaseRequest = ++state.releaseRequest;
  const own = state.releaseEpisode ? [] : state.item.releases || [];
  if (!searchEnabled || !query) { detailsState.releases = own; renderDetailsBody(); return; }
  detailsState.releases = own.length ? own : "loading";
  state.releaseError = "";
  renderDetailsBody();

  const fetchQuery = async (q) => {
    if (!q) return [];
    try {
      const request = releasesCache.get(q) || fetch(`/api/search?q=${encodeURIComponent(q)}&enrich=0`).then(res => res.json());
      releasesCache.set(q, request);
      const data = await request;
      if (data.error) { releasesCache.delete(q); return []; }
      return data.results || [];
    } catch (e) {
      releasesCache.delete(q);
      return [];
    }
  };

  let rows = [], releaseError = "";
  try {
    const queries = [query];
    const altTitle = state.data?.original_title;
    if (altTitle && altTitle !== query && !state.releaseEpisode) {
      queries.push(altTitle);
    }
    const results = await Promise.all(queries.map(fetchQuery));
    const merged = [];
    const seen = new Set();
    for (const list of results) {
      for (const r of list) {
        const k = releaseKey(r);
        if (!seen.has(k)) { seen.add(k); merged.push(r); }
      }
    }
    rows = merged;
  } catch (e) {
    releaseError = e.message || "Couldn't search for releases. Try again.";
  }
  if (requestId !== detailsRequestId || detailsState !== state || state.releaseRequest !== releaseRequest) return;
  state.releaseError = releaseError;
  const { item, data: d } = detailsState;
  const current = !state.releaseEpisode && item.size_label ? releaseKey(item) : null;
  const known = new Set([current, ...own.map(releaseKey)]);
  rows = rows.filter(r => !known.has(releaseKey(r)) && releaseMatches(r, d));
  rows = [...own.filter(r => releaseKey(r) !== current), ...rows];
  rows.sort((a, b) => b.seeders - a.seeders);
  detailsState.releases = current ? [item, ...rows] : rows;
  // The banner's Play button depends on having a release - redraw it,
  // unless something's playing in it.
  if (!detailsState.playing) renderDetailsHero();
  renderDetailsBody();
}

// The release the big Download button grabs: the one clicked, or - for a
// title opened from "More like this" or Downloads - the best-seeded match.
function primaryRelease() {
  const { item, releases, browseSeason, data } = detailsState;
  if (item.size_label) return item;
  if (!Array.isArray(releases) || !releases.length) return null;
  if (data?.media_type === "tv" && browseSeason != null) {
    const seasonMatch = releases.find(r => r.seeders > 0 && seasonMatchesRelease(r.title, browseSeason))
      || releases.find(r => seasonMatchesRelease(r.title, browseSeason));
    if (seasonMatch) return seasonMatch;
  }
  return releases.find(r => r.seeders > 0) || releases[0] || null;
}

async function findYoutubeTrailers() {
  const { data: d, item } = detailsState;
  const requestId = detailsRequestId;
  detailsState.findingTrailer = true;
  renderDetailsHero();
  renderDetailsBody();
  let videos = [];
  try {
    const title = d.title || item.clean_title || item.title;
    const res = await fetch(`/api/trailer?title=${encodeURIComponent(title)}&year=${encodeURIComponent(d.year || "")}`);
    videos = (await res.json()).videos || [];
  } catch (e) {}
  if (requestId !== detailsRequestId) return;
  Object.assign(detailsState, { findingTrailer: false, trailers: videos, trailerSource: "youtube", noTrailer: !videos.length });
  if (videos.length) playTrailer(videos[0].key);
  else { renderDetailsHero(); renderDetailsBody(); }
}



// Plays the trailer: straight away if the preloaded player is ready
// (normally the tap already went through to it - see .dt-player-slot),
// or as soon as it is.
function playTrailer(key) {
  const s = detailsState;
  if (!s) return;
  Object.assign(s, { activeTrailer: key, playing: true });
  renderDetailsHero();
  renderDetailsBody();
  if (s.player && s.playerKey === key) {
    if (s.playerReady) {
      try { s.player.playVideo(); } catch (e) {}
    }
  } else {
    prepareTrailerPlayer(key);
  }
}

function closeTrailer() {
  const s = detailsState;
  if (!s) return;
  s.playing = false;
  if (s.player) {
    try { s.player.pauseVideo(); } catch (e) {}
    try { s.player.cueVideoById(s.activeTrailer || s.playerKey); } catch (e) {}
  }
  renderDetailsHero();
  renderDetailsBody();
}

function destroyTrailerPlayer(s) {
  if (s && s.player) { try { s.player.destroy(); } catch (e) {} }
  if (s) Object.assign(s, { player: null, playerKey: null, playerReady: false });
}

let youtubeApiPromise = null;
function loadYouTubeApi() {
  if (window.YT && window.YT.Player) return Promise.resolve();
  if (!youtubeApiPromise) {
    youtubeApiPromise = new Promise((resolve, reject) => {
      const prev = window.onYouTubeIframeAPIReady;
      window.onYouTubeIframeAPIReady = () => { if (prev) prev(); resolve(); };
      const script = document.createElement("script");
      script.src = "https://www.youtube.com/iframe_api";
      script.onerror = () => { youtubeApiPromise = null; reject(new Error("YouTube player didn't load")); };
      document.head.appendChild(script);
    });
  }
  return youtubeApiPromise;
}

// Starts the trailer through YouTube's player API instead of a plain
// autoplay=1 embed. Always with sound: where the browser won't autoplay
// with sound (Safari), it simply waits for a tap on YouTube's own play
// button rather than starting muted.
//
// Subtitles in the user's language (the TMDB language - uk-UA -> "uk"):
// when the trailer isn't already in that language, YouTube is asked to
// load captions, and once it reports the video's caption tracks, a real
// Ukrainian track is switched on - or, failing that, YouTube's own
// auto-translation of the best other track (a hand-made one over
// auto-generated). A trailer with no captions at all gets none.
function subtitleLanguage() {
  return (lastConfig.tmdb_language || navigator.language || "").split("-")[0].toLowerCase();
}

async function prepareTrailerPlayer(key) {
  const s = detailsState;
  if (s.player && s.playerKey === key) return;
  destroyTrailerPlayer(s);
  s.playerKey = key;
  const mount = document.getElementById("dtPlayer");
  try {
    await loadYouTubeApi();
  } catch (e) {
    if (s.playing && mount) {
      mount.innerHTML = `<iframe src="https://www.youtube-nocookie.com/embed/${encodeURIComponent(key)}?autoplay=1&playsinline=1&rel=0" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen style="position:absolute;inset:0;width:100%;height:100%;border:0;"></iframe>`;
    }
    return;
  }
  if (!mount || detailsState !== s || s.playerKey !== key) return;
  const lang = subtitleLanguage();
  const trailer = s.trailers.find(t => t.key === key);
  const wantSubs = !!lang && (!trailer || !trailer.lang || trailer.lang !== lang);
  let subsDone = !wantSubs;
  const pickSubtitles = (player) => {
    if (subsDone || s.player !== player) return;
    const tracks = player.getOption("captions", "tracklist");
    if (!Array.isArray(tracks) || !tracks.length) return;  // not reported yet
    subsDone = true;
    const match = tracks.find(t => (t.languageCode || "").split("-")[0].toLowerCase() === lang);
    const source = tracks.filter(t => t.is_translateable !== false)
      .sort((a, b) => (a.kind === "asr") - (b.kind === "asr"))[0];
    if (match) player.setOption("captions", "track", { languageCode: match.languageCode });
    else if (source) player.setOption("captions", "track", { languageCode: source.languageCode, translationLanguage: { languageCode: lang } });
    else player.unloadModule("captions");
  };
  s.player = new YT.Player(mount, {
    host: "https://www.youtube-nocookie.com",
    videoId: key,
    playerVars: {
      autoplay: s.playing ? 1 : 0, rel: 0, playsinline: 1,
      ...(wantSubs ? { cc_load_policy: 1, cc_lang_pref: lang, hl: lang } : {}),
    },
    events: {
      onReady: (e) => {
        if (s.player !== e.target) return;
        s.playerReady = true;
        if (s.playing) {
          try { e.target.playVideo(); } catch (err) {}
        } else if (detailsState === s) renderDetailsHero();
      },
      // The caption track list arrives once the captions module loads;
      // if it never shows up the video has no captions at all.
      onApiChange: (e) => pickSubtitles(e.target),
      onStateChange: (e) => {
        if (s.player !== e.target || detailsState !== s) return;
        // Ended: back to the banner, with the trailer cued again
        if (e.data === YT.PlayerState.ENDED) {
          s.playing = false;
          subsDone = !wantSubs;
          try { e.target.cueVideoById(key); } catch (err) {}
          renderDetailsHero();
          renderDetailsBody();
          return;
        }
        // Started by user interaction in YouTube player
        if (e.data === YT.PlayerState.PLAYING && !s.playing) {
          Object.assign(s, { playing: true, activeTrailer: key });
          renderDetailsHero();
          renderDetailsBody();
        }
        if (e.data !== YT.PlayerState.PLAYING || subsDone) return;
        pickSubtitles(e.target);
        setTimeout(() => {
          pickSubtitles(e.target);
          if (!subsDone && s.player === e.target) { subsDone = true; e.target.unloadModule("captions"); }
        }, 2500);
      },
    },
  });
}

function detailsHasBanner(s) { return !!s.data.backdrop || !s.loading; }

function renderDetailsHero() {
  if (detailsState) updatePageHeader(detailsState.data.title, detailsState.data.original_title);
  const { data: d, playing } = detailsState;
  // Built once per title, then only its parts are updated - the player
  // slot must survive re-renders (moving or re-creating an iframe
  // reloads it).
  let hero = document.getElementById("dtHero");
  if (!hero) {
    detailsBody.innerHTML = `<div class="dt-hero" id="dtHero">
        <div class="dt-media"><div class="dt-player-slot"><div id="dtPlayer"></div></div><div class="dt-media-overlay"></div></div>
        <div class="dt-hero-rest"></div>
      </div><div class="dt-body" id="dtBody"></div>`;
    hero = document.getElementById("dtHero");
  }
  const meta = [];
  if (d.rating > 0) meta.push(`<span class="rating-badge" title="${d.vote_count ? `${d.vote_count.toLocaleString()} votes on TMDB` : "TMDB rating"}">${ICONS.star}${d.rating.toFixed(1)}</span>`);
  if (d.year) {
    const end = d.media_type === "tv" && d.last_air_date ? d.last_air_date.slice(0, 4) : "";
    meta.push(`<span>${d.media_type === "tv" ? `${d.year}–${d.in_production ? "" : (end !== d.year ? end : "")}` : d.year}</span>`);
  }
  if (d.media_type === "tv" && d.seasons) meta.push(`<span>${d.seasons} season${d.seasons === 1 ? "" : "s"}</span>`);
  else if (d.runtime) meta.push(`<span>${formatRuntime(d.runtime)}</span>`);
  if (d.certification) meta.push(`<span><span class="dt-cert">${escapeHtml(d.certification)}</span></span>`);
  if (d.kind) meta.push(`<span>${escapeHtml(d.kind)}</span>`);

  const s = detailsState;
  // Once details are in, a title without a backdrop gets the branded banner.
  const hasBackdrop = detailsHasBanner(s);
  const media = hero.querySelector(".dt-media");
  const brand = media.querySelector(".brand-art");
  if (hasBackdrop && !d.backdrop && !playing) {
    if (!brand || brand.dataset.seed !== (d.title || "")) { brand?.remove(); media.insertAdjacentHTML("afterbegin", brandArt(d.title, true)); }
  } else brand?.remove();
  hero.className = `dt-hero ${hasBackdrop ? "has-backdrop" : "no-backdrop"}${playing ? " is-playing" : ""}${s.playerReady ? " player-ready" : ""}`;
  const playerSlot = hero.querySelector(".dt-player-slot");
  playerSlot.setAttribute("aria-hidden", playing ? "false" : "true");
  playerSlot.querySelector("iframe")?.setAttribute("tabindex", playing ? "0" : "-1");
  detailsModal.querySelector(".details-box").classList.toggle("has-banner", hasBackdrop);

  let overlay = "";
  if (playing) {
    overlay = `<div class="dt-trailer-header">
      <span class="dt-trailer-badge">Trailer</span>
      <button type="button" class="dt-trailer-close" data-act="close-trailer" aria-label="Close trailer" title="Close trailer">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M18 6 6 18M6 6l12 12"/></svg>
      </button>
    </div>`;
  } else if (hasBackdrop && !s.loading && s.trailers && s.trailers.length > 0) {
    overlay = `<button type="button" class="dt-hero-play" data-act="trailer" aria-label="Play trailer">
      <span class="dt-hero-play-icon">${PLAY_ICON}</span>Trailer</button>`;
  }
  const showBackdrop = !!d.backdrop && !playing;
  media.style.backgroundImage = showBackdrop ? `url('${d.backdrop.replace(/'/g, "%27")}')` : "";
  hero.querySelector(".dt-media-overlay").innerHTML = overlay;
  hero.querySelector(".dt-hero-rest").innerHTML = `
    ${d.poster ? `<img class="dt-poster" src="${escapeHtml(d.poster)}" alt="">` : `<div class="dt-poster result-poster-fallback brand-host">${brandArt(d.title)}</div>`}
    <div class="dt-info">
      <h2 class="dt-title">${escapeHtml(d.title)}</h2>
      ${d.original_title && d.original_title !== d.title ? `<div class="dt-sub">${escapeHtml(d.original_title)}</div>` : ""}
      ${meta.length ? `<div class="dt-meta">${meta.join("")}</div>` : ""}
    </div>`;
}

function titleEpisodeFiles(season) {
  const files = [];
  for (const file of libraryFileList()) {
    const identity = episodeOf(file);
    if (identity && identity.season === season) files.push({ ...identity, file });
  }
  return files;
}

function renderTitleEpisodes(s) {
  if (s.data.media_type !== "tv") return "";
  const local = libraryFileList().map(episodeOf).filter(Boolean);
  const seasons = [...new Set([...(s.data.season_list || []).map(x => x.number), ...local.map(x => x.season)])].sort((a, b) => a - b);
  if (!seasons.length) return "";
  if (!seasons.includes(s.browseSeason)) s.browseSeason = seasons.find(n => n > 0) ?? seasons[0];
  const season = s.browseSeason;
  if (!s.episodeNames?.[season]) loadEpisodeNames(season);
  const pending = !s.episodeNames?.[season] || s.episodeNames[season] === "loading";
  const known = pending ? {} : s.episodeNames[season];
  const files = titleEpisodeFiles(season);
  const numbers = new Set(Object.keys(known).map(Number));
  files.forEach(f => { for (let n = f.episode; n <= f.last; n++) numbers.add(n); });
  s.episodeChoices = [...numbers].sort((a, b) => a - b).map(number => ({ number, info: known[number] || {}, source: files.find(f => number >= f.episode && number <= f.last) }));
  const cards = s.episodeChoices.map(({ number, info, source }) => {
    const available = !!source;
    const action = available ? "Play episode" : searchEnabled ? "Search torrents" : "Not in your library";
    const combined = source && source.last > source.episode ? ` · Episodes ${source.episode}–${source.last} in one file` : "";
    return `<article class="title-episode-card">
      <button type="button" class="title-episode-action" data-act="browse-episode" data-number="${number}"${!available && !searchEnabled ? " disabled" : ""} aria-label="${escapeHtml(`${action}: ${number}. ${info.name || `Episode ${number}`}`)}">
        <div class="title-episode-art">${info.still ? `<img src="${escapeHtml(info.still)}" alt="" loading="lazy">` : `<span class="title-episode-placeholder">${PLAY_ICON}</span>`}
          <span class="title-episode-play-icon" aria-hidden="true">${PLAY_ICON}</span>
          <span class="title-episode-badge${available ? " is-available" : ""}">${available ? "In your library" : searchEnabled ? "Search torrents" : "Not in your library"}</span>
          ${info.runtime ? `<span class="title-episode-runtime">${info.runtime} min</span>` : ""}
        </div>
        <h3>${number}. ${escapeHtml(info.name || `Episode ${number}`)}</h3>
      </button>
      <p class="title-episode-overview">${escapeHtml(info.overview || (source ? "" : "Episode details are not available yet."))}</p>
      ${combined ? `<p class="title-episode-file-note">${escapeHtml(combined.slice(3))}</p>` : ""}
    </article>`;
  }).join("");
  const error = s.episodeErrors?.[season];
  const status = error ? `<div class="dt-status is-error">Couldn't load episode details. <button class="dt-link-btn" data-act="retry-episodes">Try again</button></div>`
    : pending && !cards ? `<div class="dt-status" role="status">Loading episodes…</div>`
    : !cards ? `<div class="dt-status">No episodes are listed for this season yet.</div>` : "";
  return `<section class="dt-section title-episodes" aria-label="Episodes">
    <div class="dt-section-head"><h2 class="section-label">Episodes</h2><span class="title-section-note">${s.episodeChoices.length ? `${s.episodeChoices.length} episodes` : ""}</span></div>
    <div class="dt-seasons-pick" role="group" aria-label="Choose season">${seasons.map(n => `<button type="button" class="library-chip${n === season ? " is-active" : ""}" data-act="browse-season" data-season="${n}" aria-pressed="${n === season}">${n === 0 ? "Specials" : `Season ${n}`}</button>`).join("")}</div>
    ${status}<div class="title-episode-row">${cards}</div>
  </section>`;
}

function selectTitleSeason(season) {
  const s = detailsState;
  if (!s || !Number.isInteger(season) || season < 0) return;
  s.browseSeason = season;
  history.replaceState({ ...history.state, ttSeason: season }, "", titlePageURL(s.item, s.torrent, season));
  renderDetailsBody();
}

async function playTrackerEpisode(season, episodeNumber) {
  const s = detailsState;
  if (!s) return;
  const showTitle = s.data?.original_title || s.data?.title || s.item.clean_title || s.item.title;
  const epCode = `S${String(season).padStart(2, "0")}E${String(episodeNumber).padStart(2, "0")}`;
  showToast(`Finding stream for ${epCode}…`);

  // 1. Try matching among already loaded releases
  if (Array.isArray(s.releases)) {
    const directMatch = s.releases.find(r => r.seeders > 0 && episodeMatchesRelease(r.title, season, episodeNumber));
    if (directMatch) {
      playRelease(directMatch);
      return;
    }
  }

  // 2. Query tracker specifically for this episode or season
  const queries = [
    `${showTitle} ${epCode}`,
    `${showTitle} S${String(season).padStart(2, "0")}`,
    showTitle,
  ];
  if (s.data?.title && s.data.title !== showTitle) {
    queries.push(`${s.data.title} ${epCode}`);
    queries.push(`${s.data.title} S${String(season).padStart(2, "0")}`);
  }

  for (const q of queries) {
    try {
      const res = await (releasesCache.get(q) || fetch(`/api/search?q=${encodeURIComponent(q)}&enrich=0`).then(r => r.json()));
      releasesCache.set(q, Promise.resolve(res));
      const list = (res.results || []).filter(r => releaseMatches(r, s.data));
      const epMatch = list.find(r => r.seeders > 0 && episodeMatchesRelease(r.title, season, episodeNumber));
      if (epMatch) {
        playRelease(epMatch);
        return;
      }
      const seasonMatch = list.find(r => r.seeders > 0 && seasonMatchesRelease(r.title, season));
      if (seasonMatch) {
        playRelease(seasonMatch);
        return;
      }
    } catch (e) {}
  }

  // 3. Fallback: best seeded release or report none
  const best = primaryRelease();
  if (best) {
    playRelease(best);
  } else {
    showToast(`No streams found for ${epCode}`, true);
  }
}

function findTitleEpisode(number) {
  const s = detailsState;
  const episode = s?.episodeChoices?.find(e => e.number === number);
  if (!episode) return;
  if (episode.source) {
    playLibraryFrom(episode.source.file);
    return;
  }
  const season = s.browseSeason != null ? s.browseSeason : 1;
  s.releaseEpisode = `S${String(season).padStart(2, "0")}E${String(number).padStart(2, "0")}`;
  s.showDownloads = true;
  loadReleases(`${s.data?.original_title || s.data?.title || s.item.clean_title || s.item.title} ${s.releaseEpisode}`, detailsRequestId, true);
  document.getElementById("titleDownloads")?.scrollIntoView({ block: "start", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
  playTrackerEpisode(season, number);
}

function personPageURL(person, filter = 'all') {
  const url = titlePageURL({}, null, null);
  url.searchParams.delete('title');
  url.searchParams.set('person', person.id);
  url.searchParams.set('name', person.name || 'Cast & crew');
  if (['movie', 'tv'].includes(filter)) url.searchParams.set('filter', filter);
  return url;
}

function personTitles(s) {
  return (s.data?.titles || []).map((item, index) => ({ item, index }))
    .filter(({ item }) => s.filter === 'all' || item.mediaType === s.filter);
}

function renderPersonPage() {
  const s = personState;
  if (!s) return;
  const p = s.data || s.person;
  updatePageHeader(p.name, "Cast & crew");
  const titles = personTitles(s);
  const filters = [['all', 'All'], ['movie', 'Movies'], ['tv', 'TV Shows']];
  const cards = titles.map(({ item, index }) => {
    const title = { title: item.title, tmdb_id: item.tmdbId, media_type: item.mediaType };
    const local = libraryItems.some(t => t.tmdb_id === item.tmdbId && t.media_type === item.mediaType);
    const saved = favorites.some(t => t.tmdb_id === item.tmdbId && t.media_type === item.mediaType);
    return `<a class="person-title-card" href="${escapeHtml(titlePageURL(title, null, null))}" data-act="person-title" data-index="${index}">
      <div class="person-title-art"><span class="person-poster-fallback" aria-hidden="true">${ICONS.play}</span>${item.poster ? `<img src="${escapeHtml(item.poster)}" alt="" loading="lazy">` : ''}${saved ? `<span class="person-favorite" aria-label="In Favorites">${ICONS.heart}</span>` : ''}${local ? '<span class="person-library-badge">In your library</span>' : ''}</div>
      <h3>${escapeHtml(item.title)}</h3><p>${escapeHtml([item.year, item.mediaType === 'tv' ? 'TV show' : 'Movie', item.rating ? `★ ${item.rating}` : null].filter(Boolean).join(' · '))}</p>
    </a>`;
  }).join('');
  detailsBody.innerHTML = `<div class="dt-body person-page">
    <div class="person-top-bar">
      <header class="person-header"><div class="person-photo">${p.photo ? `<img src="${escapeHtml(p.photo)}" alt="">` : ''}<span aria-hidden="true">${escapeHtml((p.name || '?').charAt(0))}</span></div>
        <div><p class="person-eyebrow">Cast &amp; crew</p><h1>${escapeHtml(p.name || 'Cast & crew')}</h1>${s.data ? `<p>${s.data.titles.length} films and TV shows</p>` : ''}</div></header>
      <div class="person-filters" role="group" aria-label="Filter titles">${filters.map(([value, label]) => `<button type="button" class="library-chip${s.filter === value ? ' is-active' : ''}" data-act="person-filter" data-filter="${value}" aria-pressed="${s.filter === value}">${label}</button>`).join('')}</div>
    </div>
    <div class="person-content">
      ${s.loading ? '<p class="dt-status" role="status">Loading films and TV shows…</p>' : s.error ? `<div class="dt-status is-error" role="alert">${escapeHtml(s.error)} <button class="dt-link-btn" data-act="person-retry">Try again</button></div>` : !cards ? '<p class="dt-status">No titles are listed here yet.</p>' : `<div class="person-title-grid">${cards}</div>`}
    </div>
  </div>`;
  detailsBody.querySelectorAll('.person-page img').forEach(img => {
    const fallback = () => { img.hidden = true; };
    img.addEventListener('error', fallback);
    img.addEventListener('load', () => { img.hidden = false; });
  });
}

async function openPerson(person, { fromHistory = false, filter = 'all' } = {}) {
  if (!detailsState && !personState) {
    titleReturnFocus = document.activeElement;
    titleWorkspaceScroll = window.scrollY;
    if (!fromHistory) history.replaceState({ ...history.state, ttWorkspace: true, ttScroll: titleWorkspaceScroll }, '', location.href);
  } else if (!fromHistory) history.replaceState({ ...history.state, ttScroll: window.scrollY }, '', location.href);
  if (!fromHistory) history.pushState({ ttPerson: person, ttDepth: (history.state?.ttDepth || 0) + 1 }, '', personPageURL(person, filter));
  const requestId = ++detailsRequestId;
  destroyTrailerPlayer(detailsState);
  detailsState = null;
  const state = personState = { person, filter: ['movie', 'tv'].includes(filter) ? filter : 'all', loading: true, data: null, error: '' };
  detailsModal.hidden = false;
  detailsModal.classList.add('is-open');
  detailsModal.setAttribute('aria-label', 'Cast & crew');
  document.body.classList.add('has-title-page');
  setDetailsBackVisible(true);
  document.title = `${person.name || 'Cast & crew'} · Torrent Tube`;
  renderPersonPage();
  window.scrollTo({ top: fromHistory ? history.state?.ttScroll || 0 : 0 });
  detailsModal.querySelector('.details-box').focus({ preventScroll: true });
  try {
    let data = personCache.get(person.id);
    if (!data) {
      const response = await fetch(`/api/person?id=${encodeURIComponent(person.id)}`);
      data = await response.json();
      if (data.error) throw new Error(data.error);
      if (!response.ok) throw new Error('Could not load films and TV shows.');
      personCache.set(person.id, data);
    }
    if (detailsRequestId !== requestId || personState !== state) return;
    state.data = data;
    document.title = `${data.name || person.name} · Torrent Tube`;
  } catch (e) {
    if (detailsRequestId !== requestId || personState !== state) return;
    state.error = e.message || 'Could not load films and TV shows.';
  }
  state.loading = false;
  renderPersonPage();
  if (fromHistory) window.scrollTo({ top: history.state?.ttScroll || 0 });
}

function renderTitleFolderPicker(s) {
  return `<div class="title-folder-picker">
    <button type="button" class="title-folder-trigger" data-act="folder-toggle" aria-label="Download folder: ${escapeHtml(s.category || 'Choose folder')}" aria-haspopup="menu" aria-expanded="false" aria-controls="titleFolderMenu">
      <span>${escapeHtml(s.category || 'Choose folder')}</span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>
    </button>
    <div class="title-folder-menu" id="titleFolderMenu" role="menu" aria-label="Download folder" hidden>${currentCategories.map(c => `<button type="button" role="menuitemradio" aria-checked="${c === s.category}" tabindex="-1" data-act="folder-choice" data-category="${escapeHtml(c)}"><span>${escapeHtml(c)}</span>${c === s.category ? ICONS.check : ''}</button>`).join('')}</div>
  </div>`;
}

function positionTitleFolderPicker(trigger, menu) {
  if (!trigger || !menu) return;
  menu.classList.remove('open-up');
  menu.style.left = '';
  menu.style.right = '';
  menu.style.maxHeight = '';
  const triggerRect = trigger.getBoundingClientRect();
  const viewportWidth = window.innerWidth || document.documentElement.clientWidth;
  const viewportHeight = window.innerHeight || document.documentElement.clientHeight;
  const gutter = 12;
  const menuRect = menu.getBoundingClientRect();
  // Prefer the trigger's right edge, then flip and clamp to the viewport.
  let left = triggerRect.right - menuRect.width;
  if (left < gutter) left = triggerRect.left;
  left = Math.max(gutter, Math.min(left, viewportWidth - menuRect.width - gutter));
  const pickerRect = trigger.parentElement.getBoundingClientRect();
  menu.style.left = `${left - pickerRect.left}px`;
  menu.style.right = 'auto';
  const spaceBelow = viewportHeight - triggerRect.bottom - gutter - 8;
  const spaceAbove = triggerRect.top - gutter - 8;
  const opensUp = spaceBelow < menuRect.height && spaceAbove > spaceBelow;
  menu.classList.toggle('open-up', opensUp);
  menu.style.maxHeight = `${Math.max(0, Math.min(280, opensUp ? spaceAbove : spaceBelow))}px`;
}

function closeTitleFolderPicker(restoreFocus = false) {
  const menu = detailsBody.querySelector('.title-folder-menu:not([hidden])');
  if (!menu) return;
  menu.hidden = true;
  menu.classList.remove('open-up');
  const trigger = menu.parentElement.querySelector('.title-folder-trigger');
  if (trigger) trigger.setAttribute('aria-expanded', 'false');
  if (restoreFocus && trigger) trigger.focus({ preventScroll: true });
}

function openTitleFolderPicker(trigger, last = false) {
  const menu = trigger.parentElement.querySelector('.title-folder-menu');
  if (!menu) return;
  menu.hidden = false;
  trigger.setAttribute('aria-expanded', 'true');
  positionTitleFolderPicker(trigger, menu);
  const options = [...menu.querySelectorAll('[role="menuitemradio"]')];
  (last ? options.at(-1) : menu.querySelector('[aria-checked="true"]') || options[0])?.focus({ preventScroll: true });
}

function renderDetailsBody() {
  const body = document.getElementById("dtBody");
  if (!body || !detailsState) return;
  const s = detailsState, d = s.data, item = s.item;

  const focused = body.contains(document.activeElement) ? document.activeElement.closest("[data-act]") : null;
  const focusKey = focused ? { ...focused.dataset } : null;
  const folderWasOpen = !!body.querySelector('.title-folder-menu:not([hidden])');
  // --- actions: Play in <player>, Download + folder. The trailer plays
  // from the banner's centre button; a title without a banner gets a
  // button here instead. ---
  const actions = [];
  const seasonFile = (d.media_type === "tv" && s.browseSeason != null ? titleEpisodeFiles(s.browseSeason).sort((a,b) => a.episode - b.episode)[0]?.file : null) || libraryFileList()[0];
  const playable = s.library ? seasonFile : (s.torrent || primaryRelease() || (s.releases === "loading" || s.loading));
  const playerId = currentPlayer();
  actions.push(`<div class="play-split">
    <button type="button" class="btn-primary btn-pill play-main" data-act="play"${!playable ? " disabled" : ""}>${playerLogo(playerId)}<span class="player-action-label">${PLAYERS[playerId].canOpen ? "Play in" : "Copy link for"} ${escapeHtml(PLAYERS[playerId].name)}</span></button>
    <button type="button" class="btn-primary btn-pill play-more" data-act="pick-player" title="Choose the player" aria-label="Choose the player">${CHEVRON_DOWN}</button>
  </div>`);
  const saved = titleFavorites(s).length > 0;
  actions.push(`<button type="button" class="btn-secondary dt-favorite${saved ? " is-saved" : ""}" data-act="favorite" aria-pressed="${saved}" title="${saved ? "Remove from Favorites" : "Add to Favorites"}">${saved ? ICONS.heartFilled : ICONS.heart}${saved ? "Unfavorite" : "Favorite"}</button>`);
  if (!detailsHasBanner(s) && !s.playing && !s.loading) {
    if (s.trailers && s.trailers.length > 0) {
      actions.push(`<button type="button" class="btn-secondary" data-act="trailer">${PLAY_ICON}Trailer</button>`);
    }
  }
  if (s.library) {
    if (!s.category) s.category = currentCategories.includes(s.library.category) ? s.library.category : categoryForKind(d.kind) || getDefaultCategory();
    if (searchEnabled) actions.push(`<button type="button" class="btn-secondary" data-act="find-versions">${ICONS.download}Search torrents</button>`);
    const where = (s.library.versions || []).length > 1 ? `${s.library.versions.length} versions` : s.library.category;
    actions.push(`<span class="dt-status-pill">In your library${where ? ` · ${escapeHtml(where)}` : ""}</span>`);
  } else if (s.torrent) {
    const t = s.torrent;
    const done = t.state === "finished" || t.state === "seeding";
    actions.push(`<span class="dt-status-pill">${done ? "Downloaded" : `Downloading · ${t.progress}%`}${t.category ? ` · ${escapeHtml(t.category)}` : ""}</span>`);
  } else {
    const best = primaryRelease();
    // Re-picked on every render until the user chooses - the first render
    // happens before TMDB says whether it's a movie, show or cartoon.
    if (!s.categoryChosen) {
      const preferred = item.suggested_category || categoryForKind(d.kind);
      s.category = currentCategories.includes(preferred) ? preferred : getDefaultCategory();
    }
    const added = best && s.added.has(releaseKey(best));
    const label = !best
      ? (s.releases === "loading" || s.loading ? "Finding releases…" : "No releases found")
      : added ? "Added" : "Download";
    const bestMeta = best ? [releaseTags(best.title).find(t => t.res)?.label, best.size_label].filter(Boolean).join(" · ") : "";
    actions.push(`<button type="button" class="btn-secondary" data-act="download-best"${!best || added ? " disabled" : ""}>${added ? ICONS.check : ICONS.download}${label}${best && !added && bestMeta ? ` <span class="dt-download-meta">${escapeHtml(bestMeta)}</span>` : ""}</button>`);
    actions.push(renderTitleFolderPicker(s));
  }

  // --- overview + facts ---
  const facts = [];
  // Minor facts are dropped on phones, where the list would otherwise
  // push cast and releases a whole screen down.
  const fact = (k, v, minor) => { if (v) facts.push(`<div${minor ? ` class="dt-minor"` : ""}><span class="k">${escapeHtml(k)}:</span> ${v}</div>`); };
  fact("Genres", escapeHtml((d.genres || []).join(", ")));
  (d.facts || []).forEach(f => fact(f.label, escapeHtml(f.names.join(", "))));
  if (d.next_episode) fact("Next episode", escapeHtml(`S${d.next_episode.season}E${d.next_episode.episode} · ${formatDate(d.next_episode.date)}`));
  else if (d.media_type === "tv" && d.status) fact("Status", escapeHtml(d.status));
  if (d.media_type === "movie" && d.release_date) fact("Released", escapeHtml(formatDate(d.release_date)), true);
  fact("Country", escapeHtml((d.countries || []).slice(0, 2).join(", ")));
  if (d.original_language) fact("Language", escapeHtml(languageName(d.original_language)), true);
  fact("Collection", escapeHtml(d.collection || ""), true);
  if (d.budget || d.revenue) fact("Budget / box office", escapeHtml([d.budget ? formatMoney(d.budget) : "?", d.revenue ? formatMoney(d.revenue) : "?"].join(" / ")), true);
  const links = [];
  if (d.imdb_id) links.push(`<a href="https://www.imdb.com/title/${encodeURIComponent(d.imdb_id)}/" target="_blank" rel="noopener">IMDb</a>`);
  if (d.tmdb_url) links.push(`<a href="${escapeHtml(d.tmdb_url)}" target="_blank" rel="noopener">TMDB</a>`);
  if (item.details_link) links.push(`<a href="${escapeHtml(item.details_link)}" target="_blank" rel="noopener">Tracker</a>`);
  if (d.homepage) links.push(`<a href="${escapeHtml(d.homepage)}" target="_blank" rel="noopener">Website</a>`);
  if (links.length) fact("Links", links.join(" · "));

  let overview;
  if (s.loading) overview = `<div class="dt-skeleton" style="width:95%"></div><div class="dt-skeleton" style="width:88%"></div><div class="dt-skeleton" style="width:60%"></div>`;
  else overview = `${d.tagline ? `<p class="dt-tagline">${escapeHtml(d.tagline)}</p>` : ""}
    ${d.overview ? `<p class="dt-overview">${escapeHtml(d.overview)}</p><button type="button" class="dt-link-btn" data-act="more" hidden>More</button>` : ""}
    ${s.error ? `<div class="dt-status is-error">${escapeHtml(s.error)}</div>` : ""}`;

  // --- cast & crew ---
  const people = (d.people || []).map(p => `
    <a class="dt-person" href="${escapeHtml(personPageURL(p))}" data-act="person" data-person-id="${escapeHtml(p.id)}" title="${escapeHtml(p.name)}">
      ${p.photo ? `<img class="dt-avatar" src="${escapeHtml(p.photo)}" alt="" loading="lazy">` : `<div class="dt-avatar">${escapeHtml((p.name || "?").charAt(0))}</div>`}
      <div class="dt-person-name">${escapeHtml(p.name)}</div>
      ${p.role ? `<div class="dt-person-role">${escapeHtml(p.role)}</div>` : ""}
    </a>`).join("");

  // --- releases ---
  let releases = "";
  if (s.releases === "loading") {
    releases = `<div class="dt-status">Searching the tracker…</div>`;
  } else if (Array.isArray(s.releases) && s.releases.length) {
    releases = `<div class="dt-releases">${s.releases.map((r, i) => {
      const key = releaseKey(r);
      const tags = releaseTags(r.title).map(t => `<span class="dt-tag${t.res ? " is-res" : ""}">${escapeHtml(t.label)}</span>`).join("");
      const isCurrent = item.size_label && key === releaseKey(item);
      const added = s.added.has(key);
      return `<div class="dt-release${isCurrent ? " is-current" : ""}">
        <div class="dt-release-main">
          <div class="dt-release-tags">${tags}${isCurrent ? `<span class="dt-tag">This release</span>` : ""}</div>
          <div class="dt-release-title" title="${escapeHtml(r.title)}">${escapeHtml(r.title)}</div>
        </div>
        <div class="dt-release-stats">${escapeHtml(r.size_label)}<br><span class="seeders">${r.seeders}</span> seeds</div>
        <button type="button" class="action-btn" data-act="play-release" data-index="${i}" title="Play this release in ${escapeHtml(PLAYERS[playerId].name)}">${ICONS.play}</button>
        <button type="button" class="action-btn" data-act="download-release" data-index="${i}" title="Download this release"${added ? " disabled" : ""}>${added ? ICONS.check : ICONS.download}</button>
      </div>`;
    }).join("")}</div>`;
  } else if (Array.isArray(s.releases) && searchEnabled) {
    releases = s.releaseError ? `<div class="dt-status is-error">${escapeHtml(s.releaseError)} <button type="button" class="dt-link-btn" data-act="retry-releases">Try again</button></div>`
      : `<div class="dt-status">No releases of this title found on the tracker.</div>`;
  }
  const releasesControls = s.library ? renderTitleFolderPicker(s) : "";
  const releasesHead = searchEnabled ? `<div class="dt-section-head"><div class="section-label">Releases${Array.isArray(s.releases) && s.releases.length ? ` · ${s.releases.length}` : ""}</div>
    ${releasesControls ? `<div class="dt-releases-controls">${releasesControls}</div>` : ""}</div>` : "";

  const downloadReleases = releases;
  // Keep exact version/file controls for the server's storage workflow.
  let storedFiles = "";
  if (s.library) {
    const files = libraryFileList();
    storedFiles = !s.libraryFiles ? `<div class="dt-status" role="status">Reading the folder…</div>` : files.length ? `<div class="dt-files">${files.map((f, i) => `
      <div class="dt-file"><span class="title-file-type">${escapeHtml(f.name.split('.').pop().toUpperCase())}</span><div class="dt-file-name">${escapeHtml(f.name)}</div>
      <div class="dt-file-size">${formatBytes(f.size)}</div>
      <button type="button" class="action-btn" data-act="play-file" data-index="${i}" title="Play this exact file in ${escapeHtml(PLAYERS[playerId].name)}" aria-label="Play ${escapeHtml(f.name)}">${ICONS.play}</button></div>`).join("")}</div>`
      : `<div class="dt-status">No video files were found in this folder. Try refreshing your library.</div>`;
  }
  const episodeSection = renderTitleEpisodes(s);
  const downloads = `<details class="dt-section title-downloads" id="titleDownloads"${s.showDownloads || !s.library ? " open" : ""}>
    <summary><h2 class="section-label">Downloads &amp; versions${s.releaseEpisode ? ` · ${escapeHtml(s.releaseEpisode)}` : ""}</h2></summary>
    ${s.library ? `<div class="title-storage-info"><div class="title-storage-heading"><span class="title-storage-icon">${ICONS.check}</span><div><h3>Available on your server</h3><p>${escapeHtml(s.library.category || "Library")}${s.library.versions?.length > 1 ? ` · ${s.library.versions.length} versions` : ""} · ${libraryFileList().length} video files</p></div></div>${storedFiles ? `<details class="title-file-browser"${s.showStoredFiles || (s.libraryFiles && libraryFileList().length <= 3) ? " open" : ""}><summary><span>Browse files</span><span class="title-file-count">${libraryFileList().length}</span></summary>${storedFiles}</details>` : ""}</div>` : ""}
    ${downloadReleases ? `<div class="title-tracker-releases">${releasesHead}${downloadReleases}</div>` : searchEnabled && s.library ? `<p class="dt-status">Search torrents for a different quality or another season. <button type="button" class="dt-link-btn" data-act="find-versions">Search torrents</button></p>` : ""}
    <p class="title-storage-note">Downloaded files are added to your library.</p>
  </details>`;

  // --- more like this ---
  const recs = (d.recommendations || []).map((r, i) => `
    <button type="button" class="dt-rec" data-act="rec" data-index="${i}" title="${escapeHtml(r.title)}">
      <img src="${escapeHtml(r.poster)}" alt="" loading="lazy">
      <div class="dt-rec-title">${escapeHtml(r.title)}</div>
      <div class="dt-rec-year">${escapeHtml(r.year || "")}${r.rating > 0 ? ` · ★ ${r.rating.toFixed(1)}` : ""}</div>
    </button>`).join("");

  body.innerHTML = `
    <div class="dt-actions">${actions.join("")}</div>
    <div class="title-overview">${overview}</div>
    ${episodeSection}
    ${people ? `<section class="dt-section"><div class="dt-section-head"><h2 class="section-label">Cast &amp; crew</h2></div><div class="dt-row">${people}</div></section>` : ""}
    ${facts.length ? `<section class="dt-section"><div class="dt-section-head"><h2 class="section-label">Information</h2></div><div class="dt-facts">${facts.join("")}</div></section>` : ""}
    ${downloads}
    ${recs ? `<section class="dt-section"><div class="dt-section-head"><h2 class="section-label">More like this</h2></div><div class="dt-row">${recs}</div></section>` : ""}
  `;
  const storage = document.getElementById("titleDownloads");
  storage.addEventListener("toggle", () => { if (detailsState === s && storage.isConnected) s.showDownloads = storage.open; });
  const fileBrowser = body.querySelector(".title-file-browser");
  fileBrowser?.addEventListener("toggle", () => { if (detailsState === s && fileBrowser.isConnected) s.showStoredFiles = fileBrowser.open; });

  if (folderWasOpen) {
    const trigger = body.querySelector('.title-folder-trigger');
    if (trigger) openTitleFolderPicker(trigger);
  }
  if (focusKey?.act) {
    const selector = Object.entries(focusKey).map(([key, value]) => `[data-${key.replace(/[A-Z]/g, c => `-${c.toLowerCase()}`)}="${CSS.escape(value)}"]`).join("");
    body.querySelector(selector)?.focus({ preventScroll: true });
  }
  // Only offer "More" when the clamp actually cut something off.
  const overviewEl = body.querySelector(".dt-overview");
  const moreBtn = body.querySelector('[data-act="more"]');
  if (overviewEl && moreBtn && overviewEl.scrollHeight > overviewEl.clientHeight + 2) moreBtn.hidden = false;
  // A dead profile photo falls back to the initial, same as having none.
  body.querySelectorAll("img.dt-avatar").forEach(img => img.addEventListener("error", () => {
    const div = document.createElement("div");
    div.className = "dt-avatar";
    div.textContent = (img.closest(".dt-person").title || "?").charAt(0);
    img.replaceWith(div);
  }));
}

async function downloadRelease(release) {
  const s = detailsState;
  const key = releaseKey(release);
  s.added.add(key);
  renderDetailsBody();
  try {
    const data = await postSearchResult(release, s.category);
    if (data.error) throw new Error(data.error);
    showToast(`"${s.data.title || release.title}" added to ${s.category}`);
    refresh();
  } catch (e) {
    s.added.delete(key);
    showToast(e.message || "Couldn't add this torrent", true);
    if (detailsState === s) renderDetailsBody();
  }
}

detailsBody.addEventListener("click", (e) => {
  const el = e.target.closest("[data-act]");
  if (!el) return;
  // Keep normal link behavior for new tabs and copied links.
  if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
  if (el.dataset.act === 'person' && detailsState) {
    e.preventDefault();
    const person = (detailsState.data.people || []).find(p => String(p.id) === el.dataset.personId);
    if (person) openPerson(person);
    return;
  }
  if (personState) {
    if (el.dataset.act === 'person-filter') {
      personState.filter = el.dataset.filter;
      history.replaceState({ ...history.state, ttScroll: window.scrollY }, '', personPageURL(personState.person, personState.filter));
      renderPersonPage();
      detailsBody.querySelector(`[data-filter="${personState.filter}"]`)?.focus({ preventScroll: true });
    } else if (el.dataset.act === 'person-title') {
      e.preventDefault();
      const item = personState.data.titles[Number(el.dataset.index)];
      if (item) openDetails({ title: item.title, clean_title: item.title, tmdb_id: item.tmdbId, media_type: item.mediaType, poster: item.poster, rating: item.rating });
    } else if (el.dataset.act === 'person-retry') openPerson(personState.person, { fromHistory: true, filter: personState.filter });
    return;
  }
  if (!detailsState) return;
  const s = detailsState;
  switch (el.dataset.act) {
    case "folder-toggle":
      if (el.getAttribute('aria-expanded') === 'true') closeTitleFolderPicker(true);
      else openTitleFolderPicker(el);
      break;
    case "folder-choice":
      s.category = el.dataset.category;
      s.categoryChosen = true;
      closeTitleFolderPicker(true);
      renderDetailsBody();
      break;
    case "trailer":
      if (s.trailers && s.trailers.length) playTrailer(s.activeTrailer || s.trailers[0].key);
      break;
    case "close-trailer":
      closeTrailer();
      break;
    case "download-best": { const best = primaryRelease(); if (best) downloadRelease(best); break; }
    case "play":
      if (s.library) {
        const eps = libraryEpisodes();
        const chosen = titleEpisodeFiles(s.browseSeason).sort((a,b) => a.episode - b.episode)[0]?.file;
        playLibraryFrom(chosen || (eps ? eps[0].file : libraryFileList()[0]));
      } else if (s.torrent) {
        playRelease(null);
      } else {
        const best = primaryRelease();
        if (best) {
          playRelease(best);
        } else if (s.data?.media_type === "tv") {
          playTrackerEpisode(s.browseSeason != null ? s.browseSeason : 1, 1);
        } else {
          showToast("Searching for streams…");
        }
      }
      break;
    case "play-episode": playLibraryFrom(libraryEpisodes()[Number(el.dataset.index)].file); break;
    case "browse-season": selectTitleSeason(Number(el.dataset.season)); break;
    case "browse-episode": findTitleEpisode(Number(el.dataset.number)); break;
    case "retry-episodes": delete s.episodeNames[s.browseSeason]; delete s.episodeErrors[s.browseSeason]; renderDetailsBody(); break;
    case "retry-releases": loadReleases(s.releaseEpisode ? `${s.data.original_title || s.data.title} ${s.releaseEpisode}` : s.data.title, detailsRequestId, true); break;
    case "find-versions": s.showDownloads = true; s.releaseEpisode = null; loadReleases(s.data.title, detailsRequestId, true); break;
    case "play-release": playRelease(s.releases[Number(el.dataset.index)]); break;
    case "pick-player": openPlayerPicker(); break;
    case "favorite": toggleFavorite(s); break;
    case "download-release": downloadRelease(s.releases[Number(el.dataset.index)]); break;
    case "more": {
      const overviewEl = detailsBody.querySelector(".dt-overview");
      const expanded = overviewEl.classList.toggle("is-expanded");
      el.textContent = expanded ? "Less" : "More";
      break;
    }
    case "rec": {
      const r = s.data.recommendations[Number(el.dataset.index)];
      openDetails({ title: r.title, clean_title: r.title, tmdb_id: r.tmdb_id, media_type: r.media_type, poster: r.poster, rating: r.rating }, null, { push: true });
      break;
    }
  }
});
detailsBody.addEventListener('keydown', e => {
  const picker = e.target.closest('.title-folder-picker');
  if (!picker) return;
  const trigger = picker.querySelector('.title-folder-trigger');
  const menu = picker.querySelector('.title-folder-menu');
  if (e.key === 'Escape' && !menu.hidden) {
    e.preventDefault(); e.stopPropagation(); closeTitleFolderPicker(true); return;
  }
  if (e.key === 'Tab') { closeTitleFolderPicker(); return; }
  if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(e.key)) return;
  e.preventDefault();
  if (menu.hidden) { openTitleFolderPicker(trigger, e.key === 'ArrowUp' || e.key === 'End'); return; }
  const options = [...menu.querySelectorAll('[role="menuitemradio"]')];
  const index = options.indexOf(document.activeElement);
  const next = e.key === 'Home' ? 0 : e.key === 'End' ? options.length - 1
    : (index + (e.key === 'ArrowDown' ? 1 : -1) + options.length) % options.length;
  options[next]?.focus({ preventScroll: true });
});
document.addEventListener('click', e => {
  if (!e.target.closest('.title-folder-picker')) closeTitleFolderPicker();
});
window.addEventListener('resize', () => {
  const menu = detailsBody.querySelector('.title-folder-menu:not([hidden])');
  if (menu) positionTitleFolderPicker(menu.parentElement.querySelector('.title-folder-trigger'), menu);
}, { passive: true });
window.addEventListener('scroll', () => {
  const menu = detailsBody.querySelector('.title-folder-menu:not([hidden])');
  if (menu) positionTitleFolderPicker(menu.parentElement.querySelector('.title-folder-trigger'), menu);
}, { passive: true });
detailsBack.addEventListener("click", detailsGoBack);
// Keeps the Discover panel's fixed height in sync with the real (sticky)
// header height, same pattern Music Tube uses for its queue panel.
function syncTopBarHeight() {
  document.documentElement.style.setProperty("--topbar-h", `${topBarEl.offsetHeight}px`);
}
syncTopBarHeight();
window.addEventListener("resize", syncTopBarHeight);
if (window.ResizeObserver) new ResizeObserver(syncTopBarHeight).observe(topBarEl);

// ---------- My library ----------
// What is already in the download folders, as the server lists it in
// /api/library: one card per title (copies merged as versions), matched on
// TMDB, sorted into Movies, TV Shows and Cartoons - the same as the apps.
const libraryPanel = document.getElementById("libraryPanel");
const libraryHeader = libraryPanel ? libraryPanel.querySelector(".panel-header") : null;
function updateLibraryHeaderStickyState() {
  if (!libraryHeader || libraryPanel.hidden) return;
  const topBarH = topBarEl ? topBarEl.offsetHeight : 60;
  const rect = libraryHeader.getBoundingClientRect();
  const isStuck = rect.top <= topBarH;
  libraryHeader.classList.toggle("is-stuck", isStuck);
}
window.addEventListener("scroll", updateLibraryHeaderStickyState, { passive: true });
window.addEventListener("resize", updateLibraryHeaderStickyState, { passive: true });

const libraryChips = document.getElementById("libraryChips");
const libraryKinds = document.getElementById("libraryKinds");
const libraryKindsSelect = document.getElementById("libraryKindsSelect");
const libraryFilter = document.getElementById("libraryFilter");
const libraryGrid = document.getElementById("libraryGrid");
const libraryNote = document.getElementById("libraryNote");
const layoutEl = document.getElementById("layout");
const LIBRARY_KINDS = [["movie", "Movies"], ["tv", "TV Shows"], ["cartoon", "Cartoons"]];
let libraryItems = [], libraryPending = 0, librarySection = null, libraryTimer = null, libraryLoaded = false;
// Favorites: the server keeps one list for the apps and this page.
let favorites = [];

function libraryShown() {
  try { return localStorage.getItem("showLibrary") !== "0"; } catch (e) { return true; }
}

async function loadFavorites() {
  try {
    const d = await fetch("/api/favorites").then(r => r.json());
    if (JSON.stringify(favorites) === JSON.stringify(d.items || [])) return;
    favorites = d.items || [];
  } catch (e) { return; }
  refreshFavoriteBadges();
  renderLibrary();
  if (detailsState) renderDetailsBody();
}

// What a title shows without a poster or banner: the play mark and the Top
// Shelf rings on one of a few deep brand colors, picked from the title - the
// same hash and colors as the apps (BrandPlaceholder), so a title keeps its
// color everywhere.
const BRAND_PALETTES = [
  ["#1a3d85", "#08122e"], ["#452985", "#120a2e"], ["#0d5c66", "#051a21"],
  ["#7a2154", "#26081a"], ["#854d14", "#2b1405"], ["#1f6138", "#081c0f"],
];
function brandPaletteIndex(seed) {
  let hash = 2166136261;  // FNV-1a over the UTF-8 bytes
  for (const byte of new TextEncoder().encode(seed || "")) hash = Math.imul(hash ^ byte, 16777619) >>> 0;
  return hash % BRAND_PALETTES.length;
}
function brandArt(seed, wide = false) {
  const [a, b] = BRAND_PALETTES[brandPaletteIndex(seed)];
  // A banner keeps its centre for the trailer button and its left for the
  // title: the rings and the mark sit to the right.
  const w = wide ? 320 : 200, h = wide ? 180 : 300, cx = wide ? w * 0.74 : w / 2, cy = h / 2;
  const side = Math.min(w, h), step = side * 0.38;
  const rings = Math.max(1, Math.ceil(2 * Math.hypot(Math.max(cx, w - cx), h / 2) / step));
  let circles = "";
  for (let i = 1; i <= rings; i++) circles += `<circle cx="${cx}" cy="${cy}" r="${((step * i + side * 0.2) / 2).toFixed(1)}"/>`;
  const mh = side * (wide ? 0.16 : 0.2), mw = mh * 91 / 102, sw = mw * 10.4 / 91, x = cx + mh * 0.05;
  const mark = `M${(x - mw / 2 + sw / 2).toFixed(1)} ${(cy - mh / 2 + sw / 2).toFixed(1)}V${(cy + mh / 2 - sw / 2).toFixed(1)}L${(x + mw / 2 - sw / 2).toFixed(1)} ${cy}Z`;
  return `<div class="brand-art" data-seed="${escapeHtml(seed || "")}" style="background:linear-gradient(135deg,${a},${b})" aria-hidden="true">
    <svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid slice"><g fill="none" stroke="#fff" stroke-opacity=".07" stroke-width="${(side * 0.035).toFixed(1)}">${circles}</g>
    <path d="${mark}" fill="none" stroke="#fff" stroke-opacity="${wide ? 0.5 : 0.9}" stroke-width="${sw.toFixed(1)}" stroke-linejoin="round"/></svg></div>`;
}

// The heart in a poster's top right corner, shown only on favorites (as
// in the apps). Cards carry their id, so a change only flips a class.
const FAVORITE_BADGE = `<span class="fav-badge" aria-label="In Favorites">${ICONS.heartFilled}</span>`;
function isFavorite(id) { return favorites.some(f => f.id === id); }
function refreshFavoriteBadges() {
  const ids = new Set(favorites.map(f => f.id));
  document.querySelectorAll("[data-fav-id]").forEach(el => el.classList.toggle("is-favorite", ids.has(el.dataset.favId)));
}

async function sendFavorites(path, body) {
  try {
    const res = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    const d = await res.json();
    if (!res.ok) throw new Error(d.error || "Couldn't save favorites");
    favorites = d.items || [];
  } catch (e) { showToast(e.message || "Couldn't reach the server", true); }
  refreshFavoriteBadges();
  renderLibrary();
  if (detailsState) renderDetailsBody();
}

// The same id the apps give a title (MediaItem.id), so a heart set in one
// place shows in all of them: the library folder, else the release.
function favoriteId(s) {
  if (s.library) return s.library.id;
  const item = s.item;
  if (item.download_link || item.magnet) return item.download_link ?? item.magnet;
  const id = s.data?.tmdb_id || item.tmdb_id, type = s.data?.media_type || item.media_type;
  return id && type ? `tmdb:${type}:${id}` : item.title;
}

function favoriteEntry(s) {
  const item = s.item, d = s.data || {};
  const type = d.media_type || item.media_type || (s.library && s.library.kind === "tv" ? "tv" : "movie");
  const kind = s.library ? s.library.kind : d.kind === "Cartoon" ? "cartoon" : type === "tv" ? "tv" : "movie";
  const entry = {
    id: favoriteId(s), title: s.library ? s.library.name : item.title,
    clean_title: d.title || item.clean_title || item.title, poster: item.poster || d.poster,
    tmdb_id: d.tmdb_id || item.tmdb_id, media_type: type, kind, added_at: Date.now() / 1000,
  };
  if (s.library) entry.source_override = s.library.is_torrent ? { id: s.library.id } : { path: s.library.id };
  else Object.assign(entry, { magnet: item.magnet, download_link: item.download_link });
  return entry;
}

function titleFavorites(s) {
  const entry = favoriteEntry(s);
  return favorites.filter(f => f.id === entry.id || (entry.tmdb_id && f.tmdb_id === entry.tmdb_id && f.media_type === entry.media_type));
}
function toggleFavorite(s) {
  const saved = titleFavorites(s);
  if (saved.length) sendFavorites("/api/favorites/remove", { ids: saved.map(f => f.id) });
  else sendFavorites("/api/favorites", { items: [favoriteEntry(s)] });
}

function openFavorite(f) {
  const source = f.source_override || {};
  const path = source.path || source.id;
  const library = path && libraryItems.find(i => i.id === path);
  if (library) return openLibraryTitle(library);
  openDetails({ title: f.title, clean_title: f.clean_title, poster: f.poster, tmdb_id: f.tmdb_id,
                media_type: f.media_type, magnet: f.magnet, download_link: f.download_link });
}

async function loadLibrary(refresh = false) {
  clearTimeout(libraryTimer);
  try {
    const response = await fetch(`/api/library${refresh ? "?refresh=1" : ""}`);
    if (!response.ok) throw new Error("Couldn't load the library. Try again.");
    const d = await response.json();
    libraryItems = d.items || [];
    libraryPending = d.metadata_pending || 0;
    libraryLoaded = true;
    homeLibraryError = '';
  } catch (e) { homeLibraryError = "Couldn't load the library. Try again."; renderServerHome(); return; }
  renderLibrary();
  renderLibraryStats();
  // The server matches new titles in the background; look again until done.
  if (libraryPending > 0) libraryTimer = setTimeout(() => loadLibrary(), 5000);
}

function libraryTitle(item) { return item.display_title || item.title || item.name; }

function renderLibrary() {
  renderServerHome();
  const dedicated = ['library', 'favorites'].includes(document.body.dataset.serverView);
  const show = dedicated || ((libraryItems.length > 0 || favorites.length > 0) && libraryShown());
  libraryPanel.hidden = !show;
  layoutEl.classList.toggle("has-library", show);
  if (!show) return;
  const words = plainText(libraryFilter.value).split(" ").filter(Boolean);
  const items = words.length ? libraryItems.filter(item => {
    const hay = " " + plainText([item.display_title, item.title, item.name, item.original_title].filter(Boolean).join(" ")) + " ";
    return words.every(w => hay.includes(" " + w));
  }) : libraryItems;
  const saved = words.length ? favorites.filter(f => {
    const hay = " " + plainText([f.clean_title, f.title].filter(Boolean).join(" ")) + " ";
    return words.every(w => hay.includes(" " + w));
  }) : favorites;
  const counts = Object.fromEntries(LIBRARY_KINDS.map(([k]) => [k, items.filter(i => i.kind === k).length]));
  counts.favorites = saved.length;
  // Favorites comes after Cartoons, as in the apps.
  const tabs = [...LIBRARY_KINDS, ["favorites", "Favorites"]];
  if (!librarySection) librarySection = "movie";
  const availableTabs = tabs.filter(([k]) => counts[k] || k === librarySection || k === "movie");
  libraryKinds.innerHTML = availableTabs.map(([k, label]) =>
    `<button type="button" class="library-chip${k === librarySection ? " is-active" : ""}" data-kind="${k}">${label} · ${counts[k]}</button>`).join("");
  if (libraryKindsSelect) {
    libraryKindsSelect.innerHTML = availableTabs.map(([k, label]) =>
      `<option value="${k}"${k === librarySection ? " selected" : ""}>${label} (${counts[k]})</option>`).join("");
    libraryKindsSelect.value = librarySection;
  }
  libraryNote.hidden = !libraryPending;
  libraryNote.textContent = libraryPending ? `Matching ${libraryPending} new title${libraryPending === 1 ? "" : "s"} on TMDB…` : "";
  libraryGrid.innerHTML = "";
  if (librarySection === "favorites") saved.forEach(f => libraryGrid.appendChild(buildFavoriteCard(f)));
  else items.filter(i => i.kind === librarySection).forEach(item => libraryGrid.appendChild(buildLibraryCard(item)));
  if (!libraryGrid.childElementCount) libraryGrid.innerHTML = libraryFilter.value.trim()
    ? `<div class="library-empty">Nothing in your library matches “${escapeHtml(libraryFilter.value.trim())}”.</div>`
    : `<div class="library-empty">No titles in this section yet.</div>`;
}

function buildLibraryCard(item) {
  const card = document.createElement("button");
  card.type = "button";
  card.className = "lib-card";
  card.dataset.favId = item.id;
  if (isFavorite(item.id)) card.classList.add("is-favorite");
  const versions = (item.versions || []).length;
  const badge = item.seasons > 0 ? `${item.seasons} season${item.seasons === 1 ? "" : "s"}` : versions > 1 ? `${versions} versions` : "";
  const sub = [item.year, item.rating > 0 ? `★ ${item.rating.toFixed(1)}` : ""].filter(Boolean).join(" · ");
  card.innerHTML = `<div class="lib-poster">${item.poster
      ? `<img src="${escapeHtml(item.poster.replace("/w200/", "/w342/"))}" alt="" loading="lazy">`
      : brandArt(libraryTitle(item))}${badge ? `<span class="lib-badge">${badge}</span>` : ""}${FAVORITE_BADGE}</div>
    <div class="lib-title">${escapeHtml(libraryTitle(item))}</div>${sub ? `<div class="lib-sub">${escapeHtml(sub)}</div>` : ""}`;
  card.addEventListener("click", () => openLibraryTitle(item));
  return card;
}

function buildFavoriteCard(f) {
  const card = document.createElement("button");
  card.type = "button";
  card.className = "lib-card is-favorite";
  const title = f.clean_title || f.title;
  const kind = { movie: "Movie", tv: "TV show", cartoon: "Cartoon" }[f.kind] || "";
  card.innerHTML = `<div class="lib-poster">${f.poster
      ? `<img src="${escapeHtml(f.poster.replace("/w200/", "/w342/"))}" alt="" loading="lazy">`
      : brandArt(title)}${FAVORITE_BADGE}</div>
    <div class="lib-title">${escapeHtml(title)}</div>${kind ? `<div class="lib-sub">${kind}</div>` : ""}`;
  card.addEventListener("click", () => openFavorite(f));
  return card;
}

// The top bar's height, for the library's own scrolling area.
function measureTopBar() {
  const bar = document.querySelector(".top-bar");
  if (bar) document.documentElement.style.setProperty("--topbar-h", `${bar.offsetHeight}px`);
}
window.addEventListener("resize", measureTopBar);
measureTopBar();

libraryChips.addEventListener("click", e => {
  const chip = e.target.closest(".library-chip[data-kind]");
  if (chip) {
    librarySection = chip.dataset.kind;
    document.body.dataset.serverView = 'library';
    updateServerNavigation('library');
    renderLibrary(); libraryGrid.scrollTop = 0;
  }
});

if (libraryKindsSelect) {
  libraryKindsSelect.addEventListener("change", () => {
    librarySection = libraryKindsSelect.value;
    document.body.dataset.serverView = 'library';
    updateServerNavigation('library');
    renderLibrary();
    libraryGrid.scrollTop = 0;
  });
}

libraryFilter.addEventListener("input", () => { renderLibrary(); libraryGrid.scrollTop = 0; });
libraryFilter.addEventListener("keydown", e => { if (e.key === "Escape" && libraryFilter.value) { e.stopPropagation(); libraryFilter.value = ""; renderLibrary(); } });

// The details popup, with the title's files to play instead of releases.
function openLibraryTitle(item) {
  openDetails({
    title: libraryTitle(item), clean_title: libraryTitle(item), poster: item.poster, rating: item.rating,
    overview: item.overview, tmdb_id: item.tmdb_id, media_type: item.media_type, library: item,
  });
}

function closeSearchDropdownIfOpen() {
  if (typeof searchDropdown !== "undefined") searchDropdown.classList.remove("is-open");
}

// Every file of every version, in play order (episodes in order).
async function loadLibraryFiles(requestId) {
  const s = detailsState, item = s.item.library;
  const paths = (item.versions && item.versions.length ? item.versions.map(v => v.id) : [item.id]);
  const groups = [];
  for (const path of paths) {
    try {
      const d = await fetch("/api/playback/prepare", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ path }) }).then(r => r.json());
      if (d.files) groups.push({ path, files: d.files });
    } catch (e) {}
  }
  if (requestId !== detailsRequestId) return;
  s.libraryFiles = groups;
  renderDetailsBody();
}

function libraryFileList() {
  return (detailsState && detailsState.libraryFiles || []).flatMap(g => g.files);
}

function libraryMediaUrl(file) {
  return `${location.origin}/media/${file.path.split("/").map(encodeURIComponent).join("/")}`;
}

// Season and episode of a library file, as the apps read it: S01E02 or
// 1x02 in the name, else a "Season 1" / "Сезон 1" folder and a leading number.
// The season and episode the server read from the file's name and folders
// (episodes.py - the same reading the apps use). A file with two episodes
// in it ("1-1-2 Name", "S01E01-E02") has `last` after `episode`.
function episodeOf(file) {
  return file.season != null && file.episode != null
    ? { season: file.season, episode: file.episode, last: file.last_episode || file.episode } : null;
}

// A series' episodes: one file per season and episode (the first copy of
// each), in order. Null for a film.
function libraryEpisodes() {
  // Another copy of an episode already listed (also inside a double file) is skipped.
  const covered = new Set(), rows = [];
  for (const file of libraryFileList()) {
    const id = episodeOf(file);
    if (!id) continue;
    const keys = [];
    for (let n = id.episode; n <= id.last; n++) keys.push(`${id.season}:${n}`);
    if (keys.some(k => covered.has(k))) continue;
    keys.forEach(k => covered.add(k));
    rows.push({ ...id, file });
  }
  if (rows.length < 2) return null;
  return rows.sort((a, b) => a.season - b.season || a.episode - b.episode);
}

// TMDB's names and stills for a season's episodes, once per season.
async function loadEpisodeNames(season) {
  const s = detailsState, id = s.data && s.data.tmdb_id;
  if (!id || s.data.media_type !== "tv") return;
  s.episodeNames = s.episodeNames || {};
  if (s.episodeNames[season]) return;
  s.episodeNames[season] = "loading";
  try {
    const d = await fetch(`/api/episodes?id=${encodeURIComponent(id)}&season=${season}`).then(r => r.json());
    if (detailsState !== s) return;
    if (d.error) throw new Error(d.error);
    s.episodeNames[season] = Object.fromEntries((d.episodes || []).map(e => [e.number, e]));
    s.episodeErrors = s.episodeErrors || {};
    delete s.episodeErrors[season];
  } catch (e) {
    if (detailsState !== s) return;
    s.episodeNames[season] = {};
    s.episodeErrors = { ...s.episodeErrors, [season]: true };
  }
  if (detailsState === s) renderDetailsBody();
}

// Infuse gets direct video URLs in its own queue format; VLC gets an M3U.
// Both start with the selected episode and continue in episode order.
function playLibraryFrom(file) {
  if (!file) return;
  const episodes = libraryEpisodes();
  if (!episodes) { playLibraryFile(file); return; }
  const start = episodes.findIndex(e => e.file.path === file.path);
  if (start < 0) { playLibraryFile(file); return; }
  if (currentPlayer() === "infuse") {
    const queue = episodes.slice(start).map(e => ({ url: libraryMediaUrl(e.file), name: e.file.name }));
    playLibraryUrl(queue[0].url, file, queue);
    return;
  }
  const files = episodes.slice(Math.max(0, start)).map(e => e.file.path);
  const token = hashHex(files.join("\n"));
  fetch("/api/library/playlist", { method: "POST", keepalive: true, headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token, files }) }).catch(() => {});
  playLibraryUrl(`${location.origin}/playlist/${token}.m3u`, file);
}

// Straight from disk: no torrent, no play link to register.
function playLibraryFile(file) {
  if (file) playLibraryUrl(libraryMediaUrl(file), file);
}
function playLibraryUrl(url, file, queue) {
  const id = currentPlayer();
  if (id === "vlc" && VLC_HELPER_OS && !vlcHelperInstalled()) {
    openVlcHelper(() => playLibraryUrl(url, file, queue));
    return;
  }
  const appLink = PLAYERS[id].link(url, null, queue || [{ url, name: file.name }]);
  if (appLink) location.href = appLink;
  else copyText(url, `Link copied. In ${PLAYERS[id].name}, choose File > Open Network and paste it`);
}

// Library titles matching a search, as in the apps: words of the query in
// the Ukrainian title, the original title or the folder name.
function plainText(text) {
  return (text || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}
function librarySearch(query) {
  const words = plainText(query).split(" ").filter(Boolean);
  if (!words.length) return [];
  return libraryItems.filter(item => {
    const hay = " " + plainText([item.display_title, item.title, item.name, ...(item.versions || []).map(v => v.name)].join(" ")) + " ";
    return words.every(w => hay.includes(" " + w));
  }).slice(0, 12);
}

function buildLibraryResult(item) {
  const div = document.createElement("div");
  div.className = "item";
  const kind = (LIBRARY_KINDS.find(([k]) => k === item.kind) || [null, ""])[1];
  const sub = [kind, item.year, item.rating > 0 ? `★ ${item.rating.toFixed(1)}` : ""].filter(Boolean).join(" · ");
  div.innerHTML = `<div class="item-top">
      ${item.poster ? `<img class="result-poster" src="${escapeHtml(item.poster)}" alt="" loading="lazy">` : `<div class="result-poster-fallback">${ICONS.download}</div>`}
      <div class="item-meta">
        <div class="item-title">${escapeHtml(libraryTitle(item))}</div>
        <div class="item-sub">${escapeHtml(sub)}</div>
        ${item.overview ? `<div class="item-overview">${escapeHtml(item.overview)}</div>` : ""}
      </div>
      <div class="search-result-actions"><button class="btn-secondary btn-add-result">${ICONS.play}<span>Open</span></button></div>
    </div>`;
  div.addEventListener("click", () => openLibraryTitle(item));
  return div;
}

function sectionHead(text) {
  const head = document.createElement("div");
  head.className = "search-section-head";
  head.textContent = text;
  return head;
}

// ---------- Settings: Library ----------
function renderLibraryStats() {
  const stats = document.getElementById("libraryStats");
  if (!stats) return;
  const matched = libraryItems.filter(i => i.tmdb_id).length;
  const cells = [[libraryItems.length, "titles"], ...LIBRARY_KINDS.map(([k, label]) => [libraryItems.filter(i => i.kind === k).length, label.toLowerCase()]),
                 [matched, "matched on TMDB"], [libraryPending, "waiting"]];
  stats.innerHTML = cells.map(([n, label]) => `<div class="library-stat"><b>${n}</b><span>${label}</span></div>`).join("");
}
const settingsShowLibrary = document.getElementById("settingsShowLibrary");
settingsShowLibrary.checked = libraryShown();
settingsShowLibrary.addEventListener("change", () => {
  try { localStorage.setItem("showLibrary", settingsShowLibrary.checked ? "1" : "0"); } catch (e) {}
  renderLibrary();
});
document.getElementById("libraryRefreshBtn").addEventListener("click", async () => {
  await loadLibrary(true);
  showToast(`Library: ${libraryItems.length} titles`);
});
document.getElementById("libraryRescanBtn").addEventListener("click", async () => {
  try { await fetch("/api/library/metadata", { method: "DELETE" }); } catch (e) { showToast("Couldn't reach the server", true); return; }
  showToast("Looking every title up on TMDB again…");
  loadLibrary();
});

async function init() {
  // Back from the player: /played/<token> deleted the stream and sent us here.
  const params = new URLSearchParams(location.search);
  if (params.has("stream_closed")) {
    showToast("Player closed - the temporary file is deleted");
    params.delete("stream_closed");
    history.replaceState(null, "", location.pathname + (params.toString() ? `?${params}` : "") + location.hash);
  }
  setServerView("home");
  loadServerCatalog();
  loadConfig();
  loadLimits();
  loadLibrary();
  loadFavorites();
  // Hearts set on another device show when the page is looked at again.
  document.addEventListener("visibilitychange", () => { if (!document.hidden) loadFavorites(); });
  // Home uses the same server library and history as the Apple clients.
  loadServerHistory();
  handleServerResumeReturn();
  setInterval(() => { if (!document.hidden) {
    loadServerHistory(); loadFavorites(); loadLibrary();
    if (Date.now() - catalogUpdatedAt > 300000) loadServerCatalog(true);
  } }, 30000);
  refresh();
  if (params.has("title") || params.has("person")) await restoreTitleRoute();
  // Every 1.5 s while the page is in view; a tab in the background asks
  // nothing and catches up the moment it is shown again.
  setInterval(() => { if (!document.hidden) refresh(); }, 1500);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
}
init();
