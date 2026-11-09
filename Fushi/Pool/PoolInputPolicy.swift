/// Native field editors and selectable preview text own their editing commands.
/// In particular, Command-Delete must never become deletion of a history item.
nonisolated enum PoolInputPolicy {
  static func defersToTextEditor(keyCode: UInt16, commandPressed: Bool,
                                optionPressed: Bool = false, shiftPressed: Bool = false,
                                previewOpen: Bool = false, textEditorFocused: Bool) -> Bool {
    guard textEditorFocused else { return false }
    let arrowKey = (123...126).contains(keyCode)
    if arrowKey && (optionPressed || shiftPressed || previewOpen) { return true }
    guard commandPressed else { return false }
    switch keyCode {
    case 0, 6, 7, 8, 9, 51, 117, 123, 124, 125, 126: return true
    default: return false
    }
  }

  static func canBeginLegacyDrag(enabled: Bool, pointInsideSource: Bool, textEditorOwnsEvent: Bool) -> Bool {
    enabled && pointInsideSource && !textEditorOwnsEvent
  }
}
