import Cocoa
import FlutterMacOS

/// macOS 菜单栏托盘悬停浮层，交互对齐 Windows `tray_peek.cpp` / 企业微信。
final class TrayPeekController {
  static let shared = TrayPeekController()

  private var channel: FlutterMethodChannel?
  private var panel: NSPanel?
  private var peekView: TrayPeekView?
  private var hideTimer: Timer?
  private var items: [TrayPeekItem] = []
  private var titleText = "沙丘"
  private var total = 0
  private var flashing = false
  private var globalMouseMonitor: Any?
  private var localMouseMonitor: Any?
  private var overIcon = false
  private var suppressHoverUntilExit = false

  func setup(with messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "nova.dunes/tray_peek",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "update":
        self.update(call.arguments)
        result(nil)
      case "show":
        if !self.suppressHoverUntilExit { self.show() }
        result(nil)
      case "hide":
        self.suppressHoverUntilExit = true
        self.hide(force: true)
        result(nil)
      case "scheduleHide":
        self.scheduleHide()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = methodChannel
    startMouseMonitors()
  }

  func shutdown() {
    stopMouseMonitors()
    hide(force: true)
    panel?.close()
    panel = nil
    peekView = nil
    channel = nil
  }

  private func update(_ arguments: Any?) {
    items = []
    total = 0
    flashing = false
    if let list = arguments as? [[String: Any]] {
      items = list.compactMap { TrayPeekItem(map: $0) }
      total = items.count
    } else if let map = arguments as? [String: Any] {
      if let title = map["title"] as? String, !title.isEmpty {
        titleText = title
      }
      total = intValue(map["total"])
      flashing = intValue(map["flashing"]) != 0 || (map["flashing"] as? Bool) == true
      if let list = map["items"] as? [[String: Any]] {
        items = list.compactMap { TrayPeekItem(map: $0) }
      }
    }
    if total < items.count {
      total = items.count
    }
    peekView?.reload(title: titleText, total: total, flashing: flashing, items: items)
    if items.isEmpty {
      hide(force: true)
      return
    }
    if !suppressHoverUntilExit && (panel?.isVisible == true || shouldKeepPeek()) {
      show()
    }
  }

