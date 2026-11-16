import AppKit
import SwiftUI

// MARK: - Model

struct FolderApp: Identifiable, Equatable {
    let url: URL
    let name: String
    let icon: NSImage
    var isRunning: Bool
    /// A preview of where an app being dragged from the Dock will land (drawn faintly).
    var isPreview = false
    var id: String { url.path }

    static func == (a: FolderApp, b: FolderApp) -> Bool {
        a.url == b.url && a.isRunning == b.isRunning && a.name == b.name && a.isPreview == b.isPreview
    }
}

final class FolderPanelModel: ObservableObject {
    @Published var apps: [FolderApp] = []
    @Published var metrics = FolderMetrics(iconSize: 52, dockPitch: 56, appCount: 0, minBodyWidth: 0, magnification: 1)
    @Published var page = 0
    /// Horizontal position of the page strip; -page × width at rest, follows your fingers while swiping.
    @Published var stripOffset: CGFloat = 0
    @Published var isPresented = false
    @Published var arrowEdge: Edge = .bottom
    /// Arrow tip position along its edge, measured from the body's leading (or top) side.
    @Published var arrowPosition: CGFloat = 0
    /// The (smoothed) pointer in body coordinates (top-left origin); kept while magnification eases out.
    @Published var pointer: CGPoint?
    /// 0…1: how far magnification has eased in (it eases in and out like the Dock's).
    @Published var magnificationAmount: CGFloat = 0
    /// Whether the pointer is actually over the popup (names show only then).
    @Published var hovering = false
    /// Actual pointer for icon hit testing; magnification's pointer is deliberately smoothed.
    @Published var hoverPoint: CGPoint?
    /// Visible part of the window in top-left content coordinates, excluding screen edges.
    @Published var visibleContentBounds: CGRect?
    /// The Dock's name label for this folder is showing under the popup's edge (while the pointer
    /// is on the folder's tile, or while an auto-hiding Dock is held up), and how wide it is.
    @Published var labelUnderneath = false
    var labelWidth: CGFloat = 0

    var onOpen: (FolderApp) -> Void = { _ in }
    /// Right-click on an app; the point is in screen coordinates.
    var onMenu: (FolderApp, CGPoint) -> Void = { _, _ in }
    var onSelectPage: (Int) -> Void = { _ in }
    /// Dragging an app to rearrange it; points are in screen coordinates.
    var onDragBegin: (FolderApp, CGPoint) -> Void = { _, _ in }
    var onDragEnd: () -> Void = {}

    /// The app being dragged and where it is (body coordinates), while rearranging.
    @Published var dragging: (id: String, location: CGPoint)?
    /// Lifted (slightly larger, with a shadow) while held; settles back as it lands.
    @Published var dragLifted = false
    /// The dragged app has been carried out of the folder (as a real drag the Dock can take);
    /// its spot stays empty until it comes back or goes into the Dock.
    @Published var dragOutside = false
    /// An app dragged from the Dock is over this folder: letting go adds it.
    @Published var dropTargeted = false

    var isSettled: Bool { abs(stripOffset + CGFloat(page) * metrics.bodyWidth) < 0.5 }
}

// MARK: - The Dock's name label, measured from macOS 26

enum DockLabel {
    static let height: CGFloat = 25
    static let pointerWidth: CGFloat = 17
    static let pointerHeight: CGFloat = 5
    static let horizontalPadding: CGFloat = 14
    static let font = NSFont.systemFont(ofSize: 13)
    /// The Dock puts the label's tip this far inside the top of a tile's (possibly magnified) frame.
    static let tipInset: CGFloat = 7.5

    static func width(for text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width) + horizontalPadding * 2
    }
}

// MARK: - Layout (taken from the Dock itself)

