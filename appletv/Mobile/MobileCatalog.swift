import SwiftUI

enum MobileStyle {
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.2)
    static func itemTitle(_ mobileFont: Font, weight: Font.Weight = .medium) -> Font {
        #if os(macOS)
        .system(size: 16, weight: weight)
        #else
        mobileFont
        #endif
    }
}

/// Text in the banner. iOS text styles are much smaller on the Mac, so the
/// Mac gets its own, larger sizes; iPhone and iPad keep the system styles.
enum HeroFont {
    #if os(macOS)
    static let kind = Font.system(size: 13, weight: .bold)
    static let facts = Font.system(size: 14, weight: .medium)
    static let overview = Font.system(size: 15)
    static let button = Font.system(size: 15, weight: .semibold)
    static let buttonHeight: CGFloat = 40
    static let chip = Font.system(size: 16, weight: .semibold)
    static let chipPadding = EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
    static func titleSize(regular: Bool) -> CGFloat { 44 }
    static func title(regular: Bool) -> Font { .system(size: titleSize(regular: regular), weight: .bold) }
    #else
    static let kind = Font.caption.bold()
    static let facts = Font.subheadline
    static let overview = Font.subheadline
    static let button = Font.headline
    static let buttonHeight: CGFloat = 36
    static let chip = Font.subheadline.weight(.semibold)
    static let chipPadding = EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
    static func titleSize(regular: Bool) -> CGFloat { regular ? 40 : 30 }
    static func title(regular: Bool) -> Font { .system(size: titleSize(regular: regular), weight: .bold) }
    #endif
}

/// The text in the banner - kind, name, facts, description, then the
/// buttons - in the same order and place on Home and on a title page, so
/// opening a title never moves it.
struct HeroInfo<Actions: View>: View {
    let kind: String?
    let title: String
    let item: MediaItem
    let details: Details?
    var overview: String?
    /// The title's tagline: the heading of its description.
    var tagline: String? = nil
    var expanded = false
    /// A long description: "Read more" right under it opens it in full.
    var toggleMore: (() -> Void)? = nil
    /// How much taller the open description is than its three lines - the
    /// title page grows its banner by this, so the text opens downward.
    /// Title pages show the credits at the right (iPad and Mac).
    var showsCredits = false
    var growth: Binding<CGFloat>? = nil
    @State private var collapsedHeight: CGFloat = 0
    @ViewBuilder let actions: () -> Actions
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        // In the way of the Apple TV app: a modest title, one line of kind and
        // genres, the description, then year, length and rating, then buttons;
        // the credits on the right on larger screens.
        HStack(alignment: .bottom, spacing: 40) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(HeroFont.title(regular: sizeClass == .regular))
                    .lineLimit(2).minimumScaleFactor(0.7).tightTitleLines(size: HeroFont.titleSize(regular: sizeClass == .regular))
                    .frame(maxWidth: 760, alignment: .leading)
                HStack(spacing: 8) {
                    Text(BannerText.subtitle(kind: kind, details: details)).lineLimit(1)
                    if let certification = details?.certification, !certification.isEmpty {
                        Text(certification).font(HeroFont.facts.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    }
                }
                .font(HeroFont.facts).foregroundStyle(.white.opacity(0.85)).padding(.top, 12)
                if (tagline ?? "").isEmpty == false || (overview ?? "").isEmpty == false {
                    VStack(alignment: .leading, spacing: 4) {
                        if let tagline, !tagline.isEmpty {
                            Text(tagline).font(HeroFont.overview.weight(.semibold)).foregroundStyle(.white.opacity(0.9)).lineLimit(2)
                        }
                        if let overview, !overview.isEmpty { description(overview) }
                    }
                    .frame(maxWidth: 560, alignment: .leading).padding(.top, 12)
                }
                HStack(spacing: 10) {
                    let facts = BannerText.facts(details: details)
                    if !facts.isEmpty { Text(facts) }
                    if let rating = item.rating, rating > 0 {
                        Label { Text(String(format: "%.1f", rating)) } icon: { Image(systemName: "star.fill").foregroundStyle(MobileStyle.gold) }
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(HeroFont.facts).foregroundStyle(.white.opacity(0.7)).padding(.top, 10)
                HStack(spacing: 10) { actions() }.padding(.top, 18)
            }
            if showsCredits, sizeClass == .regular {
                Spacer(minLength: 0)
                let credits = BannerText.credits(details: details)
                if !credits.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(credits, id: \.label) { line in
                            (Text(line.label + " ").foregroundStyle(.white.opacity(0.55)) + Text(line.names).foregroundStyle(.white.opacity(0.9)))
                                .lineLimit(2)
                        }
                    }
                    .font(HeroFont.facts).frame(maxWidth: 320, alignment: .leading)
                }
            }
        }
    }

    private func description(_ overview: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(overview).font(HeroFont.overview).foregroundStyle(.white.opacity(0.75))
                .lineLimit(expanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: expanded)
                // The three-line height, from a hidden copy of the current text.
                .background(alignment: .topLeading) {
                    Text(overview).font(HeroFont.overview).lineLimit(3).hidden()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { collapsedHeight = $0 }
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                    growth?.wrappedValue = expanded ? max(0, height - collapsedHeight) : 0
                }
                .onChange(of: collapsedHeight) { _, _ in
                    if !expanded { growth?.wrappedValue = 0 }
                }
            if let toggleMore {
                Button(L(expanded ? "Show less" : "Read more"), action: toggleMore)
                    .font(HeroFont.overview.weight(.semibold)).foregroundStyle(.white)
                    .hapticButtonStyle(PlainButtonStyle())
            }
        }
    }
}

