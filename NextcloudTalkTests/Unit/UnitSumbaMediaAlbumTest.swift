//
// SPDX-FileCopyrightText: 2026 Peter Zakharov
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import SumbaChat

final class UnitSumbaMediaAlbumTest: XCTestCase {

    private func albumMember(uuid: String, index: Int, count: Int, messageId: Int, body: String) -> NCChatMessage {
        let message = NCChatMessage()
        message.messageId = messageId
        message.referenceId = SumbaMediaAlbum.referenceId(uuid: uuid, index: index, count: count)
        message.message = body
        message.actorId = "user1"
        return message
    }

    func testReplacingMemberPreservesAlbumAfterEdit() {
        let uuid = "66167e11-1b76-4dfc-952e-64ab51c2a44b"
        let members = (1...3).map { albumMember(uuid: uuid, index: $0, count: 3, messageId: $0, body: "{file}") }
        members[2].message = "3 media files"

        let collapsed = SumbaMediaAlbum.collapseForDisplay(members)
        let primary = try! XCTUnwrap(collapsed.first)
        XCTAssertEqual(primary.sumbaAlbumMembers?.count, 3)

        let edited = try! XCTUnwrap(primary.copy() as? NCChatMessage)
        edited.message = "Updated caption"
        edited.lastEditTimestamp = 1_700_000_000

        let merged = try! XCTUnwrap(SumbaMediaAlbum.replacingMember(in: primary, with: edited))
        XCTAssertEqual(merged.sumbaAlbumMembers?.count, 3)
        XCTAssertEqual(merged.message, "Updated caption")
        XCTAssertEqual(merged.sumbaAlbumMembers?.last?.message, "Updated caption")
        XCTAssertEqual(merged.sumbaAlbumMembers?.first?.message, "{file}")
    }

    func testEditableCaptionStripsSyntheticAlbumSummary() {
        let message = NCChatMessage()
        message.referenceId = SumbaMediaAlbum.referenceId(uuid: "66167e11-1b76-4dfc-952e-64ab51c2a44b", index: 3, count: 3)
        message.message = "3 media files"

        XCTAssertEqual(message.editableCaptionText, "")
        XCTAssertNil(message.chatBodyAttributedText)
        XCTAssertNil(SumbaMediaAlbumReference.cleanedUserCaption("3 media files"))
    }

    func testAlbumCaptionUsesChatBodyTypography() {
        let message = NCChatMessage()
        message.referenceId = SumbaMediaAlbum.referenceId(uuid: "66167e11-1b76-4dfc-952e-64ab51c2a44b", index: 3, count: 3)
        message.message = "Can you read Tim (3 media files)"

        let body = try! XCTUnwrap(message.chatBodyAttributedText)
        let font = body.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertEqual(font, UIFont.preferredFont(forTextStyle: .body))
        let color = body.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color, UIColor.label)
        XCTAssertTrue(body.string.contains("Can you read Tim"))
    }
}
