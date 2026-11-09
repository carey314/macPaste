import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct PoolContentView: View {
  @Default(.poolAutoPaste) private var autoPaste
  @Environment(AppState.self) private var appState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @FocusState private var searchFocused: Bool
  @State private var page = 0
  @State private var previewItem: HistoryItemDecorator?
  @State private var activeDragID: UUID?
  @State private var favoriteTargeted = false

  private var ink: Color {
    colorScheme == .dark ? Color(red: 0.91, green: 0.95, blue: 0.99)
      : Color(red: 0.16, green: 0.21, blue: 0.28)
  }
  private var recent: [HistoryItemDecorator] { appState.history.unpinnedItems }
  private var favorites: [HistoryItemDecorator] { appState.history.pinnedItems }
  private var visibleItems: [HistoryItemDecorator] { PoolLayout.pageSlice(recent, page: page) }
  private var currentPage: Int { PoolLayout.clampedPage(page, total: recent.count) }
  private var pages: Int { PoolLayout.pageCount(total: recent.count) }
  private var keyboardItems: [HistoryItemDecorator] { visibleItems + favorites }

  private var surface: some View {
    GeometryReader { geometry in
      let horizontalPadding = max(24, geometry.size.width * 0.042)
      ZStack {
        basin
        VStack(spacing: 0) {
          header(width: geometry.size.width)
            .padding(.horizontal, max(34, geometry.size.width * 0.075))
            .padding(.top, max(27, geometry.size.height * 0.075))
            .padding(.bottom, 17)
          HStack(spacing: geometry.size.width < 720 ? 12 : 22) {
            deck
            favoriteRail.frame(width: geometry.size.width < 720 ? 78 : 96)
          }
          .padding(.leading, horizontalPadding)
          .padding(.trailing, horizontalPadding + 5)
          footer.padding(.horizontal, horizontalPadding)
            .padding(.top, 16).padding(.bottom, max(24, geometry.size.height * 0.055))
        }
        if let item = previewItem {
          preview(item, in: geometry.size)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
            .zIndex(100)
        }
      }
      .foregroundStyle(ink)
      .padding(20)
      .background {
        PoolInputCapture(keyDown: handleKey)
      }
    }
  }

  private var lifecycleSurface: some View {
    surface
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("shiguang-pool")
    .accessibilityValue(previewItem == nil ? "preview-closed" : "preview-open")
    .task {
      try? await appState.history.load()
      reconcileSelection()
    }
    .onAppear {
      appState.preview.disableAutoOpen()
      endDrag()
      reconcileSelection()
      searchFocused = true
      #if DEBUG
      if PoolExperience.isDemo {
        PoolDemo.previewIsOpen = previewItem != nil
        PoolDemo.currentPage = page
      }
      #endif
    }
    .onDisappear { endDrag(); previewItem?.cleanupImages(); previewItem = nil }
    .onChange(of: previewItem) { previous, current in
      if previous?.id != current?.id { previous?.cleanupImages() }
      if current == nil { searchFocused = true }
    }
    .onChange(of: previewItem?.id) {
      #if DEBUG
      if PoolExperience.isDemo { PoolDemo.previewIsOpen = previewItem != nil }
      #endif
    }
    .onChange(of: page) {
      #if DEBUG
      if PoolExperience.isDemo { PoolDemo.currentPage = page }
      #endif
    }
  }

  var body: some View {
    lifecycleSurface
    .onChange(of: appState.history.searchQuery) {
      page = 0
      previewItem = nil
    }
    .onChange(of: recent.map(\.id)) {
      page = currentPage
      reconcileSelection()
    }
    .onChange(of: favorites.map(\.id)) { reconcileSelection() }
    .onChange(of: appState.navigator.leadSelection) {
      if let selected = appState.navigator.leadSelection,
         let index = recent.firstIndex(where: { $0.id == selected }) {
        page = index / PoolLayout.pageSize
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
      guard let window = notification.object as? NSWindow,
            window.identifier?.rawValue == Bundle.main.bundleIdentifier else { return }
      appState.preview.disableAutoOpen()
      reconcileSelection()
      searchFocused = true
    }
  }

  private var basin: some View {
    PoolBasinShape()
      .fill(.ultraThinMaterial)
      .overlay {
        PoolBasinShape().fill(LinearGradient(
          colors: [Color(red: 0.83, green: 0.92, blue: 1).opacity(0.33),
                   Color(red: 0.57, green: 0.72, blue: 0.86).opacity(0.18), .white.opacity(0.20)],
          startPoint: .topLeading, endPoint: .bottomTrailing
        ))
      }
      .overlay {
        PoolBasinShape().stroke(LinearGradient(
          colors: [.white.opacity(0.94), .white.opacity(0.38), .white.opacity(0.70)],
          startPoint: .topLeading, endPoint: .bottomTrailing
        ), lineWidth: 2)
      }
      .overlay {
        PoolBasinShape().stroke(.white.opacity(0.5), lineWidth: 6).blur(radius: 5).padding(3)
      }
      .shadow(color: Color(red: 0.16, green: 0.34, blue: 0.54).opacity(0.24), radius: 24, y: 16)
      .allowsHitTesting(false)
  }

  private func header(width: CGFloat) -> some View {
    @Bindable var history = appState.history
    return HStack(spacing: width < 720 ? 12 : 20) {
      Text("浮拾").font(.system(size: width < 720 ? 23 : 27, weight: .semibold))
        .tracking(0.5).accessibilityAddTraits(.isHeader)
      if PoolExperience.isDemo {
        Text("演示").font(.system(size: 10, weight: .medium))
          .padding(.horizontal, 7).padding(.vertical, 4)
          .background(.white.opacity(0.25), in: Capsule())
          .accessibilityLabel("演示模式，内容为合成示例")
          .accessibilityIdentifier("pool-demo-badge")
      }
      Spacer(minLength: 12)
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").font(.system(size: 17)).accessibilityHidden(true)
        TextField("想找哪一条？", text: $history.searchQuery)
          .textFieldStyle(.plain).font(.system(size: 16)).focused($searchFocused)
          .accessibilityLabel("搜索剪贴板历史").accessibilityIdentifier("pool-search")
        if !history.searchQuery.isEmpty {
          Button {
            history.searchQuery = ""
            searchFocused = true
          } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            .buttonStyle(.plain).accessibilityLabel("清除搜索")
        }
      }
      .padding(.horizontal, 14).frame(width: min(270, width * 0.31), height: 38)
      .background(.white.opacity(0.28), in: Capsule())
      .overlay { Capsule().strokeBorder(.white.opacity(0.70), lineWidth: 1) }
      Menu {
        Button("设置…", systemImage: "gearshape") { appState.openPreferences() }
        Button("关于浮拾", systemImage: "info.circle") { appState.openAbout() }
        Divider()
        Button("退出浮拾", systemImage: "power") { appState.quit() }
      } label: {
        Image(systemName: "slider.horizontal.3").font(.system(size: 17)).frame(width: 42, height: 38)
          .background(.white.opacity(0.24), in: Capsule())
          .overlay { Capsule().strokeBorder(.white.opacity(0.64), lineWidth: 1) }
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .accessibilityLabel("浮拾菜单")
    }
  }

  private var deck: some View {
    GeometryReader { geometry in
      if visibleItems.isEmpty {
        VStack(spacing: 14) {
          Image(systemName: appState.history.searchQuery.isEmpty ? "square.on.square.dashed" : "magnifyingglass")
            .font(.system(size: 37, weight: .light)).foregroundStyle(ink.opacity(0.45))
          Text(appState.history.searchQuery.isEmpty ? "复制一点灵感，让它落在这里。"
               : (favorites.isEmpty ? "没有找到这一条" : "在常用里找到 \(favorites.count) 条"))
            .font(.system(size: 18, weight: .medium))
          Text(appState.history.searchQuery.isEmpty ? "文字、图片、链接和文件，都可以留在池里。"
               : (favorites.isEmpty ? "换个关键词，或清除搜索再看看。" : "右侧可直接复制或拖出使用。"))
            .font(.system(size: 13)).foregroundStyle(ink.opacity(0.58))
        }
        .multilineTextAlignment(.center).padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
      } else {
        let slots = PoolLayout.slots(in: geometry.size, count: visibleItems.count)
        ZStack(alignment: .topLeading) {
          ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
            if index < slots.count {
              let slot = slots[index]
              let selected = appState.navigator.leadSelection == item.id
              if selected {
                Ellipse().fill(.cyan.opacity(0.14))
                  .overlay { Ellipse().stroke(.cyan.opacity(0.22), lineWidth: 1) }
                  .frame(width: slot.frame.width * 1.06, height: min(38, slot.frame.height * 0.24))
                  .blur(radius: 2)
                  .position(x: slot.frame.midX, y: min(geometry.size.height - 18, slot.frame.maxY + 10))
                  .allowsHitTesting(false)
              }
              object(item)
                .frame(width: slot.frame.width, height: slot.frame.height)
                .rotationEffect(.degrees(slot.rotation))
                .position(x: slot.frame.midX, y: slot.frame.midY)
                .zIndex(selected ? 10 : Double(index))
                .accessibilitySortPriority(Double(PoolLayout.pageSize - index))
                .accessibilityIdentifier("pool-recent-\(index)")
            }
          }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
      }
    }
    .background {
      PoolScrollCapture(enabled: previewItem == nil && activeDragID == nil) { delta in
        changePage(currentPage + (delta > 0 ? 1 : -1))
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("pool-recent-items")
  }

  private var favoriteRail: some View {
    VStack(spacing: 12) {
      Text("常用").font(.system(size: 16, weight: .medium)).tracking(2)
        .padding(.top, 20).accessibilityAddTraits(.isHeader)
      ScrollView {
        LazyVStack(spacing: 11) {
          ForEach(favorites) { item in
            object(item, compact: true).frame(height: 68)
              .accessibilityIdentifier("pool-favorite-\(item.id.uuidString)")
          }
          RoundedRectangle(cornerRadius: 21)
            .fill(.white.opacity(favoriteTargeted ? 0.30 : 0.08))
            .overlay {
              RoundedRectangle(cornerRadius: 21).strokeBorder(
                .white.opacity(favoriteTargeted ? 0.95 : 0.50), lineWidth: 1.5
              )
              VStack(spacing: 4) {
                Image(systemName: "pin").font(.system(size: 16, weight: .light))
                if favoriteTargeted || favorites.isEmpty {
                  Text("拖到这里").font(.system(size: 10))
                }
              }.foregroundStyle(ink.opacity(favoriteTargeted ? 0.85 : 0.40))
            }
            .frame(height: 66).accessibilityLabel("将剪贴板条目拖到这里放入常用")
            .accessibilityIdentifier("pool-favorite-drop")
          if favorites.isEmpty {
            RoundedRectangle(cornerRadius: 21).strokeBorder(.white.opacity(0.36), lineWidth: 1.3)
              .frame(height: 66).accessibilityHidden(true)
          }
        }.padding(.horizontal, 3).padding(.vertical, 4)
      }
      .scrollIndicators(.hidden)
    }
    .onDrop(of: PoolDrag.dropTypes, isTargeted: $favoriteTargeted, perform: acceptFavorite)
    .accessibilityIdentifier("pool-favorites")
  }

  private func object(_ item: HistoryItemDecorator, compact: Bool = false) -> some View {
    PoolItemView(item: item, compact: compact, isSelected: appState.navigator.leadSelection == item.id,
                 dragEnabled: previewItem == nil && !appState.isEditingItem
                   && (activeDragID == nil || activeDragID == item.id),
                 select: { select(item) }, copy: { copy(item) }, copyOnly: { copy(item, only: true) },
                 preview: { showPreview(item) },
                 togglePin: { togglePin(item) }, delete: { delete(item) },
                 dragStarted: { startDrag(item) }, dragEnded: { finishDrag(item) })
  }

  private var footer: some View {
    HStack(spacing: 12) {
      Spacer(minLength: 0)
      Text("滚动翻找 · 空格放大").font(.system(size: 13)).foregroundStyle(ink.opacity(0.72))
      if pages > 1 {
        HStack(spacing: 7) {
          Button { changePage(currentPage - 1) } label: { Image(systemName: "chevron.left") }
            .disabled(currentPage == 0).accessibilityLabel("较新的记录")
            .accessibilityIdentifier("pool-page-previous")
          Text("\(currentPage + 1) / \(pages)").monospacedDigit().font(.system(size: 12))
            .accessibilityLabel("第 \(currentPage + 1) 页，共 \(pages) 页")
          Button { changePage(currentPage + 1) } label: { Image(systemName: "chevron.right") }
            .disabled(currentPage + 1 >= pages).accessibilityLabel("较早的记录")
            .accessibilityIdentifier("pool-page-next")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.white.opacity(0.19), in: Capsule())
      }
      Spacer(minLength: 0)
    }.frame(height: 26)
  }

  private func select(_ item: HistoryItemDecorator) {
    appState.navigator.selectWithoutScrolling(item: item)
  }

  private func copy(_ item: HistoryItemDecorator, only: Bool = false) {
    select(item)
    PoolPasteCoordinator.shared.activate(item, copyOnly: only)
  }

  private func togglePin(_ item: HistoryItemDecorator) {
    // Avoid assigning an empty shortcut when all supported pins are in use.
    guard item.isPinned || !appState.history.availablePins.isEmpty else { return }
    appState.history.togglePin(item)
    page = currentPage
    reconcileSelection()
  }

  private func delete(_ item: HistoryItemDecorator) {
    if previewItem?.id == item.id { previewItem = nil }
    appState.history.delete(item)
    page = currentPage
    reconcileSelection()
  }

  private func reconcileSelection() {
    let items = keyboardItems
    if !items.contains(where: { $0.id == appState.navigator.leadSelection }) {
      appState.navigator.selectWithoutScrolling(item: items.first)
    }
  }

  private func changePage(_ requested: Int) {
    let next = PoolLayout.clampedPage(requested, total: recent.count)
    guard next != currentPage else { return }
    page = next
    previewItem = nil
    selectFirstVisible()
  }

  private func selectFirstVisible() {
    appState.navigator.isKeyboardNavigating = true
    appState.navigator.selectWithoutScrolling(item: visibleItems.first ?? favorites.first)
  }

  private func moveSelection(_ offset: Int) {
    let wasPreviewing = previewItem != nil
    defer {
      if wasPreviewing, let item = appState.navigator.leadHistoryItem { showPreview(item) }
    }
    let items = keyboardItems
    guard !items.isEmpty else { return }
    let current = items.firstIndex(where: { $0.id == appState.navigator.leadSelection }) ?? (offset > 0 ? -1 : 1)
    let next = current + offset
    appState.navigator.isKeyboardNavigating = true
    if next < 0, currentPage > 0 {
      changePage(currentPage - 1)
      if let last = visibleItems.last { select(last) }
    } else if next >= visibleItems.count, current < visibleItems.count, currentPage + 1 < pages {
      changePage(currentPage + 1)
    } else {
      select(items[min(max(0, next), items.count - 1)])
    }
  }

  private func startDrag(_ item: HistoryItemDecorator) {
    activeDragID = item.id
    previewItem = nil
    select(item)
    appState.navigator.isDragAndDropInProgress = true
  }

  private func finishDrag(_ item: HistoryItemDecorator) {
    guard activeDragID == item.id else { return }
    endDrag()
  }

  private func endDrag() {
    activeDragID = nil
    favoriteTargeted = false
    appState.navigator.isDragAndDropInProgress = false
  }

  private func acceptFavorite(_ providers: [NSItemProvider]) -> Bool {
    guard let expected = activeDragID,
          let item = appState.history.items.first(where: { $0.id == expected }), item.isUnpinned,
          !appState.history.availablePins.isEmpty else { return false }
    if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(PoolDrag.itemType.identifier) }) {
      provider.loadDataRepresentation(forTypeIdentifier: PoolDrag.itemType.identifier) { data, _ in
        guard let data, let string = String(data: data, encoding: .utf8), UUID(uuidString: string) == expected else { return }
        Task { @MainActor in
          if let current = appState.history.items.first(where: { $0.id == expected }), current.isUnpinned {
            togglePin(current)
          }
        }
      }
    } else {
      // Compatibility NSDraggingSource keeps its UUID solely in this process.
      // Its pasteboard contains actual export data, never an externally visible item identifier.
      togglePin(item)
    }
    return true
  }

  private func showPreview(_ item: HistoryItemDecorator) {
    searchFocused = false
    select(item)
    item.ensurePreviewImage()
    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { previewItem = item }
  }

  private func handleKey(_ event: NSEvent) -> Bool {
    guard !appState.isEditingItem, activeDragID == nil else { return false }
    if let input = NSApp.keyWindow?.firstResponder as? NSTextInputClient, input.hasMarkedText() { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
    if PoolInputPolicy.defersToTextEditor(
      keyCode: event.keyCode, commandPressed: flags.contains(.command),
      optionPressed: flags.contains(.option), shiftPressed: flags.contains(.shift),
      previewOpen: previewItem != nil, textEditorFocused: NSApp.keyWindow?.firstResponder is NSTextView
    ) { return false }
    if flags.contains(.command) {
      switch event.keyCode {
      case 3: previewItem = nil; searchFocused = true; return true // F; key codes also work with a non-Latin input source.
      case 8:
        if let item = appState.navigator.leadHistoryItem { copy(item, only: true) }
        return true
      case 43: appState.openPreferences(); return true
      case 51:
        if let item = appState.navigator.leadHistoryItem { delete(item) }
        return true
      default: return false
      }
    }
    switch event.keyCode {
    case 53:
      if previewItem != nil { previewItem = nil }
      else if !appState.history.searchQuery.isEmpty { appState.history.searchQuery = "" }
      else { appState.popup.close() }
      return true
    case 36, 76:
      if let item = previewItem ?? appState.navigator.leadHistoryItem { copy(item) }
      return true
    case 49:
      guard !searchFocused || appState.history.searchQuery.isEmpty || previewItem != nil else { return false }
      if previewItem != nil { previewItem = nil }
      else if let item = appState.navigator.leadHistoryItem { showPreview(item) }
      return true
    case 48:
      if searchFocused {
        searchFocused = false
        if flags.contains(.shift), let last = favorites.last { select(last) }
        else { selectFirstVisible() }
      } else if let selected = appState.navigator.leadSelection,
                visibleItems.contains(where: { $0.id == selected }), let first = favorites.first {
        select(first)
      } else {
        searchFocused = true
      }
      return true
    case 125, 126:
      moveSelection(event.keyCode == 125 ? 1 : -1)
      return true
    case 123, 124:
      if flags.contains(.option) { changePage(currentPage + (event.keyCode == 124 ? 1 : -1)); return true }
      guard !searchFocused || appState.history.searchQuery.isEmpty else { return false }
      moveSelection(event.keyCode == 124 ? 1 : -1)
      return true
    case 116, 121:
      changePage(currentPage + (event.keyCode == 121 ? 1 : -1))
      return true
    default: return false
    }
  }

  private func preview(_ item: HistoryItemDecorator, in size: CGSize) -> some View {
    ZStack {
      PoolBasinShape().fill(.black.opacity(0.12)).onTapGesture { previewItem = nil }
      VStack(spacing: 0) {
        HStack {
          Image(nsImage: item.applicationImage.nsImage).resizable().scaledToFit().frame(width: 23, height: 23)
          Text(item.application ?? "剪贴板预览").font(.system(size: 14, weight: .medium))
          Spacer()
          Button { previewItem = nil } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 19)) }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("关闭预览")
            .accessibilityIdentifier("pool-preview-close")
        }.padding(18)
        Divider().opacity(0.3)
        Group {
          if item.hasImage, let image = item.previewImage ?? item.item.image {
            Image(nsImage: image).resizable().scaledToFit().padding(20)
              .accessibilityLabel("剪贴板图片预览")
          } else {
            ScrollView {
              Text(String(item.item.previewableText.prefix(50_000)))
                .font(.system(size: 18, design: isCode(item) ? .monospaced : .default))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        Divider().opacity(0.3)
        HStack {
          Text(item.item.previewableText.count > 50_000 && !item.hasImage ? "预览前 50,000 字符 · 复制保留全文" : "空格或 Esc 收起")
            .font(.system(size: 11)).foregroundStyle(.secondary)
          Spacer()
          Button(autoPaste ? "粘贴" : "复制", systemImage: autoPaste ? "doc.on.clipboard" : "doc.on.doc") { copy(item) }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("pool-preview-copy")
        }.padding(16)
      }
      .frame(width: min(650, max(260, size.width - 130)), height: min(460, max(200, size.height - 130)))
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
      .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.8), lineWidth: 1) }
      .shadow(color: .black.opacity(0.22), radius: 30, y: 16)
      .accessibilityElement(children: .contain).accessibilityLabel("放大预览")
      .accessibilityIdentifier("pool-preview")
    }
  }

  private func isCode(_ item: HistoryItemDecorator) -> Bool {
    if case .code = PoolItemKind.kind(for: item) { return true }
    return false
  }
}