/// One side margin for a whole screen: 16 on iPhone, 32 on iPad - hero text,
/// shelf titles and the first poster all start on it.
private struct MobileEdgeKey: EnvironmentKey { static let defaultValue: CGFloat = 16 }
extension EnvironmentValues {
    var mobileEdge: CGFloat {
        get { self[MobileEdgeKey.self] }
        set { self[MobileEdgeKey.self] = newValue }
    }
}

extension View {
    /// iPhone in landscape: the page - its banner most of all - runs under the
    /// side insets, edge to edge; text and rows keep the insets as margin.
    func sidesUnderInsets() -> some View { modifier(SidesUnderInsets()) }
}

private struct SidesUnderInsets: ViewModifier {
    @Environment(\.mobileEdge) private var edge
    func body(content: Content) -> some View {
        #if os(iOS)
        // iPhone only: on iPad the side inset is the sidebar's room.
        if UIDevice.current.userInterfaceIdiom == .phone {
            GeometryReader { proxy in
                content
                    .environment(\.mobileEdge, edge + max(proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing))
                    .ignoresSafeArea(edges: .horizontal)
            }
        } else { content }
        #else
        content
        #endif
    }
}

/// "Movie", "TV Show", "Cartoon" or "Animated Series" - the eyebrow over a title.
func mobileKind(_ item: MediaItem, _ details: Details?) -> String? {
    let type = details?.mediaType ?? item.mediaType
    if details?.kind == "Cartoon" { return type == "tv" ? L("Animated Series") : L("Cartoon") }
    switch type {
    case "tv": return L("TV Show")
    case "movie": return L("Movie")
    default: return nil
    }
}

struct MobileArtwork: View {
    let url: String?
    var ratio: CGFloat = 2 / 3
    var fit = false
    /// The title: it picks the branded placeholder's color.
    var seed = ""
    var body: some View {
        Color(white: 0.12).aspectRatio(ratio, contentMode: .fit)
            .overlay {
                PosterArtwork(url: url.map { higherResolution($0, backdrop: ratio > 1) }.flatMap(URL.init(string:)), fit: fit, seed: seed)
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Full-height hero artwork, centered on iPhone.
/// A hero's art, its top edge faded so it melts into the fill that `pulledFill` keeps behind the page.
struct HeroArtFrame<Art: View>: View {
    let height: CGFloat
    @ViewBuilder let art: Art
    static var feather: CGFloat { 70 }
    var body: some View {
        art.frame(height: height)
            .mask(VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom).frame(height: Self.feather)
                Color.white
            })
            // After the mask: the mask clipped the copy drawn under the sidebar.
            .extendsUnderSidebar()
    }
}

/// Room above the page for the refresh spinner, below the bar. The hero cancels it with a negative top padding.
let refreshSpinnerRoom: CGFloat = 150

extension View {
    /// Pulled down past the top (or while the refresh spinner holds the page down), the plain background
    /// would show above the hero. This keeps a blurred copy of the art behind the scroll view, so it never
    /// moves with the content and never leaves a stripe. It shows only while the page is at its top.
    func pulledFill<Art: View>(height: CGFloat, @ViewBuilder art: () -> Art) -> some View {
        modifier(PulledFill(height: height, art: art()))
    }
}

private struct PulledFill<Art: View>: ViewModifier {
    let height: CGFloat
    let art: Art
    @State private var atTop = true
    @State private var pulled = false
    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top <= 1 } action: { _, new in atTop = new }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top < -12 } action: { _, new in pulled = new }
            #if os(iOS)
            // The system spinner sits under the hero, so it is hidden. This one is drawn on top, below the bar.
            .overlay(alignment: .top) {
                ProgressView().tint(.white).controlSize(.regular)
                    .padding(.top, 128)
                    .opacity(pulled ? 1 : 0).animation(.easeOut(duration: 0.15), value: pulled)
                    .allowsHitTesting(false).ignoresSafeArea(edges: .top)
            }
            #endif
            .background(alignment: .top) {
                // Moved up out of the screen, so the blur's own faded edge is never seen.
                art.frame(height: height).drawingGroup().blur(radius: 70).offset(y: -90)
                    .frame(height: 480, alignment: .top).clipped()
                    .opacity(atTop ? 1 : 0).allowsHitTesting(false)
                    .ignoresSafeArea(edges: .top)
            }
    }
}

extension View {
    /// iPadOS 26: the banner goes on under the glass sidebar, mirrored and
    /// blurred - as in Apple's TV app. Earlier systems keep the plain banner.
    @ViewBuilder func extendsUnderSidebar() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) { backgroundExtensionEffect() } else { self }
    }
}

/// The banner on screen now: the iPad's sidebar shows it, blurred - as in
/// Apple's TV app.
@MainActor @Observable
final class SidebarArt {
    var url: String?
}

