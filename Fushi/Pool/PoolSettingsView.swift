import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

/// Only preferences implemented by the pool experience are exposed here.
struct PoolSettingsView: View {
  @Default(.ignoreEvents) private var paused
  @Default(.size) private var historySize
  @Default(.searchMode) private var searchMode
  @Default(.poolAutoPaste) private var autoPaste
  @State private var permissionAllowed = Accessibility.isAllowed

  var body: some View {
    Form {
      Section {
        HStack(spacing: 15) {
          Image(nsImage: PoolBrand.icon).resizable().scaledToFit().frame(width: 58, height: 58)
          VStack(alignment: .leading, spacing: 4) {
            Text("浮拾").font(.title2.weight(.semibold))
            Text("让复制过的灵感，有处可拾。").foregroundStyle(.secondary)
          }
        }.padding(.vertical, 6)
      }
      Section("呼出与操作") {
        HStack {
          Text("打开浮拾")
          Spacer()
          KeyboardShortcuts.Recorder(for: .popup) { shortcut in
            if shortcut == nil { AppState.shared.popup.deinitEventsMonitor() }
            else { AppState.shared.popup.initEventsMonitor() }
          }
        }
        Toggle("点击条目后自动粘贴", isOn: $autoPaste)
          .accessibilityIdentifier("pool-auto-paste")
        Text("开启：点击或回车后粘贴到原输入框。关闭：只复制。右键“仅复制”始终只复制。")
          .font(.caption).foregroundStyle(.secondary)
        if autoPaste {
          HStack {
            Label(permissionAllowed ? "辅助功能权限已开启" : "需要辅助功能权限", systemImage: permissionAllowed ? "checkmark.shield" : "lock")
              .font(.caption).foregroundStyle(permissionAllowed ? .secondary : .primary)
            Spacer()
            Button(permissionAllowed ? "系统设置…" : "去开启…") { Accessibility.openSettings() }
              .accessibilityIdentifier("pool-accessibility-settings")
          }
        }
        Text("方向键选择 · 空格预览 · Esc 收起。也可以把内容直接拖进输入框。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("本地历史") {
        Toggle("暂停收集新内容", isOn: $paused)
        Stepper("保留最近 \(historySize) 条", value: $historySize, in: 50...2000, step: 50)
        Picker("搜索方式", selection: $searchMode) {
          ForEach(Search.Mode.allCases) { mode in Text(mode.description).tag(mode) }
        }
        Text("常用内容单独保留。新复制的文字、图片、链接和文件会进入池中。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section {
        HStack {
          Text("基于 Maccy 2.8.0 · MIT License").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Link("原项目", destination: URL(string: "https://github.com/p0deje/Maccy")!)
        }
      }
    }
    .formStyle(.grouped).frame(width: 480, height: 650)
    .onChange(of: historySize) { Task { try? await History.shared.load() } }
    .onChange(of: autoPaste) {
      if autoPaste && !PoolExperience.usesIsolatedData { Accessibility.requestAuthorization() }
      permissionAllowed = Accessibility.isAllowed
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      permissionAllowed = Accessibility.isAllowed
    }
  }
}