/// Sizes the popup like a little square of Dock: icons at the Dock's icon size, and the same
/// visible spacing between icons, and between icons and the glass edge, as the Dock uses.
struct FolderMetrics: Equatable {
    /// Icon image size (the Dock's tile size). App icons carry a transparent margin inside it.
    let iconSize: CGFloat
    /// Space between icon images (Dock tile pitch − icon size).
    let gap: CGFloat
    let columns: Int
    let rows: Int
    let pages: Int
    /// Wide enough to hide the Dock's name label for this folder behind the popup.
    let minBodyWidth: CGFloat
    /// Largest icon scale under the pointer (from Settings), 1 when magnification is off.
    let magnification: CGFloat
    /// Names under the icons (Launchpad style) instead of running indicators.
    let showsNames: Bool
    /// Space between columns: the Dock's gap, or wider so names fit when they're shown.
    let columnGap: CGFloat

    /// Apps per page → grid: 3 is one row of three, 6 two rows, 9 three, 16 four rows of four.
    static func grid(forPageSize size: Int) -> (columns: Int, rows: Int) {
        switch size {
        case ...3: return (3, 1)
        case 4...6: return (3, 2)
        case 7...9: return (3, 3)
        default: return (4, 4)
        }
    }

    var perPage: Int { columns * rows }
    /// Same pointer as the Dock's name label, so the popup sits exactly where that label would.
    static let arrowWidth: CGFloat = 20
    static let arrowHeight: CGFloat = DockLabel.pointerHeight
    /// Transparent room around the glass for its shadow and for app-name labels.
    static let marginH: CGFloat = 90
    static let marginTop: CGFloat = 50
    static let marginBottom: CGFloat = 14

    init(iconSize: CGFloat, dockPitch: CGFloat, appCount: Int, minBodyWidth: CGFloat, magnification: CGFloat,
         showsNames: Bool = false, pageSize: Int = 9) {
        self.iconSize = iconSize
        self.gap = max(2, dockPitch - iconSize)
        self.minBodyWidth = minBodyWidth
        self.magnification = magnification
        self.showsNames = showsNames
        let labelWidth = ceil(max(iconSize * 1.3, iconSize + 18))
        columnGap = showsNames ? max(gap, labelWidth + 4 - iconSize) : gap
        // Always room for a full page, however many apps the folder has (they fill from the top
        // left, like an iPhone folder).
        let grid = Self.grid(forPageSize: pageSize)
        columns = grid.columns
        rows = grid.rows
        pages = max(1, Int(ceil(Double(appCount) / Double(grid.columns * grid.rows))))
    }

    /// The icon artwork sits on an 824/1024 grid inside the image.
    var artworkInset: CGFloat { iconSize * 100 / 1024 }
    /// Visible space between two icons' artwork, which the Dock also uses as its padding.
    var visibleGap: CGFloat { gap + artworkInset * 2 }
    /// Extra room so magnified icons, as they spread apart, stay clear of the glass edge.
    var magnificationRoom: CGFloat { magnification > 1 ? ceil((magnification - 1) * iconSize * 0.5) + 2 : 0 }
    /// Glass edge → icon image edge: the Dock's visible spacing, plus room to magnify.
    var padding: CGFloat { visibleGap - artworkInset + magnificationRoom }
    var pitch: CGFloat { iconSize + gap }
    var dotsHeight: CGFloat { pages > 1 ? 16 : 0 }

    // App names (when shown) sit just under the icon artwork.
    var labelFontSize: CGFloat { min(max((iconSize * 0.2).rounded(), 10), 13) }
    var labelHeight: CGFloat { showsNames ? ceil(labelFontSize * 1.3) : 0 }
    var labelWidth: CGFloat { iconSize + columnGap - 4 }
    /// Icon image bottom → label top (the label tucks into the icon's transparent margin).
    var labelSpacing: CGFloat { 2 - artworkInset }
    /// An app's icon plus its name.
    var cellHeight: CGFloat { showsNames ? iconSize + labelSpacing + labelHeight : iconSize }
    var columnPitch: CGFloat { iconSize + columnGap }
    var rowPitch: CGFloat { cellHeight + gap }
    /// Side padding, with room for the outer columns' names.
    var paddingX: CGFloat { padding + (columnGap - gap) / 2 }

