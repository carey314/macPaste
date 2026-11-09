import CoreGraphics
import Foundation
import Testing
#if canImport(Fushi)
@testable import Fushi
#else
@testable import PoolLayoutCore
#endif

struct PoolLayoutTests {
  @Test("Empty history has no slots or pages")
  func emptyHistory() {
    #expect(PoolLayout.slots(in: CGSize(width: 900, height: 420), count: 0).isEmpty)
    #expect(PoolLayout.pageCount(total: 0, pageSize: 6) == 0)
    #expect(PoolLayout.clampedPage(9, total: 0, pageSize: 6) == 0)
    #expect(PoolLayout.pageSlice([Int](), page: 9, pageSize: 6).isEmpty)
  }

  @Test("A single item has a readable bounded slot")
  func oneItem() throws {
    let bounds = CGSize(width: 900, height: 420)
    let slots = PoolLayout.slots(in: bounds, count: 1)
    #expect(slots.count == 1)
    let slot = try #require(slots.first)
    #expect(slot.frame.width >= 280)
    #expect(slot.frame.height >= 180)
    #expect(CGRect(origin: .zero, size: bounds).contains(slot.frame))
  }

  @Test("Six objects have distinct sizes without overlap")
  func sixItems() {
    let bounds = CGSize(width: 900, height: 420)
    let slots = PoolLayout.slots(in: bounds, count: 6)
    #expect(slots.count == 6)
    #expect(Set(slots.map { Int($0.frame.width) }).count >= 3)
    for (index, slot) in slots.enumerated() {
      #expect(CGRect(origin: .zero, size: bounds).contains(slot.frame))
      for other in slots.dropFirst(index + 1) {
        #expect(!slot.frame.intersects(other.frame))
      }
    }
    #expect(PoolLayout.slots(in: bounds, count: 1_000).count == 6)
  }

  @Test("Small windows keep every object inside the available bounds",
        arguments: [CGSize(width: 320, height: 180), CGSize(width: 620, height: 260),
                    CGSize(width: 40, height: 40), .zero])
  func smallBounds(bounds: CGSize) {
    let slots = PoolLayout.slots(in: bounds, count: 6)
    #expect(slots.count == (bounds.width > 0 && bounds.height > 0 ? 6 : 0))
    for slot in slots {
      #expect(slot.frame.minX >= 0)
      #expect(slot.frame.minY >= 0)
      #expect(slot.frame.maxX <= bounds.width)
      #expect(slot.frame.maxY <= bounds.height)
      #expect(slot.frame.width > 0)
      #expect(slot.frame.height > 0)
    }
  }

  @Test("Paging is bounded and the last page contains only the remainder")
  func pages() {
    let history = Array(0..<17)
    #expect(PoolLayout.pageCount(total: history.count, pageSize: 6) == 3)
    #expect(PoolLayout.pageSlice(history, page: 0, pageSize: 6) == [0, 1, 2, 3, 4, 5])
    #expect(PoolLayout.pageSlice(history, page: 2, pageSize: 6) == [12, 13, 14, 15, 16])
    #expect(PoolLayout.pageSlice(history, page: 99, pageSize: 6) == [12, 13, 14, 15, 16])
    #expect(PoolLayout.pageSlice(history, page: -9, pageSize: 6) == [0, 1, 2, 3, 4, 5])
  }

  @Test("Search, pinning and deletion clamp a previously selected page")
  func changingResults() {
    let history = Array(0..<25)
    let searched = history.filter { $0 < 3 }
    let unpinned = history.filter { $0 < 6 }
    #expect(PoolLayout.clampedPage(4, total: searched.count, pageSize: 6) == 0)
    #expect(PoolLayout.pageSlice(searched, page: 4, pageSize: 6) == [0, 1, 2])
    #expect(PoolLayout.clampedPage(4, total: unpinned.count, pageSize: 6) == 0)
    #expect(PoolLayout.pageSlice(unpinned, page: 4, pageSize: 6) == Array(0..<6))
  }

