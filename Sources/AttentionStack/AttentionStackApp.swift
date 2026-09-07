import SwiftUI

@main
struct AttentionStackApp: App {
    @StateObject private var store = ItemStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            // MenuBarExtra drops the text when its label has an image,
            // so render icon + count into one template image.
            Image(nsImage: menuBarImage(count: store.items.count))
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private func menuBarImage(count: Int) -> NSImage {
    let content = HStack(spacing: 3) {
        Image(systemName: "tray.full")
            .font(.system(size: 14, weight: .regular))
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 13, weight: .medium))
        }
    }
    .foregroundStyle(.black)
    .padding(.horizontal, 1)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    let image = renderer.nsImage!
    image.isTemplate = true
    return image
}
