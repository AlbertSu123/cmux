import CoreGraphics
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct FilePreviewCSVColumnLayoutTests {
    private func layout(_ widths: [CGFloat]) -> FilePreviewCSVColumnLayout {
        FilePreviewCSVColumnLayout(widths: widths)
    }

    @Test func startsInFileOrderWithClampedWidths() {
        let subject = layout([10, 100, 5000])
        #expect(subject.order == [0, 1, 2])
        #expect(subject.width(ofColumn: 0) == FilePreviewCSVColumnLayout.minimumWidth)
        #expect(subject.width(ofColumn: 1) == 100)
        #expect(subject.width(ofColumn: 2) == FilePreviewCSVColumnLayout.maximumWidth)
    }

    @Test func resizeClampsToBounds() {
        var subject = layout([100, 100])
        subject.resize(column: 0, to: 250)
        #expect(subject.width(ofColumn: 0) == 250)

        subject.resize(column: 0, to: -40)
        #expect(subject.width(ofColumn: 0) == FilePreviewCSVColumnLayout.minimumWidth)

        subject.resize(column: 0, to: 99_999)
        #expect(subject.width(ofColumn: 0) == FilePreviewCSVColumnLayout.maximumWidth)
    }

    @Test func resizeIgnoresOutOfRangeColumns() {
        var subject = layout([100, 100])
        subject.resize(column: 7, to: 300)
        #expect(subject.widths == [100, 100])
    }

    @Test func resizeFollowsTheSourceColumnAfterReordering() {
        var subject = layout([100, 200, 300])
        subject.move(fromDisplayIndex: 0, toDisplayIndex: 2)
        subject.resize(column: 0, to: 150)
        // Column 0 now renders last; its width must travel with it.
        #expect(subject.order == [1, 2, 0])
        #expect(subject.orderedWidths == [200, 300, 150])
    }

    @Test func moveReordersColumnsAndClampsDestination() {
        var subject = layout([100, 100, 100])
        subject.move(fromDisplayIndex: 0, toDisplayIndex: 2)
        #expect(subject.order == [1, 2, 0])

        subject.move(fromDisplayIndex: 2, toDisplayIndex: 99)
        #expect(subject.order == [1, 2, 0])

        subject.move(fromDisplayIndex: 2, toDisplayIndex: -5)
        #expect(subject.order == [0, 1, 2])
    }

    @Test func moveToSameSlotIsANoOp() {
        var subject = layout([100, 200])
        subject.move(fromDisplayIndex: 1, toDisplayIndex: 1)
        #expect(subject.order == [0, 1])
    }

    @Test func offsetAccumulatesPrecedingWidthsInDisplayOrder() {
        var subject = layout([100, 200, 300])
        #expect(subject.offset(ofDisplayIndex: 0) == 0)
        #expect(subject.offset(ofDisplayIndex: 2) == 300)

        subject.move(fromDisplayIndex: 2, toDisplayIndex: 0)
        #expect(subject.orderedWidths == [300, 100, 200])
        #expect(subject.offset(ofDisplayIndex: 1) == 300)
    }

    @Test func dropIndexHoldsPositionForSmallDrags() {
        let subject = layout([100, 100, 100])
        #expect(subject.dropIndex(draggingDisplayIndex: 1, translation: 0) == 1)
        #expect(subject.dropIndex(draggingDisplayIndex: 1, translation: 20) == 1)
    }

    @Test func dropIndexAdvancesOnceTheColumnCentreCrossesItsNeighbour() {
        let subject = layout([100, 100, 100])
        // Centre of slot 0 is 50; crossing slot 1's centre (150) needs > 100.
        #expect(subject.dropIndex(draggingDisplayIndex: 0, translation: 60) == 0)
        #expect(subject.dropIndex(draggingDisplayIndex: 0, translation: 120) == 1)
        #expect(subject.dropIndex(draggingDisplayIndex: 0, translation: 260) == 2)
    }

    @Test func dropIndexClampsAtBothEnds() {
        let subject = layout([100, 100, 100])
        #expect(subject.dropIndex(draggingDisplayIndex: 2, translation: -10_000) == 0)
        #expect(subject.dropIndex(draggingDisplayIndex: 0, translation: 10_000) == 2)
    }

    @Test func dropIndexRespectsUnevenColumnWidths() {
        let subject = layout([400, 60, 60])
        // Wide first column: its centre starts at 200 and must pass 430 and 490.
        #expect(subject.dropIndex(draggingDisplayIndex: 0, translation: 200) == 0)
        #expect(subject.dropIndex(draggingDisplayIndex: 0, translation: 240) == 1)
    }

    @Test func emptyLayoutIsInert() {
        var subject = layout([])
        #expect(subject.columnCount == 0)
        #expect(subject.totalWidth == 0)
        subject.move(fromDisplayIndex: 0, toDisplayIndex: 1)
        subject.resize(column: 0, to: 100)
        #expect(subject.order.isEmpty)
        #expect(subject.dropIndex(draggingDisplayIndex: 0, translation: 50) == 0)
    }
}

