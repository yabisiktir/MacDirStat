import XCTest
@testable import MacDirStat

final class FileNodeTests: XCTestCase {
    /// root/
    ///   a.txt        (100)
    ///   sub/
    ///     b.jpg      (200, allocated 256)
    ///     c.mp4      (300, allocated 512)
    private func makeTree() -> FileNode {
        let root = FileNode(inode: 1, name: "root", isDirectory: true)
        let a = FileNode(inode: 2, name: "a.txt", isDirectory: false, ownSize: 100, allocatedSize: 128, category: .documents)
        let sub = FileNode(inode: 3, name: "sub", isDirectory: true)
        let b = FileNode(inode: 4, name: "b.jpg", isDirectory: false, ownSize: 200, allocatedSize: 256, category: .images)
        let c = FileNode(inode: 5, name: "c.mp4", isDirectory: false, ownSize: 300, allocatedSize: 512, category: .video)
        sub.addChild(b); sub.addChild(c)
        root.addChild(a); root.addChild(sub)
        root.computeAggregates()
        return root
    }

    func testAggregatesRollUp() {
        let root = makeTree()
        XCTAssertEqual(root.totalSize, 600)                 // 100 + 200 + 300
        XCTAssertEqual(root.totalAllocatedSize, 128 + 256 + 512)
        XCTAssertEqual(root.fileCount, 3)
        XCTAssertEqual(root.directoryCount, 2)              // root + sub
    }

    func testSizeMetricSelectsField() {
        let root = makeTree()
        XCTAssertEqual(root.size(for: .fileSize), root.totalSize)
        XCTAssertEqual(root.size(for: .allocatedSize), root.totalAllocatedSize)
    }

    func testSortChildrenBySizeDescending() {
        let root = makeTree()
        root.sortChildrenBySize()
        // sub (500) should come before a.txt (100)
        XCTAssertEqual(root.children.map(\.name), ["sub", "a.txt"])
        let sub = root.children[0]
        XCTAssertEqual(sub.children.map(\.name), ["c.mp4", "b.jpg"]) // 300 before 200
    }

    func testDirectoryChildrenFiltersAndCaches() {
        let root = makeTree()
        XCTAssertEqual(root.directoryChildren.map(\.name), ["sub"])
        // Cached instance is returned on repeat access.
        XCTAssertTrue(root.directoryChildren[0] === root.directoryChildren[0])
    }

    func testPathReflectsHierarchy() {
        let root = makeTree()
        let sub = root.directoryChildren[0]
        XCTAssertEqual(sub.path, "root/sub")
        XCTAssertEqual(sub.children.first(where: { $0.name == "b.jpg" })?.path, "root/sub/b.jpg")
    }

    func testVolumeRootPathHasNoDoubleSlash() {
        // Scanning a whole volume gives the root the name "/".
        let root = FileNode(inode: 1, name: "/", isDirectory: true)
        let users = FileNode(inode: 2, name: "Users", isDirectory: true)
        let file = FileNode(inode: 3, name: "readme.txt", isDirectory: false, ownSize: 1)
        users.addChild(file)
        root.addChild(users)
        XCTAssertEqual(root.path, "/")
        XCTAssertEqual(users.path, "/Users")
        XCTAssertEqual(file.path, "/Users/readme.txt")
    }

    func testCategoryBreakdownSumsPerCategory() {
        let root = makeTree()
        let breakdown = Dictionary(uniqueKeysWithValues:
            root.categoryBreakdown().map { ($0.category, $0.size) })
        XCTAssertEqual(breakdown[.documents], 100)
        XCTAssertEqual(breakdown[.images], 200)
        XCTAssertEqual(breakdown[.video], 300)
    }
}
