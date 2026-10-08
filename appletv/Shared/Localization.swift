import Foundation
import Observation

/// The app's own language, chosen in Settings - Ukrainian unless the viewer
/// picks English. Independent of the Apple TV's system language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case uk, en
    var id: String { rawValue }
    /// Each language is named in itself, so it can be found in either.
    var name: String { self == .uk ? "Українська" : "English" }
    var locale: Locale { Locale(identifier: self == .uk ? "uk_UA" : "en_US") }
}

@Observable
final class Localizer {
    nonisolated(unsafe) static let shared = Localizer()
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.key)
            // The Top Shelf extension reads it from the shared group.
            #if os(tvOS)
            TopShelfStore.defaults.set(language.rawValue, forKey: Self.key)
            #endif
        }
    }
    static let key = "appLanguage"
    private init() {
        UserDefaults.standard.register(defaults: [Self.key: AppLanguage.uk.rawValue])
        #if os(tvOS)
        TopShelfStore.defaults.register(defaults: [Self.key: AppLanguage.uk.rawValue])
        let saved = UserDefaults.standard.string(forKey: Self.key) ?? TopShelfStore.defaults.string(forKey: Self.key)
        #else
        let saved = UserDefaults.standard.string(forKey: Self.key)
        #endif
        language = saved.flatMap(AppLanguage.init(rawValue:)) ?? .uk
    }
}

/// The text in the chosen language. The English text is the key; arguments
/// fill its %@ / %ld placeholders. Views that call it while drawing redraw
/// when the language changes.
func L(_ english: String, _ arguments: CVarArg...) -> String {
    let language = Localizer.shared.language
    let template = language == .uk ? (ukrainian[english] ?? english) : english
    return arguments.isEmpty ? template : String(format: template, locale: language.locale, arguments: arguments)
}

