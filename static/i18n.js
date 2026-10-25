// UI language is a browser preference. API data, file paths, and folder values
// remain unchanged. Keep source text so switching languages is reversible.
const UI_UK = {
  'Interface':'Інтерфейс', 'Theme':'Тема', 'Close search':'Закрити пошук',
  'Loading the torrent catalog…':'Завантаження каталогу торентів…',
  'Could not load the torrent catalog. Check Search in Settings.':'Не вдалося завантажити каталог торентів. Перевірте пошук у налаштуваннях.',
  'Nothing here right now.':'Тут поки нічого немає.',
  'Home':'Головна', 'Recently added':'Нове на сервері', 'New on your server':'Нове на вашому сервері',
  'Synced across devices':'Синхронізовано між пристроями',
  'See all':'Переглянути всі', 'Watch':'Дивитися', 'Details':'Деталі',
  'Online library':'Онлайн-медіатека',
  'Your library and download server':'Онлайн-медіатека',
  'Main navigation':'Головна навігація', 'Server information':'Інформація про сервер',
  'Server settings':'Налаштування сервера', 'Connected':'Підключено', 'Connecting…':'Підключення…',
  'Loading your library…':'Завантаження медіатеки…', 'Featured title':'Вибрана назва', 'Featured titles':'Вибрані назви',
  'Playback progress':'Перебіг перегляду', 'Available on your server':'Доступно на вашому сервері',
  'Your server':'Ваш сервер', 'Your next watch starts here':'Ваш наступний перегляд починається тут',
  'Your library, favorites and viewing history in one place. Search for a title or add a torrent to grow your library.':'Медіатека, обране та історія перегляду в одному місці. Знайдіть назву або додайте торент до медіатеки.',
  'titles':'назв', 'active downloads':'активних завантажень', 'Search enabled':'Пошук увімкнено',
  'Search not configured':'Пошук не налаштовано', 'Could not save playback position':'Не вдалося зберегти позицію перегляду',
  'No titles in this section yet.':'У цьому розділі ще немає назв.',
  'Torrents':'Торенти', 'Searching...':'Шукаємо…', 'Documentaries':'Документальні',
  'Ukrainian':'Українською', 'New':'Нове',
  "Couldn't load the library. Try again.":'Не вдалося завантажити медіатеку. Спробуйте ще раз.',
  'Back':'Назад', 'Settings':'Налаштування', 'Toggle theme':'Змінити тему',
  'Toggle light/dark theme':'Змінити світлу або темну тему', 'Interface language':'Мова інтерфейсу',
  'Paste a magnet link, search, or drop a .torrent file':'Знайдіть назву, вставте magnet-посилання або додайте .torrent',
  'Search torrents, library, or paste a magnet link':'Пошук у бібліотеці й торентах або magnet-посилання',
  'Search':'Пошук', 'Clear':'Очистити', 'Close':'Закрити', 'Results':'Результати',
  'Downloads':'Завантаження', 'Discover':'Огляд', 'Discover new releases':'Знайти новинки',
  'Switch between Discover and Downloads':'Перемкнути огляд і завантаження',
  'Upload a .torrent file':'Додати файл .torrent', 'Search the library':'Пошук у бібліотеці',
  'Paste a magnet link above, or drop a .torrent file anywhere on this page.':'Вставте magnet-посилання вище або перетягніть файл .torrent на сторінку.',
  'Clear all':'Очистити все', 'Prev':'Назад', 'Next':'Далі', 'Buffering':'Буферизація',
  'Temporary files for the player. Each is deleted when you close the player.':'Тимчасові файли для плеєра. Вони видаляються після закриття плеєра.',
  'Drop .torrent file to add it':'Перетягніть файл .torrent, щоб додати його',
  'Cancel':'Скасувати', 'Download':'Завантажити', 'General':'Загальні', 'Server':'Сервер',
  'Library':'Бібліотека', 'My library':'Моя бібліотека', 'Players':'Плеєри', 'Default folder':'Типова папка',
  'Bandwidth & Connections':'Швидкість і з’єднання', 'Download speed':'Швидкість завантаження',
  'Upload speed':'Швидкість віддачі', 'Unlimited':'Без обмежень', 'Default':'Типово', 'No cap':'Без обмежень',
  'Seed after download':'Роздавати після завантаження', 'Remove when finished':'Прибирати після завершення',
  'Max connections':'Максимум з’єднань', 'Per-torrent connections':'З’єднання на торент', 'Max upload slots':'Максимум слотів віддачі',
  'Save location':'Папка збереження', 'Categories':'Категорії', 'Torrent Search':'Пошук торентів',
  'Status':'Стан', 'Jackett URL':'Адреса Jackett', 'Jackett API key':'API-ключ Jackett', 'Jackett indexer':'Індексатор Jackett',
  'Paste your Jackett API key':'Вставте API-ключ Jackett', 'Posters & Ratings':'Постери й оцінки',
  'TMDB API key':'API-ключ TMDB', 'Paste your TMDB API key':'Вставте API-ключ TMDB', 'TMDB language':'Мова даних TMDB',
  'Everything in your download folders. The server matches each title on TMDB once and keeps the posters and details - the same library the Apple TV, iPhone, iPad and Mac apps show.':'Усі відео з папок завантажень. Сервер зберігає постери й описи з TMDB. Цю саму бібліотеку показують застосунки Apple TV, iPhone, iPad і Mac.',
  'Show on the Downloads page':'Показувати на сторінці завантажень', 'Refresh list':'Оновити список', 'Rescan metadata':'Оновити дані TMDB',
  'Look through the folders again for new or removed titles':'Перевірити нові й видалені відео в папках',
  'Forget every match and look all titles up on TMDB again':'Повторно знайти всі назви в TMDB',
  'Playback':'Відтворення', 'Default player':'Типовий плеєр', 'On this device':'На цьому пристрої',
  'Default audio track':'Типова звукова доріжка', 'Download new episodes':'Завантажувати нові серії',
  'Every 30 minutes the server looks for new episodes of the shows in your library and downloads only the missing ones, from the release most like your files':'Кожні 30 хвилин сервер шукає нові серії серіалів з вашої бібліотеки й завантажує лише відсутні, з релізу, найсхожішого на ваші файли',
  'The audio track players start with, on every device. If a file does not have it, English is used. New episodes are downloaded in this language too':'Доріжка, з якої плеєри починають на всіх пристроях. Якщо у файлі її немає, вмикається англійська. Нові серії теж завантажуються цією мовою',
  'Collections':'Колекції',
  'Action':'Бойовики', 'Comedy':'Комедії', 'Thriller':'Трилери', 'Drama':'Драми', 'Horror':'Жахи', 'Sci-Fi':'Фантастика',
  'Adventure':'Пригоди', 'Crime':'Кримінал', 'Fantasy':'Фентезі', 'Family':'Сімейні', 'Romance':'Мелодрами', 'Genres':'Жанри', 'Action & Adventure':'Бойовики та пригоди', 'Mystery':'Детективи', 'Couldn’t load titles':'Не вдалося завантажити добірку', 'Animated films':'Мультфільми', 'Animated series':'Мультсеріали', 'Kids':'Для малят', 'Sci-Fi & Fantasy':'Фантастика та фентезі',
  'Reality':'Реаліті', 'War & Politics':'Війна та політика',
  'Fix match':'Виправити дані', 'Files':'Файли', 'Now:':'Зараз:', 'Now':'Зараз', 'Title':'Назва', 'Year':'Рік',
  'Metadata language':'Мова даних', 'Use this match':'Використати ці дані',
  'Match automatically again':'Знову визначати автоматично', 'Match saved':'Дані збережено',
  "Couldn't save the match":'Не вдалося зберегти дані', 'Search TMDB and pick the right film or show':'Знайти на TMDB і вибрати правильний фільм або серіал',
  'Nothing found. Try the original title, another year or another language.':'Нічого не знайдено. Спробуйте оригінальну назву, інший рік або іншу мову.',
  'Films of one series, like Harry Potter, appear here once two of them are on the server.':'Фільми однієї серії, як-от «Гаррі Поттер», з’являються тут, коли на сервері є два з них.',
  'Last check:':'Остання перевірка:', 'Last downloaded:':'Останнє завантажене:',
  'The first check starts within a minute.':'Перша перевірка почнеться протягом хвилини.',
  "A web page can't see which apps are installed, so a player gets its ✓ once it has opened from here. On a computer, VLC's comes from its helper's installer.":'Браузер не бачить установлених застосунків. Позначка ✓ з’явиться після відкриття плеєра. На комп’ютері наявність VLC перевіряє допоміжна програма.',
  'Reset':'Скинути', 'Save':'Зберегти', 'Play in':'Відкрити в', 'Play':'Дивитися', 'Open':'Відкрити',
  'Play opens the film in this app straight away. It streams from this server through a temporary file, which is deleted when you close the player.':'Фільм відкриється в обраному плеєрі. Тимчасовий файл для відтворення видалиться після закриття плеєра.',
  'Play in VLC on this computer':'Відтворення у VLC на цьому комп’ютері', 'Two steps, once per computer.':'Два кроки. Лише один раз на цьому комп’ютері.',
  'VLC player':'Плеєр VLC', 'Download VLC from videolan.org':'Завантажити VLC з videolan.org',
  'Torrent Tube helper':'Допоміжна програма Torrent Tube',
  "Your browser can't start VLC by itself. This small helper lets Play open VLC, just like Infuse. It only opens films from this server.":'Допоміжна програма дозволяє браузеру відкривати VLC. Вона відтворює лише відео з цього сервера.',
  'Copy':'Копіювати', 'Waiting for the helper to install…':'Очікуємо встановлення допоміжної програми…',
  'Already set up?':'Уже налаштовано?', 'Skip':'Пропустити', 'It may not be installed on this device.':'Можливо, застосунок не встановлено на цьому пристрої.',
  'Press Try again':'Натисніть «Спробувати ще раз»', 'Or choose another player.':'Або виберіть інший плеєр.',
  'Other player':'Інший плеєр', 'Try again':'Спробувати ще раз', 'Are you sure?':'Ви впевнені?',
  'Movies':'Фільми', 'Movie':'Фільм', 'TV Shows':'Серіали', 'TV show':'Серіал', 'Cartoons':'Мультфільми', 'Cartoon':'Мультфільм',
  'Favorites':'Обране', 'Favorite':'В обране', 'Unfavorite':'В обраному', 'All':'Усі',
  'In Favorites':'В обраному', 'Remove from Favorites':'Прибрати з обраного', 'Add to Favorites':'Додати в обране',
  'In your library':'У вашій бібліотеці', 'Not in your library':'Немає в бібліотеці',
  'Search torrents':'Шукати торенти', 'Play episode':'Дивитися серію', 'Trailer':'Трейлер', 'Play trailer':'Дивитися трейлер',
  'Episodes':'Серії', 'Choose season':'Виберіть сезон', 'Specials':'Спецвипуски',
  'Cast & crew':'Актори та знімальна група', 'Information':'Інформація', 'More like this':'Схожі',
  'Genres':'Жанри', 'Network':'Канал', 'Next episode':'Наступна серія', 'Released':'Дата виходу',
  'Country':'Країна', 'Language':'Мова', 'Collection':'Колекція', 'Links':'Посилання', 'Tracker':'Трекер', 'Website':'Сайт',
  'Director':'Режисер', 'Creator':'Автор', 'Ended':'Завершено', 'Returning Series':'Серіал триває',
  'Downloads & versions':'Завантаження й версії', 'Choose quality and manage files':'Якість і файли',
  'Library files':'Файли в бібліотеці', 'Browse files':'Переглянути файли', 'Download folder':'Папка завантаження',
  'Choose folder':'Виберіть папку', 'Downloaded files are added to your library.':'Завантажені файли з’являться у вашій бібліотеці.',
  'Search torrents for a different quality or another season.':'Знайдіть торенти з іншою якістю або іншим сезоном.',
  'No video files were found in this folder. Try refreshing your library.':'У цій папці немає відеофайлів. Спробуйте оновити бібліотеку.',
  'Reading the folder…':'Читаємо папку…', 'Releases':'Торенти', 'This release':'Ця версія',
  'No releases of this title found on the tracker.':'На трекері немає торентів із цією назвою.',
  'Searching the tracker…':'Шукаємо на трекері…', 'Finding releases…':'Шукаємо торенти…', 'No releases found':'Торентів не знайдено',
  'Added':'Додано', 'Downloaded':'Завантажено', 'Downloading':'Завантажується', 'Show all':'Показати всі', 'Show fewer':'Показати менше',
  'More':'Докладніше', 'Less':'Згорнути', 'Finding trailer…':'Шукаємо трейлер…', 'Choose the player':'Виберіть плеєр',
  'Download this release':'Завантажити цю версію', 'Loading title…':'Завантажуємо опис…',
  'Loading films and TV shows…':'Завантажуємо фільми й серіали…', 'No titles are listed here yet.':'Тут поки немає фільмів і серіалів.',
  'Filter titles':'Фільтр назв', 'Loading episodes…':'Завантажуємо серії…',
  'No episodes are listed for this season yet.':'Для цього сезону поки немає серій.',
  'Episode details are not available yet.':'Опис серії поки недоступний.',
  "Couldn't load episode details.":'Не вдалося завантажити описи серій.',
  'Could not load films and TV shows.':'Не вдалося завантажити фільми й серіали.',
  "Couldn't reach TMDB":'Не вдалося з’єднатися з TMDB', "Couldn't reach the server":'Не вдалося з’єднатися із сервером',
  "Details need a TMDB API key - add one in Settings":'Для описів потрібен API-ключ TMDB. Додайте його в налаштуваннях.',
  'All indexers':'Усі індексатори', 'Enabled':'Увімкнено', 'Disabled':'Вимкнено', 'Not configured':'Не налаштовано',
  'Installed':'Установлено', 'Not installed':'Не встановлено', 'Not checked yet':'Ще не перевірено', 'Not found':'Не знайдено',
  'Apple devices only':'Лише для пристроїв Apple', 'Remove the helper':'Видалити допоміжну програму',
  'Install the helper':'Установити допоміжну програму', 'Step-by-step setup':'Покрокове налаштування',
  'Command copied':'Команду скопійовано', 'Link copied':'Посилання скопійовано', 'Copied':'Скопійовано',
  'Pause':'Призупинити', 'Resume':'Продовжити', 'Remove':'Прибрати', 'Delete':'Видалити', 'Delete files too':'Також видалити файли',
  'Seeding':'Роздається', 'Paused':'Призупинено', 'Completed':'Завершено', 'Queued':'У черзі',
  'Checking':'Перевіряється', 'Error':'Помилка', 'Loading…':'Завантажуємо…', 'Searching…':'Шукаємо…',
  'Off: a torrent stops uploading the moment it finishes, instead of continuing to seed':'Якщо вимкнено, торент припиняє роздачу одразу після завантаження.',
  "Takes a torrent off the list once it's downloaded - the files stay in their folder. Also stops seeding it":'Прибирає завершений торент зі списку й припиняє роздачу. Файли залишаються в папці.',
  'Peer connections across all torrents combined':'Загальна кількість з’єднань для всіх торентів',
  'Peer connections allowed on any one torrent':'Кількість з’єднань для одного торента',
  'Peers unchoked (actively uploaded to) at the same time':'Кількість учасників, яким одночасно віддаються дані',
  'Search results come from your Jackett instance':'Результати пошуку надходять із вашого Jackett',
  "Jackett's dashboard, top right corner":'На панелі Jackett, угорі праворуч',
  "Trackers you've added in Jackett - All searches every one of them":'Трекери, додані в Jackett. «Усі» шукає на кожному з них.',
  'Enriches search results via TMDB':'Додає постери й описи з TMDB', 'Free key at themoviedb.org/settings/api':'Безкоштовний ключ: themoviedb.org/settings/api',
  'Language for titles and descriptions from TMDB':'Мова назв і описів із TMDB',
  'The library takes the left of the Downloads page; Downloads and Buffering move to the right':'Бібліотека буде ліворуч, а завантаження й буферизація — праворуч.',
  'The app the Play button opens. The ▾ beside Play changes it too':'Застосунок, який відкриває кнопка «Дивитися». Його також можна змінити через ▾ поруч.',
};