    var gridWidth: CGFloat { CGFloat(columns) * iconSize + CGFloat(columns - 1) * columnGap }
    var gridHeight: CGFloat { CGFloat(rows) * cellHeight + CGFloat(rows - 1) * gap }
    var naturalWidth: CGFloat { paddingX * 2 + gridWidth }
    var bodyWidth: CGFloat { ceil(max(naturalWidth, minBodyWidth)) }
    /// Centres the grid when the body had to be widened.
    var gridInsetX: CGFloat { paddingX + (bodyWidth - naturalWidth) / 2 }
    var stripHeight: CGFloat { padding + gridHeight + (pages > 1 ? 0 : padding) }
    var bodyHeight: CGFloat { ceil(stripHeight + (pages > 1 ? dotsHeight + padding * 0.5 : 0)) }
    /// Concentric with the icons' own corners, like the Dock.
    var cornerRadius: CGFloat { (iconSize - artworkInset * 2) * TileRenderer.iconCornerRatio + visibleGap + magnificationRoom }

    /// The popup's whole window content: glass, pointer and the transparent margins.
    func contentSize(arrowOnSide: Bool) -> CGSize {
        CGSize(width: bodyWidth + (arrowOnSide ? FolderMetrics.arrowHeight : 0) + FolderMetrics.marginH * 2,
               height: bodyHeight + (arrowOnSide ? 0 : FolderMetrics.arrowHeight) + FolderMetrics.marginTop + FolderMetrics.marginBottom)
    }

    /// Centre of the icon at `index` on its page, in body coordinates.
    func iconCenter(_ index: Int) -> CGPoint {
        let column = index % columns, row = index / columns
        return CGPoint(x: gridInsetX + CGFloat(column) * columnPitch + iconSize / 2,
                       y: padding + CGFloat(row) * rowPitch + iconSize / 2)
    }

    /// Centre of the whole cell (icon and name) at `index`.
    func cellCenter(_ index: Int) -> CGPoint {
        let icon = iconCenter(index)
        return CGPoint(x: icon.x, y: icon.y - iconSize / 2 + cellHeight / 2)
    }

    /// Hit-test the same scaled icon frames that PageGrid draws, not their unmagnified slots.
    func hoveredIcon(count: Int, point: CGPoint, pointer: CGPoint?, amount: CGFloat) -> (index: Int, frame: CGRect)? {
        let layout = magnifiedLayout(count: count, pointer: pointer, amount: amount)
        return layout.enumerated().compactMap { index, item -> (index: Int, frame: CGRect)? in
            let frame = CGRect(x: item.center.x - iconSize * item.scale / 2,
                               y: item.center.y - cellHeight * item.scale / 2,
                               width: iconSize * item.scale, height: iconSize * item.scale)
            return frame.contains(point) ? (index, frame) : nil
        }.min { a, b in
            hypot(a.frame.midX - point.x, a.frame.midY - point.y)
                < hypot(b.frame.midX - point.x, b.frame.midY - point.y)
        }
    }