struct PoolBasinShape: Shape {
  func path(in rect: CGRect) -> Path {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
    var path = Path()
    path.move(to: point(0.005, 0.47))
    path.addCurve(to: point(0.14, 0.035), control1: point(0.005, 0.23), control2: point(0.07, 0.025))
    path.addCurve(to: point(0.44, 0.045), control1: point(0.24, 0.002), control2: point(0.34, 0.068))
    path.addCurve(to: point(0.76, 0.018), control1: point(0.55, 0.067), control2: point(0.64, 0.002))
    path.addCurve(to: point(0.99, 0.41), control1: point(0.91, 0.01), control2: point(0.985, 0.15))
    path.addCurve(to: point(0.85, 0.91), control1: point(1.01, 0.68), control2: point(0.96, 0.84))
    path.addCurve(to: point(0.50, 0.988), control1: point(0.74, 0.999), control2: point(0.65, 0.98))
    path.addCurve(to: point(0.19, 0.95), control1: point(0.35, 0.995), control2: point(0.25, 0.999))
    path.addCurve(to: point(0.005, 0.47), control1: point(0.04, 0.88), control2: point(0.002, 0.67))
    path.closeSubpath()
    return path
  }
}

private struct PoolInputCapture: NSViewRepresentable {
  let keyDown: (NSEvent) -> Bool
  func makeNSView(context: Context) -> PoolInputView {
    let view = PoolInputView()
    view.keyDownHandler = keyDown
    return view
  }
  func updateNSView(_ view: PoolInputView, context: Context) { view.keyDownHandler = keyDown }
  static func dismantleNSView(_ view: PoolInputView, coordinator: ()) { view.removeMonitor() }
}