  private func startMouseMonitors() {
    if globalMouseMonitor == nil {
      globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
        self?.handleMouseMove()
      }
    }
    if localMouseMonitor == nil {
      localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
        self?.handleMouseMove()
        return event
      }
    }
  }

  private func stopMouseMonitors() {
    if let globalMouseMonitor {
      NSEvent.removeMonitor(globalMouseMonitor)
    }
    if let localMouseMonitor {
      NSEvent.removeMonitor(localMouseMonitor)
    }
    globalMouseMonitor = nil
    localMouseMonitor = nil
  }

  private func handleMouseMove() {
    let mouse = NSEvent.mouseLocation
    guard let iconFrame = statusItemFrame() else { return }
    let over = iconFrame.insetBy(dx: -4, dy: -4).contains(mouse)
    let overPanel = panel?.isVisible == true && (panel?.frame.insetBy(dx: -4, dy: -4).contains(mouse) ?? false)
    if suppressHoverUntilExit {
      if over { return }
      suppressHoverUntilExit = false
      overIcon = false
    }
    if over || overPanel {
      hideTimer?.invalidate()
      hideTimer = nil
    }
    if over, !items.isEmpty {
      if !overIcon {
        overIcon = true
        show()
      }
    } else if !over, !overPanel {
      if overIcon || panel?.isVisible == true {
        overIcon = false
        scheduleHide()
      }
    }
  }

  private func show() {
    guard !items.isEmpty else {
      hide(force: true)
      return
    }
    hideTimer?.invalidate()
    hideTimer = nil
    ensurePanel()
    peekView?.reload(title: titleText, total: total, flashing: flashing, items: items)
    placePanel()
    panel?.orderFrontRegardless()
  }

  private func hide(force: Bool) {
    if !force, shouldKeepPeek() {
      scheduleHide()
      return
    }
    hideTimer?.invalidate()
    hideTimer = nil
    panel?.orderOut(nil)
    peekView?.clearHot()
  }

  private func scheduleHide() {
    // Mouse-move events outside the panel must not keep postponing dismissal.
    guard hideTimer == nil else { return }
    hideTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
      guard let self else { return }
      self.hideTimer = nil
      self.hide(force: false)
    }
  }

  private func shouldKeepPeek() -> Bool {
    let mouse = NSEvent.mouseLocation
    if let frame = panel?.frame, panel?.isVisible == true {
      if frame.insetBy(dx: -4, dy: -4).contains(mouse) {
        return true
      }
    }
    // A cursor-based fallback anchor always contains the cursor and would
    // otherwise keep the popup open forever when the status item disappears.
    return statusItemFrame()?.insetBy(dx: -10, dy: -10).contains(mouse) ?? false
  }

  private func ensurePanel() {
    if panel != nil { return }
    let view = TrayPeekView()
    view.onHover = { [weak self] inside in
      guard let self else { return }
      if inside {
        self.hideTimer?.invalidate()
        self.hideTimer = nil
      } else {
        self.scheduleHide()
      }
    }
    view.onOpen = { [weak self] id in
      self?.suppressHoverUntilExit = true
      self?.hide(force: true)
      self?.channel?.invokeMethod("open", arguments: id)
    }
    view.onCancelFlash = { [weak self] in
      guard let self else { return }
      self.flashing = false
      self.peekView?.reload(
        title: self.titleText,
        total: self.total,
        flashing: false,
        items: self.items
      )
      self.placePanel()
      self.channel?.invokeMethod("cancelFlash", arguments: nil)
    }
    peekView = view

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: TrayPeekView.cardWidth, height: 80),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .popUpMenu
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.acceptsMouseMovedEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.contentView = view
    self.panel = panel
  }

  private func placePanel() {
    guard let panel, let peekView else { return }
    let size = peekView.preferredSize
    peekView.frame = NSRect(origin: .zero, size: size)
    let anchor = anchorRect()
    var x = anchor.midX - size.width / 2
    var y = anchor.minY - size.height - 6
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) })
      ?? NSScreen.main
    {
      let visible = screen.visibleFrame
      x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
      if y < visible.minY + 8 {
        y = anchor.maxY + 6
      }
      y = min(max(y, visible.minY + 8), max(visible.minY + 8, visible.maxY - size.height - 8))
    }
    panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
  }

  private func anchorRect() -> NSRect {
    if let frame = statusItemFrame() {
      return frame
    }
    let mouse = NSEvent.mouseLocation
    return NSRect(x: mouse.x - 11, y: mouse.y - 11, width: 22, height: 22)
  }

  private func statusItemFrame() -> NSRect? {
    let mouse = NSEvent.mouseLocation
    var fallback: NSRect?
    for window in NSApp.windows {
      let isStatus = window.className.contains("StatusBar") || window.level == .statusBar
      guard isStatus else { continue }
      fallback = window.frame
      if window.frame.contains(mouse) {
        return window.frame
      }
    }
    return fallback
  }

  private func intValue(_ raw: Any?) -> Int {
    if let n = raw as? Int { return n }
    if let n = raw as? NSNumber { return n.intValue }
    return 0
  }
}

struct TrayPeekItem {
  let id: Int
  let title: String
  let preview: String
  let unread: Int
  let initial: String
  let color: NSColor
  let avatar: NSImage?

  init?(map: [String: Any]) {
    let id: Int
    if let n = map["id"] as? Int {
      id = n
    } else if let n = map["id"] as? NSNumber {
      id = n.intValue
    } else {
      return nil
    }
    self.id = id
    title = (map["title"] as? String) ?? "会话"
    preview = (map["preview"] as? String) ?? ""
    if let n = map["unread"] as? Int {
      unread = max(n, 1)
    } else if let n = map["unread"] as? NSNumber {
      unread = max(n.intValue, 1)
    } else {
      unread = 1
    }
    let rawInitial = (map["initial"] as? String) ?? "?"
    initial = rawInitial.isEmpty ? "?" : String(rawInitial.prefix(1))
    let argb: Int
    if let n = map["color"] as? Int {
      argb = n
    } else if let n = map["color"] as? NSNumber {
      argb = n.intValue
    } else {
      argb = 0xFF7B_5CD8
    }
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    if let typed = map["avatarPng"] as? FlutterStandardTypedData {
      avatar = NSImage(data: typed.data)
    } else if let data = map["avatarPng"] as? Data {
      avatar = NSImage(data: data)
    } else {
      avatar = nil
    }
  }
}

final class TrayPeekView: NSView {
  static let cardWidth: CGFloat = 288
  static let pad: CGFloat = 12
  static let headerH: CGFloat = 38
  static let rowH: CGFloat = 52
  static let footerH: CGFloat = 32
  static let avatar: CGFloat = 32
  static let maxRows = 6