@Suite struct FilePreviewCSVCellLinkTests {
    @Test(arguments: [
        "https://github.com/alamb",
        "http://example.com/path?a=b",
    ])
    func recognisesWebURLs(_ cell: String) {
        #expect(FilePreviewCSVCellLink.url(for: cell)?.absoluteString == cell)
    }

    @Test func upgradesBareWWWToHTTPS() {
        #expect(
            FilePreviewCSVCellLink.url(for: "www.example.com")?.absoluteString
                == "https://www.example.com"
        )
    }

    @Test func recognisesEmailAddressesAsMailto() {
        #expect(
            FilePreviewCSVCellLink.url(for: "neil.conway@gmail.com")?.absoluteString
                == "mailto:neil.conway@gmail.com"
        )
    }

    @Test func passesThroughExistingMailto() {
        #expect(
            FilePreviewCSVCellLink.url(for: "mailto:a@b.com")?.absoluteString == "mailto:a@b.com"
        )
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(
            FilePreviewCSVCellLink.url(for: "  https://example.com  ")?.absoluteString
                == "https://example.com"
        )
    }

    @Test func usesTheFirstTokenOfAMultiLinkCell() {
        let cell = "https://a.example ; https://b.example"
        #expect(FilePreviewCSVCellLink.url(for: cell)?.absoluteString == "https://a.example")
    }

    @Test func usesTheFirstAddressOfASemicolonSeparatedEmailCell() {
        let cell = "first@example.com; second@example.com"
        #expect(FilePreviewCSVCellLink.url(for: cell)?.absoluteString == "mailto:first@example.com")
    }

    @Test(arguments: [
        "",
        "   ",
        "Andrew Lamb",
        "a plain sentence mentioning @someone in passing",
        "not-an-email@",
        "@leadinghandle",
        "user@localhost",
        "user@domain.",
        "375",
        "DataFusion — the embeddable Rust SQL query engine",
    ])
    func rejectsNonLinks(_ cell: String) {
        #expect(FilePreviewCSVCellLink.url(for: cell) == nil)
    }
}

@Suite struct FilePreviewCSVSerializerTests {
    @Test func leavesPlainFieldsUnquoted() {
        #expect(FilePreviewCSVSerializer.field("alamb", delimiter: ",") == "alamb")
    }

    @Test func quotesFieldsContainingTheDelimiter() {
        #expect(
            FilePreviewCSVSerializer.field("Boston, USA", delimiter: ",") == "\"Boston, USA\""
        )
        // The same text is safe in a TSV.
        #expect(FilePreviewCSVSerializer.field("Boston, USA", delimiter: "\t") == "Boston, USA")
    }

    @Test func doublesEmbeddedQuotes() {
        #expect(
            FilePreviewCSVSerializer.field("say \"hi\"", delimiter: ",") == "\"say \"\"hi\"\"\""
        )
    }

    @Test func quotesFieldsWithNewlinesOrEdgeWhitespace() {
        #expect(FilePreviewCSVSerializer.field("a\nb", delimiter: ",") == "\"a\nb\"")
        #expect(FilePreviewCSVSerializer.field(" pad", delimiter: ",") == "\" pad\"")
        #expect(FilePreviewCSVSerializer.field("pad ", delimiter: ",") == "\"pad \"")
    }

    @Test func serializesHeaderAndRows() {
        let text = FilePreviewCSVSerializer.serialize(
            header: ["name", "note"],
            rows: [["alamb", "Boston, USA"], ["orlp", "pdqsort"]],
            delimiter: ","
        )
        #expect(text == "name,note\nalamb,\"Boston, USA\"\norlp,pdqsort\n")
    }

    @Test func roundTripsThroughAFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmux-csv-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try FilePreviewCSVSerializer.write(
            header: ["a", "b"],
            rows: [["1", "x,y"], ["2", "he said \"no\""]],
            delimiter: ",",
            to: url
        )
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == "a,b\n1,\"x,y\"\n2,\"he said \"\"no\"\"\"\n")
    }

    @Test func writeReplacesExistingContentRatherThanAppending() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmux-csv-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("stale,content\nrow,row\n".utf8).write(to: url)
        try FilePreviewCSVSerializer.write(
            header: ["a"], rows: [["1"]], delimiter: ",", to: url
        )
        #expect(try String(contentsOf: url, encoding: .utf8) == "a\n1\n")
    }
}

@Suite struct FilePreviewCSVUndoStackTests {
    private typealias Stack = FilePreviewCSVUndoStack<String>

    @Test func startsEmpty() {
        let stack = Stack()
        #expect(!stack.canUndo)
        #expect(stack.count == 0)
    }