/// The iPad sidebar's background: the current banner, blurred and faint.
struct SidebarArtBackground: View {
    @Environment(SidebarArt.self) private var art
    var body: some View {
        ZStack {
            AppBackground()
            HeroBackdrop(url: art.url.flatMap { URL(string: higherResolution($0, backdrop: true)) })
                // Ambient: a soft wash of the banner's colors, not the picture.
                .blur(radius: 80)
                .opacity(0.45)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct MobileBackdrop: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SidebarArt.self) private var sidebarArt: SidebarArt?
    let url: String?
    var nextURL: String? = nil
    var placeholder: String? = nil
    var body: some View {
        HeroBackdrop(url: url.flatMap { URL(string: higherResolution($0, backdrop: true)) },
                     nextURL: nextURL.flatMap { URL(string: higherResolution($0, backdrop: true)) }, alignment: sizeClass == .compact ? .center : .top,
                     placeholder: placeholder)
            // The iPad's sidebar shows this banner, blurred.
            .onAppear { if sizeClass == .regular { sidebarArt?.url = url } }
            .onChange(of: url) { _, new in if sizeClass == .regular { sidebarArt?.url = new } }
    }
}

/// Rating with a golden star, year and length - one line under a title.
struct MobileFacts: View {
    let item: MediaItem
    let details: Details?
    var body: some View {
        HStack(spacing: 10) {
            if let rating = item.rating, rating > 0 {
                Label { Text(String(format: "%.1f", rating)).fontWeight(.semibold) } icon: {
                    Image(systemName: "star.fill").foregroundStyle(MobileStyle.gold)
                }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.white.opacity(0.16), in: Capsule())
            }
            if let certification = details?.certification, !certification.isEmpty {
                Text(certification).font(.caption.bold())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.6), lineWidth: 1))
            }
            Text(facts.joined(separator: " · ")).lineLimit(1)
        }
        .font(HeroFont.facts).foregroundStyle(.white.opacity(0.85))
    }
    private var facts: [String] {
        var list: [String] = []
        if let year = details?.year, !year.isEmpty { list.append(year) }
        if let runtime = details?.runtime, runtime > 0 { list.append(runtime >= 60 ? L("%ld h %ld min", runtime / 60, runtime % 60) : L("%ld min", runtime)) }
        if let genres = details?.genres, !genres.isEmpty { list.append(genres.prefix(2).joined(separator: ", ")) }
        return list
    }
}

struct MobileCard: View {
    let item: MediaItem
    var onFocus: (MediaItem) -> Void = { _ in }
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Environment(MobileContext.self) private var context
    var body: some View {
        let value = catalog.resolved(item)
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 8) {
                MobileArtwork(url: value.poster, seed: value.displayTitle)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)) }
                    .overlay(alignment: .topTrailing) {
                        if favorites.contains(value, server: context.api.baseURL) {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(.white)
                                .padding(6).background(.black.opacity(0.55), in: Circle()).padding(6)
                        }
                    }
                Text(value.displayTitle).font(MobileStyle.itemTitle(.subheadline.weight(.medium))).lineLimit(2, reservesSpace: true)
                    .foregroundStyle(.primary).multilineTextAlignment(.leading)
            }.contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle()).accessibilityLabel(value.displayTitle)
        .onHover { hovering in if hovering { onFocus(value) } }
        .contextMenu {
            let saved = favorites.contains(value, server: context.api.baseURL)
            Button {
                Task {
                    // Its details decide the Favorites tab: movie, show or cartoon.
                    if !saved { await catalog.loadDetails(item, api: context.api, config: context.config) }
                    favorites.toggle(value, details: catalog.details[item.title], server: context.api.baseURL)
                }
            } label: {
                Label(saved ? L("Remove from Favorites") : L("Add to Favorites"), systemImage: saved ? "heart.slash" : "heart")
            }
        }
        .task(id: item.id) { await catalog.enrich([item], api: context.api, config: context.config) }
    }
}

/// A light dip while a poster is pressed - the touch answer to tvOS focus.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// What every catalog view needs from the connected server.
@Observable final class MobileContext {
    let api: TorrentTubeAPI
    let config: ServerConfig
    init(api: TorrentTubeAPI, config: ServerConfig) { self.api = api; self.config = config }
}

struct MobileGrid: View {
    @Environment(\.mobileEdge) private var edge
    let items: [MediaItem]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        // Three posters across an iPhone, more on an iPad.
        let minimum: CGFloat = typeSize.isAccessibilitySize ? 220 : (sizeClass == .regular ? 160 : 104)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: 240), spacing: 14)], alignment: .leading, spacing: 22) {
            ForEach(items) { MobileCard(item: $0) }
        }.padding(.horizontal, edge)
    }
}

struct MobileShelf: View {
    @Environment(\.mobileEdge) private var edge
    let title: String
    let items: [MediaItem]
    var titleFont: Font? = nil
    var onFocus: (MediaItem) -> Void = { _ in }
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 128
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(titleFont ?? (sizeClass == .regular ? .title2.bold() : .title3.bold())).padding(.horizontal, edge)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { MobileCard(item: $0, onFocus: onFocus).frame(width: min(cardWidth * (sizeClass == .regular ? 1.3 : 1), 240)) }
                }.padding(.horizontal, edge)
            }.scrollIndicators(.hidden)
        }
    }
}

/// Category tabs inside a screen - one capsule each, the current one filled.
struct MobileChips: View {
    @Environment(\.mobileEdge) private var edge
    let options: [(String, String)]
    @Binding var selected: String
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { key, label in
                    let current = selected == key
                    Button { withAnimation(.snappy) { selected = key } } label: {
                        Text(L(label)).font(HeroFont.chip)
                            .padding(HeroFont.chipPadding)
                            .foregroundStyle(current ? .black : .white)
                            .background(current ? Color.white : Color.white.opacity(0.12), in: Capsule())
                    }
                    .hapticButtonStyle(PlainButtonStyle())
                    .accessibilityAddTraits(current ? .isSelected : [])
                    .accessibilityIdentifier("chip-\(key)")
                }
            }.padding(.horizontal, edge)
        }.scrollIndicators(.hidden)
    }
}

struct MobileError: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(L("Try again"), action: retry).hapticButtonStyle(BorderedButtonStyle()).frame(minHeight: 44)
        }.frame(maxWidth: .infinity).padding()
    }
}

/// A spinner in the middle of the space - never in a corner.
struct MobileLoading: View {
    let text: String
    var body: some View { ProgressView(text).frame(maxWidth: .infinity, minHeight: 280) }
}

