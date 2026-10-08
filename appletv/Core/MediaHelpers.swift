import Foundation

func libraryItem(_ title: LibraryTitle) -> MediaItem {
    var item = MediaItem(title: title.name, magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: nil)
    item.sourceOverride = title.source
    if !title.isTorrent {
        item.mediaType = title.kind == "tv" ? "tv" : "movie"
        item.cleanTitle = title.title
        // The server's match - used unless "Posters and details" is off.
        if CatalogStore.libraryMetadataEnabled, title.tmdbId != nil {
            item.cleanTitle = title.displayTitle ?? title.title
            item.poster = title.poster; item.rating = title.rating; item.overview = title.overview
            item.tmdbId = title.tmdbId; item.mediaType = title.mediaType ?? item.mediaType
        }
    }
    return item
}

func higherResolution(_ url: String, backdrop: Bool) -> String {
    guard url.hasPrefix("https://image.tmdb.org/t/p/") else { return url }
    return url.replacingOccurrences(of: "/w200/", with: backdrop ? "/w1280/" : "/w500/")
        .replacingOccurrences(of: "/w342/", with: backdrop ? "/w1280/" : "/w500/")
}
