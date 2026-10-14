import Cocoa
import FlutterMacOS
import XCTest
@testable import dunes_app

class RunnerTests: XCTestCase {

  private func makeView(count: Int = 2, flashing: Bool = true) -> (TrayPeekView, NSPanel) {
    let view = TrayPeekView()
    let items = (0..<count).compactMap { index in
      TrayPeekItem(map: ["id": index + 1, "title": "会话 \(index + 1)", "unread": 3])
    }
    view.reload(title: "沙丘", total: count * 3, flashing: flashing, items: items)
    let panel = NSPanel(contentRect: NSRect(origin: .zero, size: view.preferredSize),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.contentView = view
    view.frame = NSRect(origin: .zero, size: view.preferredSize)
    return (view, panel)
  }

  private func event(_ type: NSEvent.EventType, at point: NSPoint, in view: NSView) -> NSEvent {
    return NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
      modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0,
      context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
  }

  private func click(_ point: NSPoint, in view: TrayPeekView) {
    view.mouseDown(with: event(.leftMouseDown, at: point, in: view))
    view.mouseUp(with: event(.leftMouseUp, at: point, in: view))
  }

  func testHeaderAndOutsideClicksDoNotOpenTheFirstConversation() {
    let (view, panel) = makeView()
    defer { panel.close() }
    var opened: Int?
    view.onOpen = { opened = $0 }
    for point in [NSPoint(x: 40, y: 0), NSPoint(x: 40, y: TrayPeekView.headerH - 1),
      NSPoint(x: -1, y: 50), NSPoint(x: view.bounds.width + 1, y: 50)] {
      click(point, in: view)
      XCTAssertNil(opened)
    }
    click(NSPoint(x: 40, y: TrayPeekView.headerH + 20), in: view)
    XCTAssertEqual(opened, 1)
  }

  func testMouseReleaseRequiresTheSamePressedRow() {
    let (view, panel) = makeView()
    defer { panel.close() }
    var opened: Int?
    view.onOpen = { opened = $0 }
    let first = NSPoint(x: 40, y: TrayPeekView.headerH + 20)
    let second = NSPoint(x: 40, y: first.y + TrayPeekView.rowH)
    view.mouseUp(with: event(.leftMouseUp, at: first, in: view))
    XCTAssertNil(opened)
    view.mouseDown(with: event(.leftMouseDown, at: first, in: view))
    view.mouseDragged(with: event(.leftMouseDragged, at: second, in: view))
    view.mouseUp(with: event(.leftMouseUp, at: second, in: view))
    XCTAssertNil(opened)
    click(second, in: view)
    XCTAssertEqual(opened, 2)
  }

  func testOnlyFooterLinkStopsFlashingAndFooterHeightIsStable() {
    let (view, panel) = makeView()
    defer { panel.close() }
    var cancelled = 0
    view.onCancelFlash = { cancelled += 1 }
    click(NSPoint(x: 20, y: view.bounds.height - 12), in: view)
    XCTAssertEqual(cancelled, 0)
    click(NSPoint(x: view.bounds.width - 20, y: view.bounds.height - 12), in: view)
    XCTAssertEqual(cancelled, 1)
    let previousSize = view.preferredSize
    view.reload(title: "沙丘", total: 3, flashing: false, items: [TrayPeekItem(map: ["id": 1])!, TrayPeekItem(map: ["id": 2])!])
    XCTAssertEqual(view.preferredSize, previousSize)
    click(NSPoint(x: view.bounds.width - 20, y: view.bounds.height - 12), in: view)
    XCTAssertEqual(cancelled, 1)
  }

  func testReloadCancelsPendingClicksAndInactivePanelAcceptsFirstClick() {
    let (view, panel) = makeView()
    defer { panel.close() }
    XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    var opened: Int?
    view.onOpen = { opened = $0 }
    let first = NSPoint(x: 40, y: TrayPeekView.headerH + 20)
    view.mouseDown(with: event(.leftMouseDown, at: first, in: view))
    view.reload(title: "沙丘", total: 1, flashing: false, items: [TrayPeekItem(map: ["id": 99])!])
    view.mouseUp(with: event(.leftMouseUp, at: first, in: view))
    XCTAssertNil(opened)
  }

  func testOnlySixConversationsAreDisplayed() {
    let (view, panel) = makeView(count: 10)
    defer { panel.close() }
    XCTAssertEqual(view.preferredSize.height, TrayPeekView.headerH + 6 * TrayPeekView.rowH + TrayPeekView.footerH)
  }

}
