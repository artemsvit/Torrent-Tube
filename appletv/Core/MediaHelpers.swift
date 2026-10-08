import Foundation

func libraryItem(_ title: LibraryTitle) -> MediaItem {
    // Several copies on the server: "Choose version" lists them (folder, files, size).
    let versions: [Release]? = title.versions.count > 1 ? title.versions.map { version in
        let size = ByteCountFormatter.string(fromByteCount: version.size, countStyle: .file)
        let detail = version.files > 1 ? L("%ld files", version.files) + " · " + size : size
        return Release(title: "\(version.category) / \(version.name)", magnet: nil, downloadLink: nil,
                       sizeLabel: detail, seeders: nil, path: version.id)
    } : nil
    var item = MediaItem(title: title.name, magnet: nil, downloadLink: nil, sizeLabel: nil, seeders: nil, releases: versions)
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
