import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard TopShelfStore.defaults.bool(forKey: "showNewInTopShelf"),
              let snapshot = TopShelfStore.snapshot, snapshot.server == TopShelfStore.defaults.string(forKey: "activeServer"), !snapshot.titles.isEmpty else {
            completionHandler(nil)
            return
        }
        let items = snapshot.titles.compactMap { title -> TVTopShelfSectionedItem? in
            guard let image = URL(string: title.poster), ["https", "http"].contains(image.scheme) else { return nil }
            let item = TVTopShelfSectionedItem(identifier: title.id)
            item.title = title.title
            item.imageShape = .poster
            item.setImageURL(image, for: .screenScale1x)
            item.setImageURL(image, for: .screenScale2x)
            item.displayAction = TVTopShelfAction(url: title.url)
            return item
        }
        guard !items.isEmpty else { completionHandler(nil); return }
        let section = TVTopShelfItemCollection(items: items)
        section.title = L("New to explore")
        completionHandler(TVTopShelfSectionedContent(sections: [section]))
    }
}