struct MobileHome: View {
    @Environment(\.mobileEdge) private var edge
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @Environment(ResumeHistory.self) private var history
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("showContinueWatching") private var showContinue = true
    @AppStorage("previewFocusedTitle") private var previewTitle = true
    @State private var previewed: MediaItem?
    @State private var playback: PlaybackRequest?
    @State private var serverNotice = false
    @State private var trailer: Trailer?
    @State private var findingTrailer = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var featuredIndex = 0
    @State private var heroVisible = true
    @State private var overviewExpanded = false
    @State private var heroGrowth: CGFloat = 0
    /// iPad: the buttons left no room for the page dots, so they sit in the top bar.
    @State private var dotsOnTop = false
    @GestureState private var draggingHero = false
    @State private var trackpadScrolling = false
    private let feeds = [("new", "New to Explore"), ("popular", "Popular Now"), ("movies", "Movies"), ("tv", "TV Shows"), ("cartoons", "Cartoons"), ("ukrainian", "Ukrainian")]
    private var featuredItems: [MediaItem] {
        catalog.homeFeatured.isEmpty ? catalog.library.prefix(HomeFeaturedSelection.limit).map(libraryItem) : catalog.homeFeatured
    }
    private var featured: MediaItem? {
        ((previewTitle ? previewed : nil) ?? (featuredItems.isEmpty ? nil : featuredItems[min(featuredIndex, featuredItems.count - 1)])).map(catalog.resolved)
    }
    private func previewShelfItem(_ item: MediaItem) {
        #if os(macOS)
        guard heroVisible else { return }
        #endif
        if previewTitle { previewed = item }
    }
    private var rotationCycle: String? {
        guard featuredItems.count > 1, heroVisible, scenePhase == .active, playback == nil,
              !serverNotice, !draggingHero, !trackpadScrolling, !overviewExpanded, !previewTitle || previewed == nil else { return nil }
        return "\(featuredIndex):" + featuredItems.map(\.id).joined(separator: "|")
    }
    var body: some View {
        GeometryReader { screen in
            let heroHeight = HeroLayout.bannerHeight(screenHeight: screen.size.height, screenWidth: screen.size.width, sizeClass: sizeClass)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if let featured { hero(featured, height: heroHeight).padding(.top, -refreshSpinnerRoom) }
                    else if catalog.loading.contains("new") || catalog.libraryLoading { MobileLoading(text: L("Finding something to watch…")).padding(.top, 120) }
                    if showContinue { continueWatching }
                    ForEach(feeds, id: \.0) { feed, title in
                        if let items = catalog.rows[feed], !items.isEmpty {
                            MobileShelf(title: L(title), items: Array(items.prefix(24)), onFocus: previewShelfItem)
                        } else if let error = catalog.errors[feed] {
                            MobileError(message: "\(L(title)): \(error)") { Task { await catalog.loadFeed(feed, api: api, config: config, refresh: true) } }
                        }
                    }
                    if !catalog.library.isEmpty {
                        MobileShelf(title: L("New on your server"), items: catalog.library.prefix(24).map(libraryItem), onFocus: previewShelfItem)
                    }
                    if let error = catalog.libraryError { MobileError(message: error) { Task { await catalog.loadLibrary(api: api) } } }
                    if !config.searchEnabled, catalog.library.isEmpty, !catalog.libraryLoading, catalog.libraryError == nil {
                        ContentUnavailableView(L("Your library is empty"), systemImage: "film", description: Text(L("Titles on your server will appear here.")))
                            .frame(maxWidth: .infinity)
                    }
                }.padding(.bottom, 24)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                #if os(macOS)
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
                #else
                geometry.contentOffset.y + geometry.contentInsets.top < heroHeight / 2
                #endif
            } action: { _, visible in heroVisible = visible }
            .contentMargins(.top, refreshSpinnerRoom, for: .scrollContent)
            .pulledFill(height: heroHeight) { if let featured { homeHeroArt(featured, details: catalog.details[featured.title]) } }
        }
        // The hero runs under the status bar, like the Apple TV app.
        .ignoresSafeArea(edges: .top)
        .toolbar {
            if sizeClass == .compact || dotsOnTop, featuredItems.count > 1 {
                ToolbarItem(placement: .principal) { carouselDots }
            }
        }
        .refreshable { await load(refresh: true) }
        .task { await load(refresh: false) }
        .task(id: featured?.id) { if let featured { await catalog.loadDetails(featured, api: api, config: config) } }
        .onChange(of: featured?.id) { _, _ in
            overviewExpanded = false
            heroGrowth = 0
        }
        .task(id: rotationCycle) {
            guard rotationCycle != nil else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled else { return }
            nextFeatured()
        }
        .fullScreenCover(item: $playback) { MobilePlayback(request: $0, api: api) }
        .fullScreenCover(item: $trailer) { MobileTrailer(trailer: $0, api: api) }
        #if DEBUG
        // Screenshots of the player without clicking: -macOpen play
        .task {
            guard UserDefaults.standard.string(forKey: "macOpen") == "play" else { return }
            for _ in 0..<40 where catalog.library.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            if let first = catalog.library.first(where: { !$0.isTorrent && $0.kind == "movie" && $0.files == 1 }) {
                let item = libraryItem(first)
                playback = PlaybackRequest(source: item.source, title: item.displayTitle, artwork: item.poster)
            }
        }
        #endif
        .alert(L("Streaming unavailable"), isPresented: $serverNotice) { Button(L("OK"), role: .cancel) {} } message: {
            Text(L("Update Torrent Tube on your server to stream on this device."))
        }
    }
    private var nextHeroArtwork: String? {
        guard featuredItems.count > 1, !(previewTitle && previewed != nil) else { return nil }
        let next = catalog.resolved(featuredItems[(min(featuredIndex, featuredItems.count - 1) + 1) % featuredItems.count])
        return catalog.details[next.title]?.backdrop ?? next.poster
    }

    private func homeHeroArt(_ item: MediaItem, details: Details?) -> some View {
        ZStack {
            MobileBackdrop(url: details?.backdrop ?? item.poster, nextURL: nextHeroArtwork, placeholder: item.displayTitle)
            LinearGradient(stops: [.init(color: .black.opacity(0.6), location: 0), .init(color: .clear, location: 0.22),
                                   .init(color: .black.opacity(0.75), location: 0.8),
                                   .init(color: .black, location: 1.0)], startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [.init(color: .black.opacity(0.7), location: 0),
                                   .init(color: .clear, location: 0.6)], startPoint: .leading, endPoint: .trailing)
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.45),
                .init(color: .white.opacity(0.85), location: 0.65),
                .init(color: .white.opacity(0.35), location: 0.86),
                .init(color: .clear, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
        )

    }

    private func hero(_ item: MediaItem, height: CGFloat) -> some View {
        let details = catalog.details[item.title]
        return ZStack(alignment: .bottomLeading) {
            HeroArtFrame(height: height) { homeHeroArt(item, details: details) }
            .frame(maxHeight: .infinity, alignment: .top)
            HeroInfo(kind: mobileKind(item, details), title: details?.title ?? item.displayTitle, item: item, details: details,
                     overview: details?.overview ?? item.overview, tagline: details?.tagline, expanded: overviewExpanded,
                     toggleMore: (details?.overview ?? item.overview ?? "").count > 160 ? { overviewExpanded.toggle() } : nil,
                     growth: $heroGrowth) {
                if sizeClass == .regular, featuredItems.count > 1 {
                    // The dots after the buttons while they fit; else in the top bar,
                    // as on iPhone - the Trailer button never wraps under them.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            heroButtons(item, details: details)
                            Spacer(minLength: 16)
                            carouselDots
                        }.onAppear { dotsOnTop = false }
                        HStack(spacing: 10) { heroButtons(item, details: details) }
                            .onAppear { dotsOnTop = true }
                        // Still short of room: Trailer as an icon, as on iPhone.
                        HStack(spacing: 10) { heroButtons(item, details: details, iconTrailer: true) }
                            .onAppear { dotsOnTop = true }
                    }
                } else {
                    heroButtons(item, details: details)
                }
            }
            .padding(.horizontal, edge).padding(.bottom, 12)
        }
        .frame(height: height + heroGrowth)
        .mask(Rectangle().padding(.top, -1500))  // sides and bottom only: the fill above the top edge shows when pulled down
        #if os(macOS)
        .background(MacCarouselTrackpad(enabled: featuredItems.count > 1 && heroVisible && scenePhase == .active,
                                       changePage: changeFeatured, trackingChanged: { trackpadScrolling = $0 }))
        #endif
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .updating($draggingHero) { value, dragging, _ in
                    dragging = abs(value.translation.width) > abs(value.translation.height)
                }
                .onEnded { value in
                    let x = value.translation.width, y = value.translation.height
                    guard abs(x) > 40, abs(x) > abs(y) * 1.5 else { return }
                    changeFeatured(x < 0 ? 1 : -1)
                }
        )
    }
    @ViewBuilder private func heroButtons(_ item: MediaItem, details: Details?, iconTrailer: Bool = false) -> some View {
        Button {
            if config.supportsPlayback {
                playback = PlaybackRequest(source: item.source, title: item.displayTitle,
                                           artwork: details?.backdrop ?? item.poster, tmdbID: details?.tmdbId ?? item.tmdbId,
                                           seasonSources: item.librarySources)
            } else { serverNotice = true }
        } label: {
            Label(L("Play"), systemImage: "play.fill").font(HeroFont.button)
                .frame(maxWidth: sizeClass == .regular ? 220 : .infinity, minHeight: HeroFont.buttonHeight)
        }
        .primaryHeroButton()
        .accessibilityIdentifier("hero-play")
        NavigationLink(value: item) {
            Label(L("Details"), systemImage: "info.circle").font(HeroFont.button)
                .padding(.horizontal, sizeClass == .regular ? 16 : 0)
                .frame(minWidth: sizeClass == .regular ? 140 : nil, maxWidth: sizeClass == .regular ? nil : .infinity, minHeight: HeroFont.buttonHeight)
        }
        .hapticButtonStyle(BorderedButtonStyle()).tint(.white)
        .layoutPriority(sizeClass == .regular ? 1 : 0)  // iPad: when room is short, Play gives up width first
        .accessibilityIdentifier("featured-details")
        // iPad and Mac: the trailer, as on Apple TV.
        if sizeClass == .regular {
            Button {
                findingTrailer = true
                Task {
                    defer { findingTrailer = false }
                    trailer = try? await TrailerChoice.find(title: item.title, year: details?.year, known: details?.trailers ?? [], api: api)
                }
            } label: {
                HStack(spacing: 8) {
                    Group { if findingTrailer { ProgressView() } else { Image(systemName: "play.rectangle") } }
                    if !iconTrailer { Text(L("Trailer")).lineLimit(1) }
                }
                .font(HeroFont.button).padding(.horizontal, 16).frame(minHeight: HeroFont.buttonHeight)
            }
            .hapticButtonStyle(BorderedButtonStyle()).tint(.white).disabled(findingTrailer)
            .layoutPriority(1).accessibilityLabel(L("Trailer"))
            .accessibilityIdentifier("featured-trailer")
        }
    }
    private var carouselDots: some View {
        MobileHeroPageDots(count: featuredItems.count, current: featuredIndex, next: nextFeatured)
    }
    private func nextFeatured() {
        changeFeatured(1)
    }
    private func changeFeatured(_ step: Int) {
        guard featuredItems.count > 1 else { return }
        previewed = nil
        featuredIndex = (min(featuredIndex, featuredItems.count - 1) + step + featuredItems.count) % featuredItems.count
    }
    @ViewBuilder private var continueWatching: some View {
        let entries = history.entries.filter { $0.server == api.baseURL.absoluteString }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Continue Watching")).font(sizeClass == .regular ? .title2.bold() : .title3.bold()).padding(.horizontal, edge)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(entries) { entry in
                            Button { playback = PlaybackRequest(source: entry.source, title: entry.title, artwork: entry.artwork) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    MobileArtwork(url: entry.artwork, ratio: 16 / 9, seed: entry.title)
                                        .overlay(alignment: .bottom) {
                                            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).frame(height: 44)
                                        }
                                        .overlay(alignment: .bottomLeading) {
                                            ProgressView(value: min(entry.seconds, entry.duration), total: max(1, entry.duration)).tint(.white)
                                                .padding(.horizontal, 10).padding(.bottom, 8)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text(entry.title).font(MobileStyle.itemTitle(.subheadline.weight(.semibold), weight: .semibold)).lineLimit(1)
                                    Text(L("Resume at %@", entry.displayPosition)).font(.caption).foregroundStyle(.secondary)
                                }.frame(width: 250).contentShape(Rectangle())
                            }.hapticButtonStyle(PlainButtonStyle())
                        }
                    }.padding(.horizontal, edge)
                }.scrollIndicators(.hidden)
            }
        }
    }
    private func load(refresh: Bool) async {
        await catalog.loadLibrary(api: api)
        Task { await catalog.syncLibrary(api: api, config: config) }  // new library titles only
        await catalog.loadFeed("new", api: api, config: config, refresh: refresh)
        await withTaskGroup(of: Void.self) { group in
            for (feed, _) in feeds.dropFirst() { group.addTask { await catalog.loadFeed(feed, api: api, config: config, refresh: refresh) } }
        }
    }
}