  var onHover: ((Bool) -> Void)?
  var onOpen: ((Int) -> Void)?
  var onCancelFlash: (() -> Void)?

  private var titleText = "沙丘"
  private var total = 0
  private var flashing = false
  private var items: [TrayPeekItem] = []
  private var hot = -1
  private var pressedTarget = -1
  private var tracking: NSTrackingArea?

  var preferredSize: NSSize {
    let rows = min(items.count, Self.maxRows)
    let height = Self.headerH + CGFloat(max(rows, 0)) * Self.rowH
      + Self.footerH
    return NSSize(width: Self.cardWidth, height: max(height, 40))
  }

  override var isFlipped: Bool { true }

  func reload(title: String, total: Int, flashing: Bool, items: [TrayPeekItem]) {
    titleText = title
    self.total = total
    self.flashing = flashing
    self.items = Array(items.prefix(Self.maxRows))
    pressedTarget = -1
    hot = -1
    needsDisplay = true
  }

  func clearHot() {
    hot = -1
    pressedTarget = -1
    needsDisplay = true
  }

  override func updateTrackingAreas() {
    if let tracking {
      removeTrackingArea(tracking)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    tracking = area
    super.updateTrackingAreas()
  }

  override func mouseEntered(with event: NSEvent) {
    onHover?(true)
    updateHot(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseExited(with event: NSEvent) {
    hot = -1
    NSCursor.arrow.set()
    needsDisplay = true
    onHover?(false)
  }

  override func mouseMoved(with event: NSEvent) {
    updateHot(at: convert(event.locationInWindow, from: nil))
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    pressedTarget = target(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseDragged(with event: NSEvent) {
    updateHot(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseUp(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let selected = target(at: point)
    let pressed = pressedTarget
    pressedTarget = -1
    guard selected != -1, selected == pressed else { return }
    if selected == -2 {
      onCancelFlash?()
      return
    }
    let row = selected
    if row >= 0, row < items.count {
      onOpen?(items[row].id)
    }
  }

  private func updateHot(at point: NSPoint) {
    let next = target(at: point)
    if next == -1 { NSCursor.arrow.set() } else { NSCursor.pointingHand.set() }
    if next != hot {
      hot = next
      needsDisplay = true
    }
  }

  private func hitRow(_ point: NSPoint) -> Int {
    guard bounds.contains(point), point.y >= Self.headerH else { return -1 }
    let idx = Int((point.y - Self.headerH) / Self.rowH)
    if idx < 0 || idx >= items.count { return -1 }
    return idx
  }

  private func hitFooter(_ point: NSPoint) -> Bool {
    guard flashing else { return false }
    return bounds.contains(point) && point.y >= bounds.height - Self.footerH
      && point.x >= bounds.width - Self.pad - 65
  }

  private func target(at point: NSPoint) -> Int {
    return hitFooter(point) ? -2 : hitRow(point)
  }

  override func draw(_ dirtyRect: NSRect) {
    let card = bounds.insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    path.addClip()
    NSColor.windowBackgroundColor.setFill()
    path.fill()
    drawText("\(titleText) · 未读消息",
      in: NSRect(x: Self.pad, y: 0, width: bounds.width - Self.pad * 2 - 64, height: Self.headerH),
      font: .systemFont(ofSize: 12, weight: .semibold), color: .systemPurple, align: .left)
    drawText("\(max(total, items.count)) 条",
      in: NSRect(x: bounds.width - Self.pad - 64, y: 0, width: 64, height: Self.headerH),
      font: .systemFont(ofSize: 11), color: .secondaryLabelColor, align: .right)

    for (i, item) in items.enumerated() {
      let rowY = Self.headerH + CGFloat(i) * Self.rowH
      let row = NSRect(x: 0, y: rowY, width: bounds.width, height: Self.rowH)
      if i == hot {
        NSColor.systemPurple.withAlphaComponent(0.08).setFill()
        NSBezierPath(rect: row).fill()
      }
      let av = Self.avatar
      let ax = Self.pad
      let ay = row.midY - av / 2
      let avatarRect = NSRect(x: ax, y: ay, width: av, height: av)
      let corner = max(2, av * 0.18)
      if let avatar = item.avatar {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: avatarRect, xRadius: corner, yRadius: corner).addClip()
        avatar.draw(in: avatarRect)
        NSGraphicsContext.restoreGraphicsState()
      } else {
        item.color.setFill()
        NSBezierPath(roundedRect: avatarRect, xRadius: corner, yRadius: corner).fill()
        drawText(item.initial, in: avatarRect, font: .systemFont(ofSize: 12, weight: .semibold), color: .white, align: .center)
      }
      let badge = item.unread > 99 ? "99+" : "\(item.unread)"
      let badgeWidth = max(18, (badge as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width + 10)
      let textLeft = ax + av + 8
      let textRight = bounds.width - Self.pad - badgeWidth - 10
      drawText(item.title,
        in: NSRect(x: textLeft, y: rowY + 7, width: textRight - textLeft, height: 19),
        font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor, align: .left)
      drawPreview(item.preview.isEmpty ? "有未读消息" : item.preview,
        in: NSRect(x: textLeft, y: rowY + 27, width: textRight - textLeft, height: 19))
      let badgeRect = NSRect(x: bounds.width - Self.pad - badgeWidth, y: row.midY - 9, width: badgeWidth, height: 18)
      NSColor.systemRed.setFill()
      NSBezierPath(roundedRect: badgeRect, xRadius: 9, yRadius: 9).fill()
      drawText(badge, in: badgeRect, font: .systemFont(ofSize: 11), color: .white, align: .center)
    }
    let footer = NSRect(x: 0, y: bounds.height - Self.footerH, width: bounds.width, height: Self.footerH)
    NSColor.controlBackgroundColor.setFill()
    NSBezierPath(rect: footer).fill()
    if hot == -2 {
      NSColor.systemPurple.withAlphaComponent(0.08).setFill()
      NSBezierPath(rect: footer).fill()
    }
    drawText("点击会话查看消息",
      in: NSRect(x: Self.pad, y: footer.minY, width: bounds.width - Self.pad * 2 - (flashing ? 65 : 0), height: Self.footerH),
      font: .systemFont(ofSize: 11), color: .secondaryLabelColor, align: .left)
    if flashing {
      drawText("停止闪烁",
        in: NSRect(x: bounds.width - Self.pad - 65, y: footer.minY, width: 65, height: Self.footerH),
        font: .systemFont(ofSize: 11), color: .systemPurple, align: .right)
    }
    NSColor.separatorColor.setStroke()
    path.lineWidth = 1
    path.stroke()
  }

  private func drawPreview(_ text: String, in rect: NSRect) {
    var mention = 0
    if text.hasPrefix("[@"), let close = text.firstIndex(of: "]") {
      mention = text.distance(from: text.startIndex, to: close) + 1
    } else if text.hasPrefix("@"), let space = text.firstIndex(of: " ") {
      mention = text.distance(from: text.startIndex, to: space)
    } else if text.hasPrefix("@") {
      mention = text.count
    }
    let gray = NSColor.secondaryLabelColor
    if mention <= 0 {
      drawText(text, in: rect, font: .systemFont(ofSize: 11), color: gray, align: .left)
      return
    }
    let mentionText = String(text.prefix(mention))
    let rest = String(text.dropFirst(mention))
    let mentionAttr: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11),
      .foregroundColor: NSColor(srgbRed: 250 / 255, green: 81 / 255, blue: 81 / 255, alpha: 1),
    ]
    let mentionSize = (mentionText as NSString).size(withAttributes: mentionAttr)
    let mentionRect = NSRect(
      x: rect.minX,
      y: rect.minY,
      width: min(mentionSize.width, rect.width),
      height: rect.height
    )
    drawText(
      mentionText,
      in: mentionRect,
      font: .systemFont(ofSize: 11),
      color: NSColor(srgbRed: 250 / 255, green: 81 / 255, blue: 81 / 255, alpha: 1),
      align: .left
    )
    if mentionRect.maxX < rect.maxX, !rest.isEmpty {
      drawText(
        rest,
        in: NSRect(
          x: mentionRect.maxX,
          y: rect.minY,
          width: rect.maxX - mentionRect.maxX,
          height: rect.height
        ),
        font: .systemFont(ofSize: 11),
        color: gray,
        align: .left
      )
    }
  }

  private func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    align: NSTextAlignment
  ) {
    let para = NSMutableParagraphStyle()
    para.alignment = align
    para.lineBreakMode = .byTruncatingTail
    let attr: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: para,
    ]
    let size = (text as NSString).size(withAttributes: attr)
    var drawRect = rect
    drawRect.origin.y += (rect.height - size.height) / 2
    drawRect.size.height = size.height
    (text as NSString).draw(in: drawRect, withAttributes: attr)
  }
}
