import Foundation

/// Bounded undo history for the CSV preview's in-place edits.
///
/// Stores the *inverse* of each edit rather than a snapshot of the table. At a
/// 50k-row cap a snapshot per keystroke would cost tens of megabytes each and
/// exhaust memory within a normal editing session; an inverse entry is a single
/// cell value or one removed row.
struct FilePreviewCSVUndoStack<Row> {
    /// What to do to put the table back the way it was.
    enum Entry {
        /// Restore `previous` into the cell that was overwritten.
        case setCell(rowID: Int, column: Int, previous: String)
        /// Re-insert a deleted row at the index it came from.
        case insertRow(index: Int, row: Row)
        /// Remove a row again — the inverse of `insertRow`, used when redoing
        /// a deletion that was undone.
        case removeRow(rowID: Int)
        /// Put a deleted column back, with the values every row held in it.
        ///
        /// Unlike the entries above this one is proportional to the row count.
        /// That is affordable here for the reason a snapshot per keystroke is
        /// not: deleting a column is a deliberate, occasional act, so the cost
        /// is paid once rather than on every edit.
        case insertColumn(index: Int, name: String, values: [String])
        /// Delete the column again — the inverse of `insertColumn`.
        case removeColumn(index: Int)
    }

    /// Deep enough for a long editing session, bounded so history cannot grow
    /// without limit.
    static var limit: Int { 500 }

    private(set) var entries: [Entry] = []

    var canUndo: Bool { !entries.isEmpty }
    var count: Int { entries.count }

    mutating func record(_ entry: Entry) {
        entries.append(entry)
        if entries.count > Self.limit {
            entries.removeFirst(entries.count - Self.limit)
        }
    }

    mutating func popLast() -> Entry? {
        entries.popLast()
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}
