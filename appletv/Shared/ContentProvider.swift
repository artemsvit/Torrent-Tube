import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard TopShelfStore.defaults.bool(forKey: "showNewInTopShelf"),
              let snapshot = TopShelfStore.snapshot, snapshot.server == TopShelfStore.defaults.string(forKey: "activeServer"), !snapshot.titles.isEmpty else {
            completionHandler(nil)
            return
        }
        let items = snapshot.titles.prefix(10).compactMap { title -> TVTopShelfCarouselItem? in
            guard let image = TopShelfStore.artworkURL(for: title) else { return nil }
            let item = TVTopShelfCarouselItem(identifier: title.id)
            item.setImageURL(image, for: .screenScale1x)
            item.setImageURL(image, for: .screenScale2x)
            // Top left: the kind ("Фільм", "Серіал"), then the name and the facts.
            item.contextTitle = title.kind
            item.title = title.title
            item.summary = title.overview
            item.genre = title.genres?.prefix(2).joined(separator: ", ")
            if let year = title.year.flatMap(Int.init) {
                item.creationDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 1, day: 1))
            }
            if let rating = title.rating, rating > 0 {
                item.namedAttributes = [TVTopShelfNamedAttribute(name: "TMDB", values: [String(format: "★ %.1f", rating)])]
            }
            if let preview = title.previewURL, let url = URL(string: preview), ["https", "http"].contains(url.scheme) {
                item.previewVideoURL = url
            }
            // One button: it opens the title page. No "More Info" button.
            item.playAction = TVTopShelfAction(url: title.url)
            return item
        }
        guard !items.isEmpty else { completionHandler(nil); return }
        completionHandler(TVTopShelfCarouselContent(style: .details, items: items))
    }
}