private struct MobileHeroPageDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let count: Int
    let current: Int
    let next: () -> Void
    var body: some View {
        Button(action: next) {
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule().fill(.white.opacity(index == current ? 1 : 0.35))
                        .frame(width: index == current ? 16 : 5, height: 5)
                }
            }.padding(.horizontal, 10).frame(height: 44)
        }
        .hapticButtonStyle(PlainButtonStyle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: current)
        .accessibilityLabel(L("Featured title %ld of %ld", current + 1, count))
        .accessibilityHint(L("Next featured title"))
        .accessibilityIdentifier("hero-next")
    }
}

/// Movies or TV Shows: chips for the sub-categories, then a poster grid.
struct MobileCategory: View {
    let options: [(String, String)]
    let api: TorrentTubeAPI
    let config: ServerConfig
    @Environment(CatalogStore.self) private var catalog
    @State private var selected: String
    init(options: [(String, String)], api: TorrentTubeAPI, config: ServerConfig) {
        self.options = options; self.api = api; self.config = config
        _selected = State(initialValue: options.first?.0 ?? "movies")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if options.count > 1 { MobileChips(options: options, selected: $selected) }
                let items = selected == "library" ? catalog.library.map(libraryItem) : (catalog.rows[selected] ?? [])
                if items.isEmpty && (catalog.loading.contains(selected) || (selected == "library" && catalog.libraryLoading)) {
                    MobileLoading(text: L("Loading titles…"))
                } else if let error = selected == "library" ? catalog.libraryError : catalog.errors[selected] {
                    MobileError(message: error) { Task { await load(refresh: true) } }
                } else if items.isEmpty {
                    ContentUnavailableView(L("Nothing here yet"), systemImage: "film", description: Text(L("Try another category or refresh your server’s catalog.")))
                        .frame(maxWidth: .infinity)
                }
                MobileGrid(items: items)
            }.padding(.vertical, 8)
        }
        .refreshable { await load(refresh: true) }
        .task(id: selected) { await load(refresh: false) }
    }
    private func load(refresh: Bool) async {
        if selected == "library" { await catalog.loadLibrary(api: api) }
        else { await catalog.loadFeed(selected, api: api, config: config, refresh: refresh) }
    }
}