    /// Dock-style magnification for one page: icons grow toward the pointer and push their
    /// neighbours apart (like the Dock's row spreading), with the spot under the pointer staying put.
    /// Returns each icon's centre and scale, in body coordinates.
    func magnifiedLayout(count: Int, pointer: CGPoint?, amount: CGFloat) -> [(center: CGPoint, scale: CGFloat)] {
        let rest = (0..<count).map { (cellCenter($0), CGFloat(1)) }
        guard let pointer, amount > 0.001, magnification > 1, count > 0 else { return rest }
        let growth = (magnification - 1) * amount
        let radius = max(columnPitch, rowPitch) * 1.6
        func weight(_ d: CGFloat) -> CGFloat { d < radius ? (cos(d / radius * .pi) + 1) / 2 : 0 }

        let columnCount = min(count, columns)
        let rowCount = Int(ceil(Double(count) / Double(columns)))
        let columnCenters = (0..<columnCount).map { cellCenter($0).x }
        let rowCenters = (0..<rowCount).map { cellCenter($0 * columns).y }
        let columnWeights = columnCenters.map { weight(abs($0 - pointer.x)) }
        let rowWeights = rowCenters.map { weight(abs($0 - pointer.y)) }

        // Each column (row) widens by its largest magnified icon, then the line is laid out so
        // the pointer keeps its place within it, exactly like the Dock's row.
        func spread(_ centers: [CGFloat], _ weights: [CGFloat], across: CGFloat, at position: CGFloat,
                    size: CGFloat, gap: CGFloat) -> [CGFloat] {
            let pitch = size + gap
            let sizes = weights.map { size * (1 + growth * $0 * across) }
            let start0 = centers[0] - size / 2
            let u = min(max((position - start0) / pitch, 0), CGFloat(centers.count))
            let whole = min(Int(u), centers.count - 1)
            var before: CGFloat = 0
            for i in 0..<whole { before += sizes[i] + gap }
            before += (u - CGFloat(whole)) * (sizes[whole] + gap)
            var x = start0 + u * pitch - before
            var placed = sizes.map { size -> CGFloat in
                defer { x += size + gap }
                return x + size / 2
            }
            // Stay inside the room the popup leaves for magnification: shift (or, if it can't
            // fit, centre) the line rather than pushing icons past the glass.
            let minEdge = start0 - magnificationRoom
            let maxEdge = centers[centers.count - 1] + size / 2 + magnificationRoom
            let first = placed[0] - sizes[0] / 2
            let last = placed[placed.count - 1] + sizes[sizes.count - 1] / 2
            var shift: CGFloat = 0
            if last - first > maxEdge - minEdge { shift = (minEdge + maxEdge - first - last) / 2 }
            else if first < minEdge { shift = minEdge - first }
            else if last > maxEdge { shift = maxEdge - last }
            if shift != 0 { placed = placed.map { $0 + shift } }
            return placed
        }
        let xs = spread(columnCenters, columnWeights, across: rowWeights.max() ?? 0, at: pointer.x,
                        size: iconSize, gap: columnGap)
        let ys = spread(rowCenters, rowWeights, across: columnWeights.max() ?? 0, at: pointer.y,
                        size: cellHeight, gap: gap)
        return (0..<count).map { index in
            let column = index % columns, row = index / columns
            return (CGPoint(x: xs[column], y: ys[row]), 1 + growth * columnWeights[column] * rowWeights[row])
        }
    }
}

// MARK: - Callout shape (rounded body + Dock-style pointer)

struct CalloutShape: Shape {
    var edge: Edge
    var arrowPosition: CGFloat
    var cornerRadius: CGFloat
    var arrowWidth = FolderMetrics.arrowWidth
    var arrowHeight = FolderMetrics.arrowHeight

    /// The pointer moves with the shape when it resizes, instead of jumping ahead of it.
    var animatableData: CGFloat {
        get { arrowPosition }
        set { arrowPosition = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var body = rect
        switch edge {
        case .bottom: body.size.height -= arrowHeight
        case .top: body.origin.y += arrowHeight; body.size.height -= arrowHeight
        case .leading: body.origin.x += arrowHeight; body.size.width -= arrowHeight
        case .trailing: body.size.width -= arrowHeight
        }
        let rounded = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)

        // Keep the pointer clear of the rounded corners.
        let alongLength = (edge == .bottom || edge == .top) ? body.width : body.height
        let inset = cornerRadius * 0.8 + arrowWidth / 2
        let along = min(max(arrowPosition, inset), alongLength - inset)

        let pointer = Self.pointer(width: arrowWidth, height: arrowHeight)
        let transform: CGAffineTransform
        switch edge {
        case .bottom: transform = CGAffineTransform(translationX: body.minX + along, y: body.maxY)
        case .top: transform = CGAffineTransform(translationX: body.minX + along, y: body.minY).rotated(by: .pi)
        case .leading: transform = CGAffineTransform(translationX: body.minX, y: body.minY + along).rotated(by: .pi / 2)
        case .trailing: transform = CGAffineTransform(translationX: body.maxX, y: body.minY + along).rotated(by: -.pi / 2)
        }
        return rounded.union(pointer.applying(transform))
    }

