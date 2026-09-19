import SwiftUI

struct TreemapRect: Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var area: Double { width * height }
    var minSide: Double { min(width, height) }

    func contains(point: CGPoint) -> Bool {
        point.x >= x && point.x <= x + width &&
        point.y >= y && point.y <= y + height
    }
}

struct TreemapItem: Identifiable, Sendable {
    let id: Int
    let node: FileNode
    let rect: TreemapRect
    let depth: Int
    let color: CGColor
}

struct TreemapLayoutEngine: Sendable {
    let maxDepth: Int
    let minPixelArea: Double

    init(maxDepth: Int = 12, minPixelArea: Double = 4) {
        self.maxDepth = maxDepth
        self.minPixelArea = minPixelArea
    }

    func layout(root: FileNode, in bounds: TreemapRect, sizeMetric: SizeMetric = .fileSize) -> [TreemapItem] {
        var items: [TreemapItem] = []
        items.reserveCapacity(8192)
        var nextID = 0
        layoutNode(root, in: bounds, depth: 0, sizeMetric: sizeMetric, items: &items, nextID: &nextID)
        return items
    }

    /// Layout that bails out early when the enclosing `Task` is cancelled.
    /// Callers run this off the main actor and supersede it on every resize /
    /// drill-down, so without this a stale layout keeps burning a core to
    /// completion. Returns `nil` when cancelled mid-flight.
    func layout(root: FileNode, in bounds: TreemapRect, sizeMetric: SizeMetric,
                isCancelled: () -> Bool) -> [TreemapItem]? {
        var items: [TreemapItem] = []
        items.reserveCapacity(8192)
        var nextID = 0
        layoutNode(root, in: bounds, depth: 0, sizeMetric: sizeMetric,
                   items: &items, nextID: &nextID, isCancelled: isCancelled)
        return isCancelled() ? nil : items
    }

    private func colorForNode(_ node: FileNode, depth: Int) -> CGColor {
        let darkenFactor = max(0.5, 1.0 - Double(depth) * 0.08)
        let baseColor = node.category.color.resolve(in: .init())
        return CGColor(
            red: Double(baseColor.red) * darkenFactor,
            green: Double(baseColor.green) * darkenFactor,
            blue: Double(baseColor.blue) * darkenFactor,
            alpha: 1.0
        )
    }

    private func layoutNode(
        _ node: FileNode,
        in bounds: TreemapRect,
        depth: Int,
        sizeMetric: SizeMetric,
        items: inout [TreemapItem],
        nextID: inout Int,
        isCancelled: () -> Bool = { false }
    ) {
        guard bounds.area >= minPixelArea else { return }

        func emit() {
            let itemID = nextID; nextID += 1
            items.append(TreemapItem(
                id: itemID,
                node: node,
                rect: bounds,
                depth: depth,
                color: colorForNode(node, depth: depth)
            ))
        }

        // Leaf node (file or empty/childless directory)
        if !node.isDirectory || node.children.isEmpty || depth >= maxDepth {
            emit()
            return
        }

        // Filter children with positive size
        let children = node.children.filter { $0.size(for: sizeMetric) > 0 }
        guard !children.isEmpty else { emit(); return }

        // Render directory as background so gaps show its color, not black
        emit()

        let totalSize = Double(children.reduce(0) { $0 + $1.size(for: sizeMetric) })
        guard totalSize > 0 else { return }

        // Children are sorted largest-first. A child's rect area is
        // size/total * bounds.area, so once a child falls below minPixelArea
        // every child after it does too — and none of them (or their subtrees)
        // can render. Stop at that cutoff instead of squarifying and recursing
        // into a long tail of sub-pixel nodes that only get culled anyway.
        // This is visually identical to laying them all out and culling.
        let areaScale = bounds.area / totalSize
        var renderCount = 0
        for child in children {
            if Double(child.size(for: sizeMetric)) * areaScale >= minPixelArea {
                renderCount += 1
            } else {
                break
            }
        }
        guard renderCount > 0 else { return }

        // Bail out of a superseded layout before doing the expensive subtree.
        if isCancelled() { return }

        let visible = children.prefix(renderCount)
        let sizes = visible.map { Double($0.size(for: sizeMetric)) * areaScale }
        let rects = squarify(sizes: sizes, in: bounds)

        for (i, child) in visible.enumerated() where i < rects.count {
            layoutNode(child, in: rects[i], depth: depth + 1, sizeMetric: sizeMetric,
                       items: &items, nextID: &nextID, isCancelled: isCancelled)
        }
    }