  @Test("Invalid sizes and extreme counts cannot overflow paging")
  func invalidInputs() {
    #expect(PoolLayout.pageCount(total: -1, pageSize: 6) == 0)
    #expect(PoolLayout.pageCount(total: 3, pageSize: 0) == 3)
    #expect(PoolLayout.pageCount(total: Int.max, pageSize: 6) == Int.max / 6 + 1)
    #expect(PoolLayout.pageSlice([1, 2, 3], page: Int.max, pageSize: 0) == [3])
    #expect(PoolLayout.slots(in: CGSize(width: -20, height: 100), count: 6).isEmpty)
  }
}

struct PoolInputPolicyTests {
  @Test("Text editors own copy, delete and other native command editing shortcuts",
        arguments: [UInt16(0), 6, 7, 8, 9, 51, 117, 123, 124, 125, 126])
  func textEditingOwnsCommands(keyCode: UInt16) {
    #expect(PoolInputPolicy.defersToTextEditor(keyCode: keyCode, commandPressed: true, textEditorFocused: true))
  }

  @Test("Copy and delete may act on history only when no text editor owns focus", arguments: [UInt16(8), 51])
  func historyCommandsWithoutEditor(keyCode: UInt16) {
    #expect(!PoolInputPolicy.defersToTextEditor(keyCode: keyCode, commandPressed: true, textEditorFocused: false))
  }

  @Test("Search and preferences remain application commands; ordinary typing stays outside this command policy")
  func applicationCommands() {
    #expect(!PoolInputPolicy.defersToTextEditor(keyCode: 3, commandPressed: true, textEditorFocused: true))
    #expect(!PoolInputPolicy.defersToTextEditor(keyCode: 43, commandPressed: true, textEditorFocused: true))
    #expect(!PoolInputPolicy.defersToTextEditor(keyCode: 8, commandPressed: false, textEditorFocused: true))
  }
}

extension PoolInputPolicyTests {
  @Test("Option arrows move or extend the text caret instead of paging history",
        arguments: [UInt16(123), 124, 125, 126], [false, true])
  func optionArrowEditing(keyCode: UInt16, shiftPressed: Bool) {
    #expect(PoolInputPolicy.defersToTextEditor(keyCode: keyCode, commandPressed: false,
                                              optionPressed: true, shiftPressed: shiftPressed,
                                              textEditorFocused: true))
  }

  @Test("Shift arrows select native text instead of changing history selection", arguments: [UInt16(123), 124, 125, 126])
  func shiftArrowSelection(keyCode: UInt16) {
    #expect(PoolInputPolicy.defersToTextEditor(keyCode: keyCode, commandPressed: false,
                                              shiftPressed: true, textEditorFocused: true))
  }

  @Test("Plain arrows belong to focused preview text", arguments: [UInt16(123), 124, 125, 126])
  func previewTextNavigation(keyCode: UInt16) {
    #expect(PoolInputPolicy.defersToTextEditor(keyCode: keyCode, commandPressed: false,
                                              previewOpen: true, textEditorFocused: true))
    #expect(!PoolInputPolicy.defersToTextEditor(keyCode: keyCode, commandPressed: false,
                                               optionPressed: true, previewOpen: true, textEditorFocused: false))
  }

  @Test("Command Delete remains native with additional editing modifiers", arguments: [false, true], [false, true])
  func commandDeleteEditing(optionPressed: Bool, shiftPressed: Bool) {
    #expect(PoolInputPolicy.defersToTextEditor(keyCode: 51, commandPressed: true,
                                              optionPressed: optionPressed, shiftPressed: shiftPressed,
                                              textEditorFocused: true))
  }

  @Test("Underlying legacy cards cannot drag through a preview or text editor",
        arguments: Array(0..<8))
  func legacyDragOwnership(state: Int) {
    let enabled = state & 1 != 0
    let pointInsideSource = state & 2 != 0
    let textEditorOwnsEvent = state & 4 != 0
    let allowed = PoolInputPolicy.canBeginLegacyDrag(enabled: enabled, pointInsideSource: pointInsideSource,
                                                      textEditorOwnsEvent: textEditorOwnsEvent)
    if !enabled || textEditorOwnsEvent || !pointInsideSource { #expect(!allowed) }
    else { #expect(allowed) }
  }
}