    /// A pointer whose base sits on y = 0 and whose softly rounded tip points down (+y),
    /// with small concave fillets where it meets the body.
    private static func pointer(width: CGFloat, height: CGFloat) -> Path {
        let half = width / 2
        let fillet = min(5, width * 0.25)
        let tipRadius = min(3, height * 0.4)
        let length = hypot(half, height)
        let down = CGPoint(x: half / length, y: height / length)      // base-left → tip
        let up = CGPoint(x: half / length, y: -height / length)       // tip → base-right
        let baseLeft = CGPoint(x: -half, y: 0), baseRight = CGPoint(x: half, y: 0), tip = CGPoint(x: 0, y: height)

        var p = Path()
        p.move(to: CGPoint(x: -half - fillet, y: -4))
        p.addLine(to: CGPoint(x: -half - fillet, y: 0))
        p.addQuadCurve(to: CGPoint(x: baseLeft.x + down.x * fillet * 0.8, y: baseLeft.y + down.y * fillet * 0.8), control: baseLeft)
        p.addLine(to: CGPoint(x: tip.x - down.x * tipRadius, y: tip.y - down.y * tipRadius))
        p.addQuadCurve(to: CGPoint(x: tip.x + up.x * tipRadius, y: tip.y + up.y * tipRadius), control: tip)
        p.addLine(to: CGPoint(x: baseRight.x - up.x * fillet * 0.8, y: baseRight.y - up.y * fillet * 0.8))
        p.addQuadCurve(to: CGPoint(x: half + fillet, y: 0), control: baseRight)
        p.addLine(to: CGPoint(x: half + fillet, y: -4))
        p.closeSubpath()
        return p
    }
}

// MARK: - Views