/// Медіатека: what is already on the server (one chip per type, newest
/// first) and Favorites (newest first) - as on Apple TV.
struct MobileLibrary: View {
    let api: TorrentTubeAPI
    @Environment(MobileContext.self) private var context
    @Environment(CatalogStore.self) private var catalog
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.mobileEdge) private var edge
    @State private var section = ""
    var body: some View {
        let active = section.isEmpty ? LibrarySections.defaultSection(catalog.library) : section
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MobileChips(options: LibrarySections.chips(catalog.library, favorites: favorites.entries(server: api.baseURL).count),
                            selected: Binding(get: { active }, set: { section = $0 }))
                if active == "favorites" {
                    let all = favorites.entries(server: api.baseURL)
                    if all.isEmpty {
                        ContentUnavailableView(L("No favorites yet"), systemImage: "heart", description: Text(L("Tap the heart on a title to save it here.")))
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }
                    // One grid, newest first - like the other chips and the web page.
                    MobileGrid(items: all.map(\.item))
                } else if active == "collections" {
                    let all = LibrarySections.collections(catalog.library)
                    if all.isEmpty {
                        ContentUnavailableView(L("No collections yet"), systemImage: "square.stack",
                                               description: Text(L("Films of one series, like Harry Potter, appear here once two of them are on the server.")))
                            .padding(.top, 40).frame(maxWidth: .infinity)
                    }
                    MobileCollectionGrid(collections: all)
                } else {
                    let items = catalog.library.filter { $0.kind == active }
                    if items.isEmpty && catalog.libraryLoading {
                        MobileLoading(text: L("Loading titles…"))
                    } else if let error = catalog.libraryError, items.isEmpty {
                        MobileError(message: error) { Task { await catalog.loadLibrary(api: api) } }
                    } else if items.isEmpty {
                        ContentUnavailableView(L("Nothing here yet"), systemImage: "externaldrive",
                                               description: Text(L("Titles you download to the server appear here.")))
                            .frame(maxWidth: .infinity)
                    }
                    MobileGrid(items: items.map(libraryItem))
                }
            }.padding(.vertical, 8)
        }
        .refreshable {
            async let hearts: Void = favorites.sync().value
            await catalog.loadLibrary(api: api)
            await hearts
        }
        .task {
            favorites.sync()
            await catalog.loadLibrary(api: api)
            // The server is still matching titles: show them as they come in.
            while catalog.libraryPending > 0 && !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                await catalog.loadLibrary(api: api)
            }
            await catalog.syncLibrary(api: api, config: context.config)  // saves only titles not saved yet
        }
    }
}

