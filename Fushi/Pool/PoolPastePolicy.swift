/// Paste requires an intentional selection, an editable target and unchanged focus/clipboard.
nonisolated enum PoolPastePolicy {
  enum Decision: Equatable { case copyOnly, needsPermission, noInput, paste }

  static func decision(enabled: Bool, copyOnly: Bool, isolated: Bool,
                       trusted: Bool, hasEditableTarget: Bool) -> Decision {
    if !enabled || copyOnly || isolated { return .copyOnly }
    if !trusted { return .needsPermission }
    if !hasEditableTarget { return .noInput }
    return .paste
  }

  static func isTextInput(role: String) -> Bool {
    ["AXTextField", "AXTextArea", "AXComboBox"].contains(role)
  }

  static func isEditableTextInput(role: String, valueWritable: Bool, selectedTextWritable: Bool) -> Bool {
    isTextInput(role: role) && (valueWritable || selectedTextWritable)
  }

  static func canDeliver(trusted: Bool, targetActive: Bool, sameInput: Bool,
                         clipboardUnchanged: Bool) -> Bool {
    trusted && targetActive && sameInput && clipboardUnchanged
  }
}