struct FolderPanelView: View {
    @ObservedObject var model: FolderPanelModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let m = model.metrics
        let size = m.contentSize(arrowOnSide: model.arrowEdge == .leading || model.arrowEdge == .trailing)
        // A fixed frame: nothing inside can change the window's layout, so nothing shifts.
        ZStack(alignment: .topLeading) {
            popup(m)
                .padding(.horizontal, FolderMetrics.marginH)
                .padding(.top, FolderMetrics.marginTop)
                .padding(.bottom, FolderMetrics.marginBottom)

            appNameLabel(m, size: size)

            // The icon being dragged, lifted above everything and free to leave the folder's edges.
            if let dragging = model.dragging, !model.dragOutside, let app = model.apps.first(where: { $0.id == dragging.id }) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: m.iconSize, height: m.iconSize)
                    .scaleEffect(model.dragLifted ? 1.12 : 1)
                    .shadow(color: .black.opacity(model.dragLifted ? 0.3 : 0), radius: 8, y: 4)
                    .position(x: bodyOrigin.x + dragging.location.x, y: bodyOrigin.y + dragging.location.y)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func appNameLabel(_ m: FolderMetrics, size: CGSize) -> some View {
        let pageApps = apps(on: model.page)
        if model.isPresented, model.hovering, model.isSettled, model.dragging == nil, !model.dropTargeted,
           let point = model.hoverPoint,
           let hit = m.hoveredIcon(count: pageApps.count, point: point, pointer: model.pointer,
                                   amount: model.magnificationAmount),
           !pageApps[hit.index].isPreview {
            let app = pageApps[hit.index]
            let bounds = model.visibleContentBounds ?? CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
            let width = min(DockLabel.width(for: app.name), bounds.width)
            let height = DockLabel.height + DockLabel.pointerHeight
            let iconX = bodyOrigin.x + hit.frame.midX
            let x = min(max(iconX, bounds.minX + width / 2), bounds.maxX - width / 2)
            // Anchor to the visible artwork's top edge, including its magnification.
            let artworkTop = bodyOrigin.y + hit.frame.minY + hit.frame.height * 100 / 1024
            let y = max(bounds.minY + height / 2, artworkTop - 4 - height / 2)
            NameLabel(text: app.name, width: width,
                      arrowPosition: min(max(iconX - x + width / 2, 16), width - 16))
                .position(x: x, y: y)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Top-left of the popup body inside this view.
    private var bodyOrigin: CGPoint {
        CGPoint(x: FolderMetrics.marginH + (model.arrowEdge == .leading ? FolderMetrics.arrowHeight : 0),
                y: FolderMetrics.marginTop + (model.arrowEdge == .top ? FolderMetrics.arrowHeight : 0))
    }

    private func popup(_ m: FolderMetrics) -> some View {
        let shape = CalloutShape(edge: model.arrowEdge, arrowPosition: model.arrowPosition, cornerRadius: m.cornerRadius)
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<m.pages, id: \.self) { page in
                    PageGrid(apps: apps(on: page), metrics: m, model: model,
                             pointer: page == model.page && model.isSettled ? model.pointer : nil,
                             amount: model.magnificationAmount)
                        .frame(width: m.bodyWidth, height: m.stripHeight, alignment: .topLeading)
                }
            }
            .offset(x: model.stripOffset)
            .frame(width: m.bodyWidth, height: m.stripHeight, alignment: .leading)
            // Clip sideways only (pages slide horizontally); magnified icons may grow past the
            // strip's top and bottom into the padding.
            .mask(Rectangle().padding(.vertical, -60))

            if m.pages > 1 {
                PageDots(count: m.pages, current: model.page, select: model.onSelectPage)
                    .frame(width: m.bodyWidth, height: m.dotsHeight)
            }
        }
        .frame(width: m.bodyWidth, height: m.bodyHeight, alignment: .top)
        .padding(arrowEdgeSet, FolderMetrics.arrowHeight)
        // While the Dock's name label for this folder sits under the popup's edge, a soft frost
        // just over it keeps the name from reading through the glass. Everywhere else (and once
        // the label's gone) it's clear glass over whatever is behind.
        .background(labelFrost(m).clipShape(shape))
        .contentShape(shape)
        .dockGlass(in: shape, deepen: false)
        // An app dragged from the Dock will drop in here.
        .overlay(shape.stroke(Color.accentColor, lineWidth: 2.5).opacity(model.dropTargeted ? 0.85 : 0))
        .animation(.easeOut(duration: 0.15), value: model.dropTargeted)
        // Grows out of its pointer, and shrinks back into the tile when it closes (even while
        // riding down with an auto-hiding Dock).
        .scaleEffect(model.isPresented ? 1 : 0.3, anchor: arrowAnchor(m))
        .opacity(model.isPresented ? 1 : 0)
    }

    /// The Dock draws the folder's name label right under the popup's Dock-side edge (while the
    /// pointer is on its tile, or while an auto-hiding Dock is held up), and other apps can't hide
    /// it. Through the glass it's only a soft smudge (light text in Dark Mode, dark in Light
    /// Mode); a gentle neutral veil over just that spot evens it out. No material here: materials
    /// pick up the wallpaper's colour and read as a solid patch.
    private func labelFrost(_ m: FolderMetrics) -> some View {
        let horizontal = model.arrowEdge == .bottom || model.arrowEdge == .top
        let along = model.labelWidth + 24
        let across = DockLabel.height + DockLabel.pointerHeight + 8
        let size = horizontal ? CGSize(width: along, height: across) : CGSize(width: across, height: along)
        let total = CGSize(width: m.bodyWidth + (horizontal ? 0 : FolderMetrics.arrowHeight),
                           height: m.bodyHeight + (horizontal ? FolderMetrics.arrowHeight : 0))
        let center: CGPoint
        switch model.arrowEdge {
        case .bottom: center = CGPoint(x: model.arrowPosition, y: total.height - size.height / 2)
        case .top: center = CGPoint(x: model.arrowPosition, y: size.height / 2)
        case .leading: center = CGPoint(x: size.width / 2, y: model.arrowPosition)
        case .trailing: center = CGPoint(x: total.width - size.width / 2, y: model.arrowPosition)
        }
        let veil = scheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.4)
        return Capsule()
            .fill(veil)
            .frame(width: size.width, height: size.height)
            .blur(radius: 10)
            .position(center)
            .frame(width: total.width, height: total.height)
            .opacity(model.labelUnderneath && model.labelWidth > 0 && !reduceTransparency ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: model.labelUnderneath)
            .allowsHitTesting(false)
    }

    private func apps(on page: Int) -> [FolderApp] {
        let perPage = model.metrics.perPage
        let start = page * perPage
        guard start < model.apps.count else { return [] }
        return Array(model.apps[start..<min(start + perPage, model.apps.count)])
    }

    private var arrowEdgeSet: Edge.Set {
        switch model.arrowEdge {
        case .bottom: return .bottom
        case .top: return .top
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    /// The popup grows out of its pointer, like it's coming out of the Dock tile.
    private func arrowAnchor(_ m: FolderMetrics) -> UnitPoint {
        let w = m.bodyWidth, h = m.bodyHeight
        switch model.arrowEdge {
        case .bottom: return UnitPoint(x: model.arrowPosition / w, y: 1)
        case .top: return UnitPoint(x: model.arrowPosition / w, y: 0)
        case .leading: return UnitPoint(x: 0, y: model.arrowPosition / h)
        case .trailing: return UnitPoint(x: 1, y: model.arrowPosition / h)
        }
    }
}

private struct PageGrid: View {
    let apps: [FolderApp]
    let metrics: FolderMetrics
    let model: FolderPanelModel
    let pointer: CGPoint?
    let amount: CGFloat

    var body: some View {
        let layout = metrics.magnifiedLayout(count: apps.count, pointer: pointer, amount: pointer == nil ? 0 : amount)
        ZStack(alignment: .topLeading) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                // The dragged icon is drawn floating above the folder (so it can go anywhere); its
                // cell stays here invisibly, still tracking the press.
                let lifted = model.dragging?.id == app.id
                AppCell(app: app, metrics: metrics, model: model)
                    .scaleEffect(layout[index].scale)
                    .opacity(lifted ? 0 : 1)
                    .zIndex(Double(layout[index].scale))
                    .position(layout[index].center)
            }
        }
        .frame(width: metrics.bodyWidth, height: metrics.stripHeight, alignment: .topLeading)
    }
}

