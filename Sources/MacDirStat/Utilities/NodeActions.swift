import AppKit

/// Shared Finder/clipboard actions used by the treemap, the sidebar tree, and
/// the inspector so all three context menus behave identically.
enum NodeActions {
    static func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
    }

    static func copyPath(_ node: FileNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
    }
}