    private func squarify(sizes: [Double], in bounds: TreemapRect) -> [TreemapRect] {
        guard !sizes.isEmpty else { return [] }

        var rects = [TreemapRect](repeating: TreemapRect(x: 0, y: 0, width: 0, height: 0), count: sizes.count)
        var remaining = bounds
        var index = 0

        while index < sizes.count {
            let shortSide = remaining.minSide

            // Grow the row as long as squaring improves. `sizes` is sorted
            // descending, so the row's largest element is `sizes[index]` and
            // its smallest is the one most recently added — the worst aspect
            // ratio needs only (sum, max, min), computed in O(1) per step
            // instead of rescanning and re-allocating the whole row.
            let rowMax = sizes[index]
            var rowSum = sizes[index]
            var rowMin = sizes[index]
            var bestWorst = worstAspectRatio(sum: rowSum, max: rowMax, min: rowMin, shortSide: shortSide)

            var next = index + 1
            while next < sizes.count {
                let candidate = sizes[next]
                let newSum = rowSum + candidate
                let newMin = Swift.min(rowMin, candidate)
                let newWorst = worstAspectRatio(sum: newSum, max: rowMax, min: newMin, shortSide: shortSide)
                if newWorst > bestWorst { break }
                bestWorst = newWorst
                rowSum = newSum
                rowMin = newMin
                next += 1
            }

            // Lay out the row [index, next)
            let rowFraction = rowSum / (remaining.width * remaining.height)
            let isHorizontal = remaining.width >= remaining.height

            if isHorizontal {
                let rowWidth = remaining.width * rowFraction
                var yOffset = remaining.y
                for idx in index..<next {
                    let itemHeight = (sizes[idx] / rowSum) * remaining.height
                    rects[idx] = TreemapRect(x: remaining.x, y: yOffset, width: rowWidth, height: itemHeight)
                    yOffset += itemHeight
                }
                remaining = TreemapRect(
                    x: remaining.x + rowWidth,
                    y: remaining.y,
                    width: remaining.width - rowWidth,
                    height: remaining.height
                )
            } else {
                let rowHeight = remaining.height * rowFraction
                var xOffset = remaining.x
                for idx in index..<next {
                    let itemWidth = (sizes[idx] / rowSum) * remaining.width
                    rects[idx] = TreemapRect(x: xOffset, y: remaining.y, width: itemWidth, height: rowHeight)
                    xOffset += itemWidth
                }
                remaining = TreemapRect(
                    x: remaining.x,
                    y: remaining.y + rowHeight,
                    width: remaining.width,
                    height: remaining.height - rowHeight
                )
            }

            index = next
        }

        return rects
    }

    private func worstAspectRatio(sum: Double, max: Double, min: Double, shortSide: Double) -> Double {
        guard shortSide > 0, sum > 0, min > 0 else { return Double.infinity }
        let s2 = shortSide * shortSide
        let sum2 = sum * sum
        return Swift.max((s2 * max) / sum2, sum2 / (s2 * min))
    }
}

struct TreemapHitTester: Sendable {
    let items: [TreemapItem]

    func itemAt(point: CGPoint) -> TreemapItem? {
        // Reverse iterate to find deepest (topmost rendered) item
        for item in items.reversed() {
            if item.rect.contains(point: point) {
                return item
            }
        }
        return nil
    }
}
