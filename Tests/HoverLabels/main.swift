import AppKit

// FolderView only needs this drawing constant from the app icon renderer.
enum TileRenderer { static let iconCornerRatio: CGFloat = 0.26 }

for pageSize in [3, 6, 9, 16] {
    for showsNames in [false, true] {
        let metrics = FolderMetrics(iconSize: 64, dockPitch: 70, appCount: pageSize,
                                    minBodyWidth: 0, magnification: 1.5,
                                    showsNames: showsNames, pageSize: pageSize)
        for index in 0..<pageSize {
            let point = metrics.iconCenter(index)
            let rest = metrics.hoveredIcon(count: pageSize, point: point, pointer: nil, amount: 0)
            precondition(rest?.index == index, "Resting hit test failed for \(pageSize) apps, index \(index)")
            let layout = metrics.magnifiedLayout(count: pageSize, pointer: point, amount: 1)
            // Cell centres differ from icon centres when permanent names are shown.
            let center = CGPoint(x: layout[index].center.x,
                                 y: layout[index].center.y - metrics.cellHeight * layout[index].scale / 2
                                    + metrics.iconSize * layout[index].scale / 2)
            let hit = metrics.hoveredIcon(count: pageSize, point: center, pointer: point, amount: 1)
            precondition(hit?.index == index, "Magnified hit test failed")
            precondition(abs(hit!.frame.width - metrics.iconSize * layout[index].scale) < 0.001)
        }
        precondition(metrics.hoveredIcon(count: pageSize, point: .zero, pointer: nil, amount: 0) == nil)
        precondition(metrics.hoveredIcon(count: 0, point: metrics.iconCenter(0), pointer: nil, amount: 0) == nil)
    }
}
print("PASS: hover labels hit actual icon frames across grid sizes, name modes and magnification; no labels outside icons")