    @Test func popsMostRecentEntryFirst() throws {
        var stack = Stack()
        stack.record(.setCell(rowID: 1, column: 0, previous: "first"))
        stack.record(.setCell(rowID: 2, column: 1, previous: "second"))
        #expect(stack.count == 2)

        let popped = stack.popLast()
        guard case let .setCell(rowID, column, previous) = try #require(popped) else {
            Issue.record("expected a setCell entry")
            return
        }
        #expect(rowID == 2)
        #expect(column == 1)
        #expect(previous == "second")
        #expect(stack.count == 1)
    }

    @Test func retainsRowPayloadForDeletions() throws {
        var stack = Stack()
        stack.record(.insertRow(index: 3, row: "deleted-row"))
        let popped = stack.popLast()
        guard case let .insertRow(index, row) = try #require(popped) else {
            Issue.record("expected an insertRow entry")
            return
        }
        #expect(index == 3)
        #expect(row == "deleted-row")
    }

    @Test func dropsOldestEntriesPastTheLimit() throws {
        var stack = Stack()
        for i in 0..<(Stack.limit + 25) {
            stack.record(.setCell(rowID: i, column: 0, previous: "\(i)"))
        }
        #expect(stack.count == Stack.limit)
        // The newest entry survives; the oldest 25 were evicted.
        let popped = stack.popLast()
        guard case let .setCell(rowID, _, _) = try #require(popped) else {
            Issue.record("expected a setCell entry")
            return
        }
        #expect(rowID == Stack.limit + 24)
    }

    @Test func removeAllClearsHistory() {
        var stack = Stack()
        stack.record(.setCell(rowID: 1, column: 0, previous: "x"))
        stack.removeAll()
        #expect(!stack.canUndo)
        #expect(stack.popLast() == nil)
    }

    @Test func popOnEmptyStackReturnsNil() {
        var stack = Stack()
        #expect(stack.popLast() == nil)
    }
}

@Suite struct FilePreviewCSVRedoEntryTests {
    private typealias Stack = FilePreviewCSVUndoStack<String>

    @Test func removeRowEntryCarriesItsRowID() throws {
        var stack = Stack()
        stack.record(.removeRow(rowID: 42))
        let popped = stack.popLast()
        guard case let .removeRow(rowID) = try #require(popped) else {
            Issue.record("expected a removeRow entry")
            return
        }
        #expect(rowID == 42)
    }

    @Test func undoAndRedoStacksAreIndependent() throws {
        var undo = Stack()
        var redo = Stack()
        undo.record(.setCell(rowID: 1, column: 0, previous: "before"))

        // Undo pops from one stack and pushes the inverse onto the other.
        let entry = undo.popLast()
        _ = try #require(entry)
        redo.record(.setCell(rowID: 1, column: 0, previous: "after"))

        #expect(!undo.canUndo)
        #expect(redo.canUndo)

        let redone = redo.popLast()
        guard case let .setCell(_, _, previous) = try #require(redone) else {
            Issue.record("expected a setCell entry")
            return
        }
        #expect(previous == "after")
    }

    @Test func redoHistoryIsBoundedLikeUndo() {
        var stack = Stack()
        for i in 0..<(Stack.limit + 10) {
            stack.record(.removeRow(rowID: i))
        }
        #expect(stack.count == Stack.limit)
    }
}

@Suite struct FilePreviewCSVColumnShiftTests {
    private func layout(_ widths: [CGFloat]) -> FilePreviewCSVColumnLayout {
        FilePreviewCSVColumnLayout(widths: widths)
    }

    @Test func shiftsRightAndLeft() {
        var subject = layout([100, 200, 300])
        let right = subject.shift(column: 0, by: 1)
        #expect(right)
        #expect(subject.order == [1, 0, 2])
        let left = subject.shift(column: 0, by: -1)
        #expect(left)
        #expect(subject.order == [0, 1, 2])
    }

    @Test func refusesToShiftPastEitherEnd() {
        var subject = layout([100, 100, 100])
        let offLeft = subject.shift(column: 0, by: -1)
        #expect(!offLeft)
        #expect(subject.order == [0, 1, 2])
        let offRight = subject.shift(column: 2, by: 1)
        #expect(!offRight)
        #expect(subject.order == [0, 1, 2])
    }

    @Test func shiftTracksTheColumnNotTheSlot() {
        var subject = layout([100, 200, 300])
        // Move column 2 to the front, then keep nudging that same column.
        let first = subject.shift(column: 2, by: -1)
        #expect(first)
        #expect(subject.order == [0, 2, 1])
        let second = subject.shift(column: 2, by: -1)
        #expect(second)
        #expect(subject.order == [2, 0, 1])
        let third = subject.shift(column: 2, by: -1)
        #expect(!third)
    }

    @Test func shiftCarriesTheColumnWidth() {
        var subject = layout([100, 200, 300])
        subject.resize(column: 0, to: 150)
        let moved = subject.shift(column: 0, by: 2)
        #expect(moved)
        #expect(subject.orderedWidths == [200, 300, 150])
    }

    @Test func shiftIgnoresUnknownColumns() {
        var subject = layout([100, 100])
        let moved = subject.shift(column: 9, by: 1)
        #expect(!moved)
        #expect(subject.order == [0, 1])
    }

    @Test func displayIndexFollowsReordering() {
        var subject = layout([100, 100, 100])
        #expect(subject.displayIndex(ofColumn: 2) == 2)
        subject.move(fromDisplayIndex: 2, toDisplayIndex: 0)
        #expect(subject.displayIndex(ofColumn: 2) == 0)
        #expect(subject.displayIndex(ofColumn: 99) == nil)
    }
}