Object.assign(UI_UK, {
  "Add": "Додати",
  "Adding...": "Додаємо…",
  "Loading...": "Завантажуємо…",
  "Show less": "Згорнути",
  "Show more": "Докладніше",
  "Continue Watching": "Продовжити перегляд",
  "New releases": "Новинки",
  "Popular": "Популярне",
  "Trending": "У тренді",
  "Top rated": "Найкращі",
  "Animation": "Анімація",
  "New for watching": "Нове для перегляду",
  "Search isn't set up on this server yet": "Пошук на сервері ще не налаштовано",
  "Couldn't load this feed. Try again.": "Не вдалося завантажити добірку. Спробуйте ще раз.",
  "Search failed. Try again.": "Не вдалося виконати пошук. Спробуйте ще раз.",
  "Settings saved": "Налаштування збережено",
  "Couldn't save settings": "Не вдалося зберегти налаштування",
  "Couldn't save the default player": "Не вдалося зберегти типовий плеєр",
  "Couldn't save it": "Не вдалося зберегти",
  "Remove torrent and delete its files?": "Прибрати торент і видалити його файли?",
  "Remove torrent from the list?": "Прибрати торент зі списку?",
  "The downloaded files will be permanently deleted.": "Завантажені файли буде остаточно видалено.",
  "The downloaded files are kept on disk.": "Завантажені файли залишаться на диску.",
  "Nothing is playing. Films you play in Infuse or VLC buffer here.": "Зараз нічого не відтворюється. Тут показується буферизація відео для Infuse або VLC.",
  "VLC is installed.": "VLC установлено.",
  "VLC isn't on this computer yet. Download and install it, then press Play.": "VLC ще не встановлено. Завантажте й установіть його, потім натисніть «Дивитися».",
  "The free player that plays the film. Don't have it yet? Install it first.": "Безкоштовний плеєр для перегляду відео. Спочатку встановіть його.",
  "Helper installed - Play now opens VLC.": "Допоміжну програму встановлено. Кнопка «Дивитися» відкриває VLC.",
  "VLC is ready": "VLC готовий",
  "Almost ready": "Майже готово",
  "All set on this computer.": "На цьому комп’ютері все налаштовано.",
  "Install VLC, then press Play.": "Установіть VLC, потім натисніть «Дивитися».",
  "Done": "Готово",
  "Open Terminal: press ⌘ Space, type Terminal, press Return.": "Відкрийте Terminal: натисніть ⌘ Space, введіть Terminal і натисніть Return.",
  "Open PowerShell: press the Windows key, type PowerShell, press Enter.": "Відкрийте PowerShell: натисніть клавішу Windows, введіть PowerShell і натисніть Enter.",
  "Press ⌘ V, then Return - the command below is already copied.": "Натисніть ⌘ V, потім Return. Команду нижче вже скопійовано.",
  "Press Ctrl + V, then Enter - the command below is already copied.": "Натисніть Ctrl + V, потім Enter. Команду нижче вже скопійовано.",
  "Infuse plays the film from this server. Get it on the App Store - for iPhone, iPad, Apple TV and Mac.": "Infuse відтворює відео з цього сервера. Завантажте його з App Store для iPhone, iPad, Apple TV або Mac.",
  "VLC is a free player that plays the film from this server.": "VLC — безкоштовний плеєр для перегляду відео з цього сервера.",
  "Title details": "Опис",
  "Pause download": "Призупинити завантаження",
  "Resume download": "Продовжити завантаження"
});

