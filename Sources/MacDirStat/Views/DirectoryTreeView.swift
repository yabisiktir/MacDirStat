import SwiftUI

struct DirectoryTreeView: View {
    let root: FileNode
    @Binding var selectedNode: FileNode?
    let sizeMetric: SizeMetric

    var body: some View {
        List(selection: Binding(
            get: { selectedNode?.id },
            set: { id in
                if let id {
                    selectedNode = findNode(id: id, in: root)
                }
            }
        )) {
            OutlineGroup(root.directoryChildren, id: \.id, children: \.optionalDirectoryChildren) { node in
                DirectoryRow(node: node, sizeMetric: sizeMetric)
                    .contextMenu {
                        Button {
                            NodeActions.revealInFinder(node)
                        } label: {
                            Label("Reveal in Finder", systemImage: "arrow.right.circle")
                        }
                        Button {
                            NodeActions.copyPath(node)
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
    }

    // The sidebar only ever shows and selects directories, so restrict the
    // lookup to the directory subtree. Walking `children` here would traverse
    // every file on the volume on each click; `directoryChildren` skips them.
    private func findNode(id: UInt64, in node: FileNode) -> FileNode? {
        if node.id == id { return node }
        for child in node.directoryChildren {
            if let found = findNode(id: id, in: child) {
                return found
            }
        }
        return nil
    }
}

struct DirectoryRow: View {
    let node: FileNode
    let sizeMetric: SizeMetric

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(ByteFormatter.string(from: node.size(for: sizeMetric)))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private extension FileNode {
    var optionalDirectoryChildren: [FileNode]? {
        let dirs = directoryChildren
        return dirs.isEmpty ? nil : dirs
    }
}