struct MobileSearch: View {
    /// On the Mac, Search is a page of the current tab (same window, the top
    /// row's Back); on iPhone and iPad it is its own full-screen stack.
    @ViewBuilder private func searchStack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        #if os(macOS)
        content()
        #else
        NavigationStack(path: $searchPath) { content() }
        #endif
    }
    @Environment(\.mobileEdge) private var edge
    @Environment(\.dismiss) private var dismiss
    let api: TorrentTubeAPI
    let config: ServerConfig
    /// The Mac's always-visible field in the top row: when given, this screen
    /// shows only the results and hides its own field and close button.
    var sharedQuery: Binding<String>? = nil
    @Environment(CatalogStore.self) private var catalog
    @State private var ownQuery = ""
    private var query: String {
        get { sharedQuery?.wrappedValue ?? ownQuery }
        nonmutating set { if let sharedQuery { sharedQuery.wrappedValue = newValue } else { ownQuery = newValue } }
    }
    @FocusState private var isFieldFocused: Bool
    @State private var items: [MediaItem] = []
    @State private var searched = ""
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    @State private var searchPath = NavigationPath()
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var results: LibrarySearchResults {
        LibrarySearchResults(query: term, library: catalog.library.map { catalog.resolved(libraryItem($0)) },
                             torrents: searched == term ? items.map { catalog.resolved($0) } : [])
    }
    private var noResults: Bool {
        term.count >= 2 && !loading && !catalog.libraryLoading && error == nil && catalog.libraryError == nil &&
        results.library.isEmpty && results.torrents.isEmpty && (!config.searchEnabled || searched == term)
    }
    var body: some View {
        searchStack {
            VStack(spacing: 0) {
                if sharedQuery == nil {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField(L("Search"), text: sharedQuery ?? $ownQuery)
                                .textFieldStyle(.plain)  // no extra macOS frame inside our own field
                                .focused($isFieldFocused)
                                .submitLabel(.search)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .accessibilityIdentifier("search-input")
                            if !query.isEmpty {
                                Button { query = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .hapticButtonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12), in: Capsule())

                        Button {
                            isFieldFocused = false
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.15), in: Circle())
                        }
                        .hapticButtonStyle(PlainButtonStyle())
                        .accessibilityIdentifier("close-search")
                    }
                    .padding(.horizontal, edge)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }

                GeometryReader { viewport in
                ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if term.count < 2 {
                    if let popular = catalog.rows["popular"], !popular.isEmpty {
                        Text(L("Popular now")).font(.title3.bold()).padding(.horizontal, edge)
                        MobileGrid(items: Array(popular.prefix(24)))
                    }
                } else {
                    if !results.library.isEmpty {
                        Label(L("In your library"), systemImage: "folder").font(.title3.bold()).padding(.horizontal, edge)
                        MobileGrid(items: results.library)
                    }
                    if let libraryError = catalog.libraryError {
                        MobileError(message: libraryError) { Task { await catalog.loadLibrary(api: api) } }
                    }
                    if config.searchEnabled {
                        #if os(macOS)
                        if !noResults { Label(L("Torrents"), systemImage: "network").font(.title3.bold()).padding(.horizontal, edge) }
                        #else
                        Label(L("Torrents"), systemImage: "network").font(.title3.bold()).padding(.horizontal, edge)
                        #endif
                        if let error {
                            MobileError(message: error) { retry += 1 }
                        } else if loading || searched != term {
                            MobileLoading(text: L("Searching…"))
                        } else if !results.torrents.isEmpty {
                            MobileGrid(items: results.torrents)
                        } else if !results.library.isEmpty {
                            Text(L("No additional torrent titles.")).foregroundStyle(.secondary).padding(.horizontal, edge)
                        }
                    }
                    if noResults {
                        ContentUnavailableView(L("No results for “%@”", term), systemImage: "magnifyingglass",
                                               description: Text(L("Check the spelling or try a new search.")))
                            #if os(macOS)
                            .frame(maxWidth: .infinity)
                            #endif
                    }
                    if !config.searchEnabled {
                        Text(L("Searching your library. Torrent search is disabled on this server."))
                            .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, edge)
                    }
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(macOS)
            .frame(minHeight: noResults ? max(0, viewport.size.height - 16) : 0)
            #endif
        }
        #if !os(macOS)
        .scrollDismissesKeyboard(.immediately)
        #endif
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppBackground())
        .hidesNavigationBar()
        .navigationDestination(for: MediaItem.self) { item in
            MobileTitle(item: item, api: api, config: config).sidesUnderInsets()
        }
        .navigationDestination(for: PersonRoute.self) { MobilePerson(route: $0, api: api) }
        .navigationDestination(for: LibraryCollection.self) { MobileCollection(collection: $0) }
    }
    .onAppear {
            UserDefaults.standard.removeObject(forKey: "recentSearches")
            if sharedQuery == nil { isFieldFocused = true }
        }
        .task {
            guard sharedQuery == nil else { return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            isFieldFocused = true
        }
        .task { await catalog.loadLibrary(api: api) }
        .task { await catalog.loadFeed("popular", api: api, config: config) }
        .task(id: "\(term)|\(retry)") {
            guard config.searchEnabled, term.count >= 2 else { items = []; error = nil; searched = ""; loading = false; return }
            loading = true; error = nil
            do {
                try await Task.sleep(for: .milliseconds(400))  // typing pause
                let result: CatalogResponse = try await api.request("api/search", query: [.init(name: "q", value: term)])
                try Task.checkCancellation()
                items = result.results; searched = term; loading = false
                await catalog.enrich(Array(items.prefix(24)), api: api, config: config)
            } catch is CancellationError {} catch {
                if !Task.isCancelled { self.error = error.localizedDescription; loading = false }
            }
        }
    }

}