function ukrainianCount(n, one, few, many) {
  const number = Number(n), tail = number % 100;
  const word = tail >= 11 && tail <= 14 ? many : number % 10 === 1 ? one : number % 10 >= 2 && number % 10 <= 4 ? few : many;
  return `${n} ${word}`;
}

function translateUI(text, language) {
  if (language !== 'uk') return text;
  const key = text.trim();
  let translated = UI_UK[key];
  if (!translated) {
    const patterns = [
      [/^(\d+) titles$/, n => ukrainianCount(n, 'назва', 'назви', 'назв')],
      [/^Resume at (.+)$/, time => `Продовжити з ${time}`],
      [/^(\d+) season$/, n => ukrainianCount(n, 'сезон', 'сезони', 'сезонів')],
      [/^Results for “(.+)”$/, query => `Результати для «${query}»`],
      [/^Downloaded: (.+)$/, name => `Завантажено: ${name}`],
      [/^(.+) didn't open$/, app => `Не вдалося відкрити ${app}`],
      [/^Install (.+)$/, app => `Установити ${app}`],
      [/^Saved - it's downloading to (.+)$/, folder => `Збережено. Завантажуємо в ${folder}`],
      [/^Command copied - paste it in (.+)$/, app => `Команду скопійовано. Вставте її в ${app}`],
      [/^Couldn't play: (.+)$/, error => `Не вдалося відтворити: ${translateUI(error, language)}`],
      [/^Nothing in your library matches “(.+)”\.$/, query => `У бібліотеці немає результатів для «${query}».`],
      [/^Season (\d+)$/, n => `Сезон ${n}`], [/^Episode (\d+)$/, n => `Серія ${n}`],
      [/^(\d+) episodes$/, n => ukrainianCount(n, 'серія', 'серії', 'серій')], [/^(\d+) films and TV shows$/, n => `${n} фільмів і серіалів`],
      [/^(\d+) seasons$/, n => ukrainianCount(n, 'сезон', 'сезони', 'сезонів')], [/^(\d+) video files$/, n => ukrainianCount(n, 'відеофайл', 'відеофайли', 'відеофайлів')],
      [/^(\d+) versions$/, n => ukrainianCount(n, 'версія', 'версії', 'версій')],
      [/^(\d+) films$/, n => ukrainianCount(n, 'фільм', 'фільми', 'фільмів')],
      [/^(\d+) of (\d+) films$/, (n, total) => `${n} з ${total} фільмів`],
      [/^Part (\d+)$/, n => `Частина ${n}`],
      [/^Results for “(.+)”$/, q => `Результати для «${q}»`],
      [/^Page (\d+) of (\d+)$/, (n, total) => `Сторінка ${n} з ${total}`],
      [/^Play in (.+)$/, app => `Відкрити в ${app}`], [/^Copy link for (.+)$/, app => `Копіювати посилання для ${app}`],
      [/^Play this release in (.+)$/, app => `Відтворити цю версію в ${app}`],
      [/^Play this exact file in (.+)$/, app => `Відтворити цей файл у ${app}`],
      [/^Download folder: (.+)$/, folder => `Папка завантаження: ${UI_UK[folder] || folder}`],
      [/^In your library( · .+)$/, rest => `У вашій бібліотеці${translateUI(rest, language)}`],
      [/^Downloads & versions( · .+)$/, rest => `Завантаження й версії${rest}`],
      [/^Releases( · .+)$/, rest => `Торенти${rest}`],
      [/^Downloading( · .+)$/, rest => `Завантажується${rest}`],
      [/^Search torrents: (.+)$/, name => `Шукати торенти: ${name}`],
      [/^Play episode: (.+)$/, name => `Дивитися серію: ${name}`],
      [/^(\d+) min$/, n => `${n} хв`],
      [/^(.+)\s*\((\d+)\)$/, (cat, n) => `${UI_UK[cat.trim()] || cat.trim()} (${n})`],
    ];
    for (const [pattern, render] of patterns) {
      const match = key.match(pattern);
      if (match) { translated = render(...match.slice(1)); break; }
    }
    if (!translated && key.startsWith('·')) translated = `·${translateUI(key.slice(1), language)}`;
    if (!translated && key.includes(' · ')) translated = key.split(' · ').map(part => translateUI(part, language)).join(' · ');
    if (!translated && key.endsWith(':')) translated = UI_UK[key.slice(0, -1)] ? `${UI_UK[key.slice(0, -1)]}:` : null;
  }
  return translated && translated !== key ? text.replace(key, translated) : text;
}

(() => {
  let language = document.documentElement.lang === 'en' ? 'en' : 'uk';
  const sources = new WeakMap();
  const excluded = 'script, style, code, textarea, [data-no-i18n], .item-title, .lib-title, .lib-name, #uploadModalFilename, .dt-rec-title, .dt-person-name, .dt-overview, .dt-tagline, .dt-release-title, .dt-file-name, .title-episode-overview, .title-episode-card h3, .person-title-card h3, .dt-info h2, .dt-original';
  function applyText(node) {
    if (!node.parentElement || node.parentElement.closest(excluded)) return;
    const old = sources.get(node);
    const source = old && node.textContent === old.output ? old.source : node.textContent;
    const output = translateUI(source, language);
    sources.set(node, { source, output });
    if (node.textContent !== output) node.textContent = output;
  }
  const attributes = ['title', 'aria-label', 'placeholder', 'data-tip'];
  function applyElement(el) {
    if (el.matches(excluded) || el.closest('[data-no-i18n]')) return;
    let saved = sources.get(el) || {};
    for (const attr of attributes) {
      if (!el.hasAttribute(attr)) continue;
      const current = el.getAttribute(attr), old = saved[attr];
      const source = old && current === old.output ? old.source : current;
      const output = translateUI(source, language);
      saved[attr] = { source, output };
      if (current !== output) el.setAttribute(attr, output);
    }
    sources.set(el, saved);
  }
  function applyTree(root) {
    if (root.nodeType === Node.TEXT_NODE) { applyText(root); return; }
    if (root.nodeType !== Node.ELEMENT_NODE || root.matches(excluded)) return;
    applyElement(root);
    const walk = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walk.nextNode())) {
      if (node.nodeType === Node.TEXT_NODE) applyText(node);
      else applyElement(node);
    }
  }
  const observer = new MutationObserver(records => {
    for (const record of records) {
      if (record.type === 'childList') record.addedNodes.forEach(applyTree);
      else if (record.type === 'characterData') applyText(record.target);
      else applyElement(record.target);
    }
  });
  observer.observe(document.body, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: attributes });
  function setLanguage(next) {
    language = next === 'en' ? 'en' : 'uk';
    document.documentElement.lang = language;
    document.querySelectorAll('[data-ui-language]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.uiLanguage === language)));
    try { localStorage.setItem('torrenttube-language', language); } catch (e) {}
    applyTree(document.body);
  }
  document.querySelectorAll('[data-ui-language]').forEach(button => button.addEventListener('click', () => setLanguage(button.dataset.uiLanguage)));
  setLanguage(language);
})();
