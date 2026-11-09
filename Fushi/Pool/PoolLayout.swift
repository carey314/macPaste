import CoreGraphics
import Foundation

/// Fixed, non-overlapping resting places. Only the current six objects are materialized.
nonisolated struct PoolSlot: Equatable {
  let frame: CGRect
  let rotation: Double
}

nonisolated enum PoolLayout {
  static let pageSize = 6

  static func slots(in size: CGSize, count: Int) -> [PoolSlot] {
    guard size.width.isFinite, size.height.isFinite,
          size.width > 0, size.height > 0, count > 0 else { return [] }
    let count = min(count, pageSize)
    if count == 1 {
      return [PoolSlot(frame: CGRect(x: size.width * 0.14, y: size.height * 0.16,
                                    width: size.width * 0.64, height: size.height * 0.64), rotation: -4)]
    }
    if size.width < 660 || size.height < 300 {
      let gap = min(12, size.width * 0.035, size.height * 0.045)
      let rows = CGFloat((count + 1) / 2)
      let width = max(0.1, (size.width - gap * 3) / 2)
      let height = max(0.1, (size.height - gap * (rows + 1)) / rows)
      return (0..<count).map { index in
        PoolSlot(frame: CGRect(x: gap + CGFloat(index % 2) * (width + gap),
                               y: gap + CGFloat(index / 2) * (height + gap),
                               width: width, height: height), rotation: 0)
      }
    }
    let placements: [(CGFloat, CGFloat, CGFloat, CGFloat, Double)] = [
      (0.035, 0.07, 0.36, 0.43, -4),
      (0.445, 0.04, 0.285, 0.55, 4),
      (0.765, 0.30, 0.225, 0.43, 0),
      (0.06, 0.71, 0.34, 0.23, 7),
      (0.45, 0.70, 0.27, 0.28, -3),
      (0.785, 0.82, 0.195, 0.16, -3)
    ]
    return placements.prefix(count).map { x, y, width, height, rotation in
      PoolSlot(frame: CGRect(x: x * size.width, y: y * size.height,
                             width: width * size.width, height: height * size.height), rotation: rotation)
    }
  }

  static func pageCount(total: Int, pageSize: Int = pageSize) -> Int {
    guard total > 0 else { return 0 }
    let size = max(1, pageSize)
    return total / size + (total % size == 0 ? 0 : 1)
  }

  static func clampedPage(_ page: Int, total: Int, pageSize: Int = pageSize) -> Int {
    max(0, min(page, pageCount(total: total, pageSize: pageSize) - 1))
  }

  static func pageSlice<Item>(_ items: [Item], page: Int, pageSize: Int = pageSize) -> [Item] {
    guard !items.isEmpty else { return [] }
    let size = max(1, pageSize)
    let start = clampedPage(page, total: items.count, pageSize: size) * size
    return Array(items[start..<(start + min(size, items.count - start))])
  }
}
