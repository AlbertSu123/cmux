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