private final class PoolInputView: NSView {
  var keyDownHandler: ((NSEvent) -> Bool)?
  nonisolated(unsafe) private var monitor: Any?
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    removeMonitor()
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window == self.window, self.window?.isKeyWindow == true else { return event }
      return self.keyDownHandler?(event) == true ? nil : event
    }
  }
  func removeMonitor() {
    if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
  }
  deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

private struct PoolScrollCapture: NSViewRepresentable {
  let enabled: Bool
  let scroll: (CGFloat) -> Void
  func makeNSView(context: Context) -> PoolScrollView {
    let view = PoolScrollView()
    view.enabled = enabled
    view.scroll = scroll
    return view
  }
  func updateNSView(_ view: PoolScrollView, context: Context) {
    view.enabled = enabled
    view.scroll = scroll
  }
  static func dismantleNSView(_ view: PoolScrollView, coordinator: ()) { view.removeMonitor() }
}

private final class PoolScrollView: NSView {
  var enabled = true
  var scroll: ((CGFloat) -> Void)?
  nonisolated(unsafe) private var monitor: Any?
  private var lastPageTime: TimeInterval = 0
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    removeMonitor()
    guard window != nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, self.enabled, event.window == self.window,
            self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
      let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
      let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 2 : 0
      if abs(delta) > threshold, event.timestamp - self.lastPageTime > 0.28,
         event.momentumPhase.isEmpty {
        self.lastPageTime = event.timestamp
        self.scroll?(delta)
        return nil
      }
      return event
    }
  }
  func removeMonitor() {
    if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
  }
  deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
