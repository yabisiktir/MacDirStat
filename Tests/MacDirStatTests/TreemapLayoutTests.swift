import XCTest
@testable import MacDirStat

final class TreemapLayoutTests: XCTestCase {
    private let bounds = TreemapRect(x: 0, y: 0, width: 1000, height: 700)

    /// A directory with `count` equally sized file children.
    private func flatTree(count: Int, each size: Int64 = 1_000_000) -> FileNode {
        let root = FileNode(inode: 1, name: "root", isDirectory: true)
        for i in 0..<count {
            root.addChild(FileNode(inode: UInt64(i + 2), name: "f\(i)", isDirectory: false,
                                   ownSize: size, allocatedSize: size, category: .images))
        }
        root.computeAggregates()
        root.sortChildrenBySize()
        return root
    }

    private func assertWithinBounds(_ items: [TreemapItem], file: StaticString = #filePath, line: UInt = #line) {
        let eps = 0.001
        for item in items {
            XCTAssertGreaterThanOrEqual(item.rect.x, bounds.x - eps, file: file, line: line)
            XCTAssertGreaterThanOrEqual(item.rect.y, bounds.y - eps, file: file, line: line)
            XCTAssertLessThanOrEqual(item.rect.x + item.rect.width, bounds.x + bounds.width + eps, file: file, line: line)
            XCTAssertLessThanOrEqual(item.rect.y + item.rect.height, bounds.y + bounds.height + eps, file: file, line: line)
            XCTAssertGreaterThan(item.rect.width, 0, file: file, line: line)
            XCTAssertGreaterThan(item.rect.height, 0, file: file, line: line)
        }
    }

    func testLayoutEmitsRootPlusRenderableChildren() {
        let engine = TreemapLayoutEngine()
        let items = engine.layout(root: flatTree(count: 8), in: bounds)
        // 1 directory background tile + 8 file tiles.
        XCTAssertEqual(items.count, 9)
        assertWithinBounds(items)
    }

    func testChildTilesDoNotOverlap() {
        let engine = TreemapLayoutEngine()
        let items = engine.layout(root: flatTree(count: 8), in: bounds)
        let childRects = items.filter { $0.depth == 1 }.map(\.rect)
        XCTAssertEqual(childRects.count, 8)
        for i in 0..<childRects.count {
            for j in (i + 1)..<childRects.count {
                XCTAssertFalse(rectsOverlap(childRects[i], childRects[j]),
                               "tiles \(i) and \(j) overlap")
            }
        }
    }

    func testLayoutIsDeterministic() {
        let engine = TreemapLayoutEngine()
        let tree = flatTree(count: 32)
        let a = engine.layout(root: tree, in: bounds).map(\.node.id)
        let b = engine.layout(root: tree, in: bounds).map(\.node.id)
        XCTAssertEqual(a, b)
    }

    func testCancellableMatchesNonCancellableWhenNotCancelled() {
        let engine = TreemapLayoutEngine()
        let tree = flatTree(count: 50)
        let plain = engine.layout(root: tree, in: bounds).map(\.node.id)
        let cancellable = engine.layout(root: tree, in: bounds, sizeMetric: .fileSize,
                                        isCancelled: { false })?.map(\.node.id)
        XCTAssertEqual(cancellable, plain)
    }

    func testCancelledLayoutReturnsNil() {
        let engine = TreemapLayoutEngine()
        let result = engine.layout(root: flatTree(count: 50), in: bounds,
                                   sizeMetric: .fileSize, isCancelled: { true })
        XCTAssertNil(result)
    }

    func testSubPixelChildrenArePruned() {
        // One huge file plus many tiny ones. The tiny files are sub-pixel and
        // must not appear as their own tiles (they are pruned, not rendered).
        let root = FileNode(inode: 1, name: "root", isDirectory: true)
        root.addChild(FileNode(inode: 2, name: "big", isDirectory: false,
                               ownSize: 1_000_000_000, allocatedSize: 1_000_000_000, category: .video))
        for i in 0..<500 {
            root.addChild(FileNode(inode: UInt64(i + 3), name: "tiny\(i)", isDirectory: false,
                                   ownSize: 10, allocatedSize: 10, category: .other))
        }
        root.computeAggregates()
        root.sortChildrenBySize()

        let items = TreemapLayoutEngine().layout(root: root, in: bounds)
        let renderedFileNames = Set(items.filter { $0.depth == 1 }.map(\.node.name))
        XCTAssertTrue(renderedFileNames.contains("big"))
        XCTAssertLessThan(renderedFileNames.count, 50, "sub-pixel tail should be pruned")
        assertWithinBounds(items)
    }

    func testDepthIsCappedByMaxDepth() {
        // A deep chain of nested directories; maxDepth limits recursion.
        var root = FileNode(inode: 1, name: "d0", isDirectory: true)
        let top = root
        for depth in 1...20 {
            let child = FileNode(inode: UInt64(depth + 1), name: "d\(depth)", isDirectory: true)
            let file = FileNode(inode: UInt64(1000 + depth), name: "f\(depth)", isDirectory: false,
                                ownSize: 1_000_000, allocatedSize: 1_000_000, category: .code)
            child.addChild(file)
            root.addChild(child)
            root = child
        }
        top.computeAggregates()
        top.sortChildrenBySize()

        let engine = TreemapLayoutEngine(maxDepth: 5)
        let items = engine.layout(root: top, in: bounds)
        XCTAssertLessThanOrEqual(items.map(\.depth).max() ?? 0, 5)
    }

    private func rectsOverlap(_ a: TreemapRect, _ b: TreemapRect) -> Bool {
        let eps = 0.001
        return a.x < b.x + b.width - eps && b.x < a.x + a.width - eps &&
               a.y < b.y + b.height - eps && b.y < a.y + a.height - eps
    }
}
