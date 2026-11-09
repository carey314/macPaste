import Testing
@testable import Fushi

struct PoolPastePolicyTests {
  @Test("Disabling the switch or choosing copy-only never asks for permissions")
  func explicitCopyChoices() {
    #expect(PoolPastePolicy.decision(enabled: false, copyOnly: false, isolated: false,
                                     trusted: false, hasEditableTarget: false) == .copyOnly)
    #expect(PoolPastePolicy.decision(enabled: true, copyOnly: true, isolated: false,
                                     trusted: false, hasEditableTarget: false) == .copyOnly)
  }

  @Test("Synthetic demos can never send paste events even with full permissions")
  func isolatedDemo() {
    #expect(PoolPastePolicy.decision(enabled: true, copyOnly: false, isolated: true,
                                     trusted: true, hasEditableTarget: true) == .copyOnly)
  }

  @Test("Auto-paste needs both an explicit accessibility grant and a captured input")
  func requiredPreconditions() {
    #expect(PoolPastePolicy.decision(enabled: true, copyOnly: false, isolated: false,
                                     trusted: false, hasEditableTarget: true) == .needsPermission)
    #expect(PoolPastePolicy.decision(enabled: true, copyOnly: false, isolated: false,
                                     trusted: true, hasEditableTarget: false) == .noInput)
    #expect(PoolPastePolicy.decision(enabled: true, copyOnly: false, isolated: false,
                                     trusted: true, hasEditableTarget: true) == .paste)
  }

  @Test("Only text inputs qualify; Finder lists, buttons and web pages do not")
  func textInputRoles() {
    for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
      #expect(PoolPastePolicy.isTextInput(role: role))
    }
    for role in ["AXOutline", "AXButton", "AXWebArea", "AXStaticText", "AXUnknown"] {
      #expect(!PoolPastePolicy.isTextInput(role: role))
    }
  }

  @Test("Read-only text and non-editable controls never qualify as paste targets")
  func readonlyInputs() {
    #expect(!PoolPastePolicy.isEditableTextInput(role: "AXTextArea", valueWritable: false, selectedTextWritable: false))
    #expect(!PoolPastePolicy.isEditableTextInput(role: "AXComboBox", valueWritable: false, selectedTextWritable: false))
    #expect(PoolPastePolicy.isEditableTextInput(role: "AXTextArea", valueWritable: false, selectedTextWritable: true))
    #expect(PoolPastePolicy.isEditableTextInput(role: "AXTextField", valueWritable: true, selectedTextWritable: false))
    #expect(!PoolPastePolicy.isEditableTextInput(role: "AXButton", valueWritable: true, selectedTextWritable: true))
  }

  @Test("Losing target focus, permission or clipboard ownership cancels delivery",
        arguments: [0, 1, 2, 3])
  func changedPrecondition(index: Int) {
    var conditions = [true, true, true, true]
    conditions[index] = false
    #expect(!PoolPastePolicy.canDeliver(trusted: conditions[0], targetActive: conditions[1],
                                      sameInput: conditions[2], clipboardUnchanged: conditions[3]))
    #expect(PoolPastePolicy.canDeliver(trusted: true, targetActive: true,
                                     sameInput: true, clipboardUnchanged: true))
  }
}