private struct AppCell: View {
    let app: FolderApp
    let metrics: FolderMetrics
    let model: FolderPanelModel
    @State private var pressed = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: metrics.labelSpacing) {
            icon
            if metrics.showsNames {
                Text(app.name)
                    .font(.system(size: metrics.labelFontSize))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: metrics.labelWidth, height: metrics.labelHeight)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: metrics.iconSize, height: metrics.cellHeight, alignment: .top)
        // A dragged app's landing spot: faint, and not clickable.
        .opacity(app.isPreview ? 0.45 : 1)
        .scaleEffect(app.isPreview ? 0.9 : 1)
        .allowsHitTesting(!app.isPreview)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: app.isPreview)
    }

    private var icon: some View {
        Image(nsImage: app.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: metrics.iconSize, height: metrics.iconSize)
            .brightness(pressed ? -0.25 : 0)
            // Running indicator, placed like the Dock's: centred in the gap under the artwork.
            .overlay(alignment: .bottom) {
                if !metrics.showsNames {
                    Circle()
                        .fill(scheme == .dark ? Color.white : Color.black)
                        .frame(width: 4, height: 4)
                        .opacity(app.isRunning ? 0.62 : 0)
                        .offset(y: metrics.visibleGap / 2 - metrics.artworkInset + 2)
                }
            }
            .overlay(
                ClickCatcher(
                    onPressChanged: { pressed = $0 },
                    onClick: { model.onOpen(app) },
                    onSecondaryClick: { model.onMenu(app, $0) },
                    onDragBegin: { model.onDragBegin(app, $0) },
                    onDragEnd: { model.onDragEnd() }
                )
            )
    }
}