private let ukrainian: [String: String] = [
    // Touch interface
    "About": "Про застосунок",
    "Appearance": "Вигляд",
    "Choose a file": "Виберіть файл",
    "Clear recent searches": "Очистити нещодавні пошуки",
    "Done": "Готово",
    "Enable search on your server to discover more titles.": "Увімкніть пошук на сервері, щоб знаходити більше фільмів і серіалів.",
    "Favorites and viewing history stay on this device.": "Обране та історія перегляду зберігаються на цьому пристрої.",
    "No versions found. Try searching for this title.": "Версій не знайдено. Спробуйте пошук за назвою.",
    "Open device settings": "Відкрити налаштування пристрою",
    "Open-source licenses": "Ліцензії відкритого коду",
    "Playback paused while the app was in the background.": "Перегляд призупинено, поки застосунок був у фоні.",
    "Playback position": "Позиція відтворення",
    "Privacy": "Приватність",
    "Reconnect and resume": "Під’єднатися й продовжити",
    "Scan Network": "Пошук у мережі",
    "Scanning Network…": "Пошук сервера…",
    "Scan network": "Пошук у мережі",
    "Scanning network…": "Пошук сервера…",
    "Search unavailable": "Пошук недоступний",
    "Season": "Сезон",
    "Server": "Сервер",
    "Skip interval": "Крок перемотування",
    "Tap the heart on a title to save it here.": "Натисніть серце на сторінці фільму або серіалу, щоб додати його сюди.",
    "Titles on your server will appear here.": "Тут з’являться фільми та серіали з вашого сервера.",
    "Unable to play": "Не вдалося почати перегляд",
    "Update Torrent Tube on your server to stream on this device.": "Оновіть Torrent Tube на сервері, щоб дивитися на цьому пристрої.",
    "Use the same Wi-Fi as your server. Allow Local Network access in Settings.": "Під’єднайтеся до тієї ж мережі Wi-Fi, що й сервер. Дозвольте доступ до локальної мережі в налаштуваннях.",
    "Welcome": "Вітаємо",
    "Your library is empty": "Ваша медіатека порожня",
    "Read more": "Читати далі",
    "Show less": "Згорнути",
    "Saved": "Збережено",
    "Save": "Зберегти",

    // Tabs and shelves
    "Home": "Головна",
    "Movies": "Фільми",
    "TV Shows": "Серіали",
    "Cartoons": "Мультики",
    "Search": "Пошук",
    "Favorites": "Обране",
    "Library": "Медіатека",
    "Sync now": "Синхронізувати",
    "Syncing…": "Синхронізація…",
    "Save details and images for titles new on the server.": "Зберегти описи й зображення для нових назв на сервері.",
    "Rescan library": "Пересканувати медіатеку",
    "Match every title again on the server and save everything anew.": "Знову зіставити всі назви на сервері й зберегти все заново.",
    "Saving %ld of %ld…": "Збереження: %ld з %ld…",
    "The server is matching %ld titles…": "Сервер зіставляє назви: %ld…",
    "Not synced yet": "Ще не синхронізовано",
    "Synced %@ · %ld titles · data %@ · images %@": "Синхронізовано %@ · назв: %ld · дані %@ · зображення %@",
    "%ld files": "файлів: %ld",
    "Posters and details": "Постери та описи",
    "Refresh library metadata": "Оновити дані медіатеки",
    "Forget the saved posters and details and look them up again.": "Забути збережені постери й описи та знайти їх знову.",
    "Saved on this device: %ld titles · %@": "Збережено на пристрої: назв — %ld · %@",
    "New on your server": "Нове на вашому сервері",
    "Titles you download to the server appear here.": "Тут з’являються фільми, завантажені на сервер.",
    "Add to Favorites": "Додати в обране",
    "Remove from Favorites": "Прибрати з обраного",
    "No favorites yet": "Тут поки нічого немає",
    "Nothing of this type in Favorites yet.": "В обраному поки немає нічого такого типу.",
    "Press the heart on a title page, or hold Select on a poster, to keep it here.": "Натисніть ♡ на сторінці фільму або затисніть кнопку вибору на постері, щоб зберегти його тут.",
    "Settings": "Налаштування",
    "Documentaries": "Документальні",
    "Ukrainian": "Українське",
    "New to Explore": "Нове для перегляду",
    "Popular Now": "Популярне зараз",
    "New to explore": "Нове для перегляду",
    "Popular now": "Популярне зараз",
    "On your server": "На вашому сервері",
    "Continue Watching": "Продовжити перегляд",
    "Browse": "Розділи",
    "Refresh titles": "Оновити список",
    "Refresh": "Оновити",
    "All": "Усі",

    // Home and title pages
    "Play": "Дивитися",
    "Details": "Деталі",
    "Back": "Назад",
    "OK": "OK",
    "Cancel": "Скасувати",
    "Try again": "Спробувати ще",
    "Movie": "Фільм",
    "TV Show": "Серіал",
    "Cartoon": "Мультфільм",
    "Animated Series": "Мультсеріал",
    "%ld h %ld min": "%ld год %ld хв",
    "%ld min": "%ld хв",
    "Resume at %@": "Продовжити з %@",
    "Finding something to watch…": "Шукаємо, що подивитися…",
    "Your next movie night": "Ваш наступний кіновечір",
    "Explore your server’s catalog below.": "Каталог вашого сервера — нижче.",
    "Ready-to-watch titles from your server appear here.": "Тут з’являться готові до перегляду фільми з вашого сервера.",
    "Connect a media source on your server to start watching.": "Підключіть джерело медіа на сервері, щоб почати перегляд.",
    "Streaming unavailable": "Перегляд недоступний",
    "Update Torrent Tube on your server to stream on this Apple TV.": "Оновіть Torrent Tube на сервері, щоб дивитися на цьому Apple TV.",
    "Update your server to enable streaming on this Apple TV.": "Оновіть сервер, щоб дивитися на цьому Apple TV.",
    "Loading titles…": "Завантаження…",
    "Nothing here yet": "Тут поки порожньо",
    "Try another category or refresh your server’s catalog.": "Спробуйте інший розділ або оновіть каталог сервера.",
    "Trailer": "Трейлер",
    "Finding trailer…": "Шукаємо трейлер…",
    "No trailer": "Немає трейлера",
    "No trailer was found for this title.": "Трейлер для цієї назви не знайдено.",
    "Preparing trailer…": "Готуємо трейлер…",
    "Choose version": "Вибрати версію",
    "Finding versions…": "Шукаємо версії…",
    "Use this version": "Використати цю версію",
    "%ld seeders": "сідів: %ld",
    "Episodes": "Серії",
    "Season %ld": "Сезон %ld",
    "Season %ld · Episode %ld": "Сезон %ld · Серія %ld",
    "Loading episodes…": "Завантаження серій…",
    "Choose a version to see the episodes available to stream.": "Виберіть версію, щоб побачити серії, доступні для перегляду.",
    "Cast & Crew": "Актори та знімальна група",
    "Information": "Інформація",
    "More Like This": "Схожі",
    "Genres": "Жанри",
    "Country": "Країна",
    "Age rating": "Вікове обмеження",
    "Original title": "Оригінальна назва",
    "Writers": "Сценаристи",
    "Network": "Телеканал",
    "Director": "Режисер",
    "Creator": "Автор",

    // Search
    "Movies, TV shows, cartoons": "Фільми, серіали, мультфільми",
    "Recent searches": "Нещодавні пошуки",
    "Clear": "Очистити",
    "Space": "Пробіл",
    "Delete": "Видалити",
    "Keyboard language": "Мова клавіатури",
    "Type a title - results appear as you type.": "Введіть назву — результати з’являються під час введення.",
    "Searching…": "Пошук…",
    "Results for “%@”": "Результати для «%@»",
    "No results for “%@”": "Нічого не знайдено для «%@»",
    "Check the spelling or try a new search.": "Перевірте написання або спробуйте інший запит.",

    // Playback
    "Preparing your stream…": "Готуємо відео…",
    "Continue from %@?": "Продовжити з %@?",
    "Resume": "Продовжити",
    "Start from beginning": "Почати спочатку",
    "Choose a file for episode %ld": "Виберіть файл для серії %ld",
    "Choose an episode": "Виберіть серію",
    "This torrent contains no supported video files.": "У цьому торенті немає підтримуваних відеофайлів.",
    "This file could not be played. Try another release.": "Не вдалося відтворити файл. Спробуйте іншу версію.",
    "Show playback controls": "Показати керування",
    "Buffering…": "Буферизація…",
    "%ld%% ready": "Готово %ld%%",
    "Close player": "Закрити плеєр",
    "Close": "Закрити",
    "Pause": "Пауза",
    "Back %ld seconds": "Назад на %ld с",
    "Forward %ld seconds": "Вперед на %ld с",
    "Audio": "Аудіо",
    "Subtitles": "Субтитри",
    "Off": "Вимк.",
    "On": "Увімк.",
    "No tracks available yet.": "Доріжок поки немає.",

    // Connecting
    "Connect to your server": "Підключіться до свого сервера",
    "Enter the address of your Torrent Tube server.": "Вкажіть адресу свого сервера Torrent Tube.",
    "The server and this device must be on the same network.": "Сервер і цей пристрій мають бути в одній мережі.",
    "Server address": "Адреса сервера",
    "Example: %@": "Приклад: %@",
    "Connecting…": "Підключення…",
    "Connect": "Підключити",
    "This address belongs to another service.": "Ця адреса належить іншому сервісу.",
    "This server version is not supported. Update the app.": "Ця версія сервера не підтримується. Оновіть застосунок.",
    "Enter your server address.": "Введіть адресу сервера.",
    "Enter an HTTP or HTTPS server address, including its port if needed.": "Введіть адресу HTTP або HTTPS, з портом, якщо потрібно.",
    "This server address is invalid.": "Неправильна адреса сервера.",
    "Could not create the server URL.": "Не вдалося створити адресу запиту.",
    "The server returned an invalid playback URL.": "Сервер повернув неправильну адресу відео.",
    "No response from the server.": "Сервер не відповідає.",
    "This server requires authentication. This version supports direct LAN connections.": "Сервер вимагає входу. Ця версія підтримує лише пряме підключення в локальній мережі.",
    "Update Torrent Tube on your server to play trailers inside the app.": "Оновіть Torrent Tube на сервері, щоб дивитися трейлери в застосунку.",
    "Server request failed (HTTP %ld).": "Помилка запиту до сервера (HTTP %ld).",
    "The server returned an unexpected response. Check the address and server version.": "Сервер повернув неочікувану відповідь. Перевірте адресу та версію сервера.",

    // Settings
    "Language": "Мова",
    "App language": "Мова застосунку",
    "Menus, buttons and messages. Titles and descriptions come from your server’s catalog settings.": "Меню, кнопки та повідомлення. Назви й описи залежать від налаштувань каталогу на сервері.",
    "Home & Top Shelf": "Головна та Top Shelf",
    "Playback": "Відтворення",
    "Server & Storage": "Сервер і сховище",
    "Version %@": "Версія %@",
    "Top Shelf": "Top Shelf",
    "New titles": "Нові фільми",
    "Brand artwork": "Логотип",
    "Shown above the app on your Apple TV Home screen.": "Показується над застосунком на екрані Apple TV.",
    "Shown above the app when Torrent Tube is in the first row of your Apple TV Home screen.": "Показується над застосунком, коли Torrent Tube у першому ряду головного екрана Apple TV.",
    "New titles update when you open the app or refresh the catalog. If no artwork is available, the brand banner is shown.": "Нові фільми оновлюються, коли ви відкриваєте застосунок або оновлюєте каталог. Якщо зображень немає, показується логотип.",
    "New titles need a server with catalog search enabled. The brand banner is shown until then.": "Для нових фільмів на сервері має бути ввімкнений пошук у каталозі. До того часу показується логотип.",
    "Show": "Показувати",
    "Hide": "Приховати",
    "Display your unfinished titles on Home.": "Недодивлені фільми на головній.",
    "Display your unfinished titles on Home. Saved positions are kept.": "Недодивлені фільми на головній. Збережені позиції залишаються.",
    "Display your unfinished titles on Home. Title preview updates the banner as you move between titles.": "Недодивлені фільми на головній. Банер оновлюється під час перегляду.",
    "Choose how far the player moves with each skip. Audio and subtitles can be changed while a title is playing.": "Наскільки плеєр перемотує за одне натискання. Аудіо та субтитри можна змінювати під час відтворення.",
    "Look up library titles on TMDB. Matches are saved on this device, so the Library opens without waiting.": "Шукати назви медіатеки в TMDB. Знайдене зберігається на цьому пристрої, тому медіатека відкривається одразу.",
    "Saved playback positions for this server will be removed from this device. Your server files stay untouched.": "Збережені позиції для цього сервера буде видалено з цього пристрою. Ваші файли на сервері залишаться без змін.",
    "Title preview while browsing": "Банер під час гортання",
    "Update the Home banner as you browse titles.": "Банер на головній змінюється під час перегляду.",
    "Update the Home banner as you move between movie cards.": "Банер на головній змінюється, коли ви переходите між картками.",
    "Look up library titles on TMDB and save them on this device.": "Шукати дані на TMDB і зберігати на цьому пристрої.",
    "Save details and images for new titles on the server.": "Зберегти деталі та постери для нових фільмів на сервері.",
    "Match all titles again on the server and update details.": "Перевірити всі фільми на сервері та оновити дані.",
    "Skip": "Перемотування",
    "Skip Intro": "Пропустити заставку",
    "Full Screen": "На весь екран",
    "The tracker didn't hand over this release: it was probably removed or replaced. Choose another version. If no release opens at all, log this tracker in again in Jackett (port 9117).": "Трекер не віддав цей реліз: імовірно, його видалили або замінили. Виберіть іншу версію. Якщо не відкривається жоден реліз, увійдіть у цей трекер у Jackett ще раз (порт 9117).",
    "Connecting to %@…": "Підключення до %@…",
    "The server is not responding": "Сервер не відповідає",
    "Check that the server is on and this device is on the same Wi-Fi network.": "Перевірте, що сервер увімкнений, а цей пристрій у тій самій мережі Wi‑Fi.",
    "No network connection": "Немає підключення до мережі",
    "Connect to the same Wi-Fi network as your server.": "Підключіться до тієї ж мережі Wi‑Fi, що й сервер.",
    "Can’t reach this address": "Не вдається знайти цю адресу",
    "Check the address and port, for example http://192.168.0.102:5058.": "Перевірте адресу й порт, наприклад http://192.168.0.102:5058.",
    "This address is not valid": "Неправильна адреса",
    "Use an address like http://192.168.0.102:5058.": "Вкажіть адресу на зразок http://192.168.0.102:5058.",
    "Couldn’t connect to the server": "Не вдалося підключитися до сервера",
    "%ld seconds": "%ld секунд",
    "Choose how far the player moves with each skip.": "Наскільки плеєр перемотує за одне натискання.",
    "Audio and subtitles can be changed while a title is playing. Available tracks depend on the video file.": "Аудіо й субтитри можна змінити під час перегляду. Доступні доріжки залежать від відеофайлу.",
    "Player licenses": "Ліцензії плеєра",
    "Change server": "Змінити сервер",
    "Connect to a different Torrent Tube server.": "Підключитися до іншого сервера Torrent Tube.",
    "Refresh catalog": "Оновити каталог",
    "Refreshing…": "Оновлення…",
    "Reload Home titles and update Top Shelf.": "Перезавантажити фільми на головній і оновити Top Shelf.",
    "Catalog updated.": "Каталог оновлено.",
    "Clear viewing history": "Очистити історію переглядів",
    "Remove saved positions for this server on this Apple TV.": "Видалити збережені позиції для цього сервера на цьому Apple TV.",
    "Clear viewing history?": "Очистити історію переглядів?",
    "Forget the terms shown on the Search screen.": "Забути запити, показані на екрані пошуку.",
    "None": "Немає",
    "Clear history": "Очистити історію",
    "Saved playback positions for this server will be removed from this Apple TV. Your server files stay untouched.": "Збережені позиції для цього сервера буде видалено з цього Apple TV. Файли на сервері не зміняться.",
    "License file unavailable.": "Файл ліцензії недоступний.",
    "Playback uses VideoLAN’s VLCKit library. Source: %@": "Відтворення використовує бібліотеку VLCKit від VideoLAN. Код: %@",
    "In your library": "У медіатеці",
    "Torrents": "Торенти",
    "No additional torrent titles.": "Інших фільмів у торентах немає.",
    "Searching your library. Torrent search is disabled on this server.": "Пошук у медіатеці. Пошук торентів на сервері вимкнено.",
    "Stop preview": "Зупинити трейлер",
    "Mute preview": "Вимкнути звук трейлера",
    "Unmute preview": "Увімкнути звук трейлера",
    "Previous featured title": "Попередній банер",
    "Next featured title": "Наступний банер",
    "Featured title %ld of %ld": "Банер %ld із %ld",
    "Autoplay Home trailers": "Автовідтворення трейлерів на головній",
    "Play muted previews after five seconds in the Home banner.": "Відтворювати трейлери без звуку після п’яти секунд у банері на головній.",
    "No trailer is available for this title.": "Трейлер недоступний.",
]
