import CoreGraphics
import Foundation

/// Column geometry and display ordering for the CSV preview grid.
///
/// This is a pure value type on purpose: the grid renders its rows inside a
/// `LazyVStack`, and the snapshot-boundary rule forbids anything below that
/// boundary from holding a reference to an observable store. Rows receive a
/// copy of this struct, never a binding to one.
struct FilePreviewCSVColumnLayout: Equatable {
    /// Narrow enough to collapse a column to a stub, wide enough to stay grabbable.
    static let minimumWidth: CGFloat = 44
    static let maximumWidth: CGFloat = 1200

    /// Widths indexed by *source* column (the order the columns appear in the file).
    private(set) var widths: [CGFloat]
    /// Source column indices in display order.
    private(set) var order: [Int]

    init(widths: [CGFloat]) {
        self.widths = widths.map(Self.clamped)
        self.order = Array(widths.indices)
    }

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumWidth), maximumWidth)
    }

    var columnCount: Int { widths.count }

    /// Widths laid out left to right as the user currently sees them.
    var orderedWidths: [CGFloat] { order.map { widths[$0] } }

    var totalWidth: CGFloat { widths.reduce(0, +) }

    func width(ofColumn column: Int) -> CGFloat {
        widths.indices.contains(column) ? widths[column] : Self.minimumWidth
    }

    /// Resize a source column, clamping to the allowed range.
    mutating func resize(column: Int, to width: CGFloat) {
        guard widths.indices.contains(column) else { return }
        widths[column] = Self.clamped(width)
    }

    /// Leading x offset of a display slot, in points from the grid's left edge.
    func offset(ofDisplayIndex index: Int) -> CGFloat {
        let ordered = orderedWidths
        guard ordered.indices.contains(index) else { return 0 }
        return ordered[..<index].reduce(0, +)
    }

    /// Display slot a column dragged horizontally by `translation` should land in.
    ///
    /// Compares the dragged column's midpoint against its neighbours' midpoints
    /// in the *pre-drag* coordinate space and counts how many it has passed, so
    /// the drop target flips exactly when the column visually overtakes a
    /// neighbour. Walking accumulated edges instead would double-count the
    /// dragged column's own width and skip a slot on every drag.
    func dropIndex(draggingDisplayIndex from: Int, translation: CGFloat) -> Int {
        let ordered = orderedWidths
        guard ordered.indices.contains(from) else { return from }
        var centres: [CGFloat] = []
        centres.reserveCapacity(ordered.count)
        var edge: CGFloat = 0
        for width in ordered {
            centres.append(edge + width / 2)
            edge += width
        }
        let dragged = centres[from] + translation
        var destination = from
        if translation > 0 {
            var index = from + 1
            while index < centres.count, centres[index] < dragged {
                destination = index
                index += 1
            }
        } else if translation < 0 {
            var index = from - 1
            while index >= 0, centres[index] > dragged {
                destination = index
                index -= 1
            }
        }
        return destination
    }

    /// Move a column between display slots. Out-of-range slots are clamped.
    mutating func move(fromDisplayIndex from: Int, toDisplayIndex to: Int) {
        guard order.indices.contains(from) else { return }
        let destination = min(max(to, 0), order.count - 1)
        guard destination != from else { return }
        let column = order.remove(at: from)
        order.insert(column, at: destination)
    }
}