/// An app's name above its icon, drawn like the Dock's own label.
private struct NameLabel: View {
    let text: String
    let width: CGFloat
    let arrowPosition: CGFloat

    var body: some View {
        Text(text)
            .font(Font(DockLabel.font))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, DockLabel.horizontalPadding)
            .frame(width: width, height: DockLabel.height)
            .padding(.bottom, DockLabel.pointerHeight)
            .dockGlass(in: CalloutShape(
                edge: .bottom, arrowPosition: arrowPosition, cornerRadius: DockLabel.height / 2,
                arrowWidth: DockLabel.pointerWidth, arrowHeight: DockLabel.pointerHeight
            ))
            .fixedSize()
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int
    let select: (Int) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(scheme == .dark ? Color.white : Color.black)
                    .opacity(index == current ? 0.85 : 0.25)
                    .frame(width: 6, height: 6)
                    .overlay(ClickCatcher(onPressChanged: { _ in }, onClick: { select(index) }).frame(width: 14, height: 14))
            }
        }
        .animation(.smooth(duration: 0.2), value: current)
    }
}

// MARK: - AppKit click handling
// The popup is a non-activating panel (so your frontmost app stays frontmost, like the Dock's
// own stacks). This view accepts the very first click and reports right-clicks.

struct ClickCatcher: NSViewRepresentable {
    var onPressChanged: (Bool) -> Void
    var onClick: () -> Void
    var onSecondaryClick: ((CGPoint) -> Void)? = nil
    var onDragBegin: ((CGPoint) -> Void)? = nil
    var onDragMove: ((CGPoint) -> Void)? = nil
    var onDragEnd: (() -> Void)? = nil

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onPressChanged = onPressChanged
        view.onClick = onClick
        view.onSecondaryClick = onSecondaryClick
        view.onDragBegin = onDragBegin
        view.onDragMove = onDragMove
        view.onDragEnd = onDragEnd
    }
}

/// Click to open, right-click for the menu, or press and drag to rearrange.
final class CatcherView: NSView {
    var onPressChanged: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onSecondaryClick: ((CGPoint) -> Void)?
    var onDragBegin: ((CGPoint) -> Void)?
    var onDragMove: ((CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?

    private var downPoint: CGPoint?
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { secondary(event); return }
        downPoint = event.locationInWindow
        isDragging = false
        onPressChanged?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint else { return }
        let point = event.locationInWindow
        if !isDragging, onDragBegin != nil, hypot(point.x - downPoint.x, point.y - downPoint.y) > 4 {
            isDragging = true
            onPressChanged?(false)
            onDragBegin?(screen(downPoint))
        }
        if isDragging {
            onDragMove?(screen(point))
        } else {
            onPressChanged?(bounds.contains(convert(point, from: nil)))
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil; isDragging = false }
        if isDragging { onDragEnd?(); return }
        onPressChanged?(false)
        if downPoint != nil, bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) { secondary(event) }

    private func screen(_ windowPoint: CGPoint) -> CGPoint {
        window?.convertPoint(toScreen: windowPoint) ?? windowPoint
    }

    private func secondary(_ event: NSEvent) {
        guard let onSecondaryClick, let window else { return }
        onSecondaryClick(window.convertPoint(toScreen: event.locationInWindow))
    }
}
