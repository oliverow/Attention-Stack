import AppKit
import SwiftUI

@main
struct AttentionStackApp: App {
    @StateObject private var store = ItemStore()
    @StateObject private var frontmost = FrontmostAppTracker()

    // Launching a rebuilt copy leaves the old one running, and two processes
    // writing items.json means the stale one's next save wipes whatever the
    // other added. Newest launch wins; this runs before the store loads.
    init() {
        let me = NSRunningApplication.current.processIdentifier
        for other in NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ) where other.processIdentifier != me {
            other.terminate()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store, frontmost: frontmost)
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