/// A person's page: their photo and name, then every film and show they are in.
struct MobilePerson: View {
    @Environment(\.mobileEdge) private var edge
    @Environment(\.horizontalSizeClass) private var sizeClass
    let route: PersonRoute
    let api: TorrentTubeAPI
    @State private var credits: PersonCredits?
    @State private var error: String?
    @State private var retry = 0
    @State private var scrolled = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color(white: 0.14))
                        if let photo = credits?.photo ?? route.photo, let url = URL(string: photo) {
                            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                        } else {
                            Text(String(route.name.prefix(1))).font(.largeTitle.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                        }
                    }.frame(width: 96, height: 96).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.name).font(.title.bold())
                        if let credits, !credits.titles.isEmpty {
                            Text(L("%ld titles", credits.titles.count)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.horizontal, edge)
                if let credits {
                    if credits.titles.isEmpty {
                        ContentUnavailableView(L("Nothing here yet"), systemImage: "film")
                    } else {
                        MobileGrid(items: credits.items)
                    }
                } else if let error {
                    MobileError(message: error) { retry += 1 }
                } else {
                    MobileLoading(text: L("Loading titles…"))
                }
            }.padding(.vertical, 16)
        }
        .background(AppBackground())
        // No bar panel: the content blends into the bar as it scrolls, and the name shows in the bar once the big one is gone.
        .softTopEdge()
        #if !os(macOS)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        #endif
        #if os(macOS)
        .navigationTitle(scrolled ? route.name : "")
        #else
        .navigationTitle(sizeClass == .regular ? "" : (scrolled ? route.name : ""))
        .toolbar {
            if sizeClass == .regular, scrolled {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) { floatingName }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { floatingName }
                }
            }
        }
        #endif
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 70 } action: { _, new in scrolled = new }
        .task(id: retry) {
            error = nil
            do { credits = try await api.request("api/person", query: [.init(name: "id", value: String(route.id))]) }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private var floatingName: some View {
        Text(route.name)
            .font(.headline).lineLimit(1).minimumScaleFactor(0.65)
            .frame(width: 220, height: 44, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("person-floating-name")
    }
}

/// The Library's collections, as poster cards like the titles around them.
struct MobileCollectionGrid: View {
    @Environment(\.mobileEdge) private var edge
    let collections: [LibraryCollection]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        let minimum: CGFloat = typeSize.isAccessibilitySize ? 220 : (sizeClass == .regular ? 160 : 104)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: 240), spacing: 14)], alignment: .leading, spacing: 22) {
            ForEach(collections) { collection in
                NavigationLink(value: collection) {
                    VStack(alignment: .leading, spacing: 8) {
                        MobileArtwork(url: collection.poster, seed: collection.name)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)) }
                            .overlay(alignment: .topLeading) {
                                Label("\(collection.titles.count)", systemImage: "square.stack.fill").font(.caption.weight(.bold))
                                    .padding(.horizontal, 7).padding(.vertical, 4).background(.black.opacity(0.6), in: Capsule()).padding(6)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collection.name).font(MobileStyle.itemTitle(.subheadline.weight(.medium))).lineLimit(2, reservesSpace: true)
                                .foregroundStyle(.primary)
                            Text(collection.count).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.multilineTextAlignment(.leading)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(collection.name), \(collection.count)")
                .accessibilityIdentifier("collection-\(collection.id)")
            }
        }.padding(.horizontal, edge)
    }
}

/// A collection's page: its backdrop, poster, name and overview, then its
/// films in release order, each with its part and year.
struct MobileCollection: View {
    @Environment(\.mobileEdge) private var edge
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    let collection: LibraryCollection
    var body: some View {
        let minimum: CGFloat = typeSize.isAccessibilitySize ? 220 : (sizeClass == .regular ? 160 : 104)
        let poster: CGFloat = sizeClass == .regular ? 180 : 116
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom, spacing: 16) {
                    MobileArtwork(url: collection.poster, seed: collection.name).frame(width: poster)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1)) }
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(collection.name).font(sizeClass == .regular ? .largeTitle.bold() : .title2.bold()).lineLimit(3)
                        Text(collection.count).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }.padding(.bottom, 4)
                }
                .padding(.horizontal, edge)
                if let overview = collection.info.overview, !overview.isEmpty {
                    Text(overview).font(.callout).foregroundStyle(.white.opacity(0.8)).lineSpacing(3)
                        .frame(maxWidth: 760, alignment: .leading).padding(.horizontal, edge)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: 240), spacing: 14)], alignment: .leading, spacing: 22) {
                    ForEach(collection.titles) { title in
                        VStack(alignment: .leading, spacing: 2) {
                            MobileCard(item: libraryItem(title))
                            Text(LibraryCollection.line(title)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }.padding(.horizontal, edge)
            }
            .padding(.top, sizeClass == .regular ? 140 : 110).padding(.bottom, 24)
        }
        .background(alignment: .top) {
            // Edge to edge at a fixed height, cropped - sized by its own 16:9
            // shape it stopped short of the right edge on iPad.
            if let backdrop = collection.info.backdrop {
                Color.clear
                    .frame(maxWidth: .infinity).frame(height: sizeClass == .regular ? 620 : 340)
                    .overlay { PosterArtwork(url: URL(string: higherResolution(backdrop, backdrop: true)), fit: false, seed: collection.name) }
                    .clipped()
                    .mask(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea()
            }
        }
        .background(AppBackground())
        .navigationTitle(collection.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
