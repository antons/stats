//
//  Kit.swift
//  Tests
//
//  Created by Serhiy Mytrovtsiy on 04/07/2026.
//  Using Swift 6.0.
//  Running on macOS 26.5.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import XCTest
import Cocoa
@testable import Kit

class KitTests: XCTestCase {
    func testIsNewestVersion_release() throws {
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.11.0"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.11.1"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.1", latestVersion: "v2.11.0"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.12.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.12.0", latestVersion: "v2.11.5"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v3.0.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v3.0.0", latestVersion: "v2.99.99"))
    }
    
    func testIsNewestVersion_beta() throws {
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.0-beta1"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0-beta2", latestVersion: "v2.11.0-beta1"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.0-beta2"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.10.9"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.11.1-beta1"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.1-beta1"))
    }
    
    func testIsNewestVersion_malformed() throws {
        XCTAssertFalse(isNewestVersion(currentVersion: "v3", latestVersion: "v3.0.0"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v3", latestVersion: "v3.0.1"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v3.0", latestVersion: "v3.0.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "", latestVersion: ""))
    }
    
    func testUnitsGetReadableSpeed_byte() throws {
        XCTAssertEqual(Units(bytes: 0).getReadableSpeed(base: .byte), "0 KB/s")
        XCTAssertEqual(Units(bytes: 999).getReadableSpeed(base: .byte), "0 KB/s")
        XCTAssertEqual(Units(bytes: 1_000).getReadableSpeed(base: .byte), "1 KB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte), "500 KB/s")
        XCTAssertEqual(Units(bytes: 2_500_000).getReadableSpeed(base: .byte), "2.5 MB/s")
        XCTAssertEqual(Units(bytes: 150_000_000).getReadableSpeed(base: .byte), "150 MB/s")
        XCTAssertEqual(Units(bytes: 2_000_000_000).getReadableSpeed(base: .byte), "2.0 GB/s")
        XCTAssertEqual(Units(bytes: 2_000_000_000_000).getReadableSpeed(base: .byte), "2.0 TB/s")
        XCTAssertEqual(Units(bytes: -5).getReadableSpeed(base: .byte), "0 KB/s")
    }
    
    func testUnitsGetReadableSpeed_bit() throws {
        XCTAssertEqual(Units(bytes: 100).getReadableSpeed(base: .bit), "0 Kb/s")
        XCTAssertEqual(Units(bytes: 50_000).getReadableSpeed(base: .bit), "400 Kb/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .bit), "4.0 Mb/s")
        XCTAssertEqual(Units(bytes: 200_000_000).getReadableSpeed(base: .bit), "1.6 Gb/s")
        XCTAssertEqual(Units(bytes: 200_000_000_000).getReadableSpeed(base: .bit), "1.6 Tb/s")
    }
    
    func testUnitsGetReadableSpeed_fixedUnit() throws {
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte, unit: "KB"), "500 KB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte, unit: "MB"), "0.5 MB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .bit, unit: "MB"), "4 Mb/s")
    }

    @MainActor
    func testPopupMenuReplaysCachedValuesAndClosesReaders() {
        let content = PopupTestView()
        content.update(1)
        content.update(2)
        var visibility: [Bool] = []
        let menu = PopupMenu(title: "CPU", module: .CPU, view: content) { visibility.append($0) }

        menu.menuNeedsUpdate(menu)
        menu.menuWillOpen(menu)
        XCTAssertEqual(content.renderedValue, 2)
        XCTAssertTrue(menu.isVisible)
        XCTAssertEqual(visibility, [true])

        menu.menuDidClose(menu)
        XCTAssertFalse(menu.isVisible)
        XCTAssertEqual(content.disappearCount, 1)
        XCTAssertEqual(visibility, [true, false])
    }

    @MainActor
    func testPopupMenuResizesContentWithoutResizingItsHostingWindow() throws {
        let content = PopupTestView()
        let menu = PopupMenu(title: "CPU", module: .CPU, view: content) { _ in }
        let host = try XCTUnwrap(menu.items.first?.view)
        let originalMenuHeight = menu.size.height
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(host)
        let originalWindowSize = window.frame.size
        let originalHostHeight = host.frame.height

        content.setFrameSize(NSSize(width: Constants.Popup.width, height: 200))
        content.sizeCallback?(content.frame.size)

        XCTAssertEqual(host.frame.height - originalHostHeight, 100)
        XCTAssertEqual(menu.size.height - originalMenuHeight, 100)
        XCTAssertEqual(window.frame.size, originalWindowSize)
        window.contentView = nil
        window.close()
    }

    @MainActor
    func testPopupMenuBoundsTallContentToTheScreen() throws {
        let content = PopupTestView()
        content.setFrameSize(NSSize(width: Constants.Popup.width, height: 10_000))
        let menu = PopupMenu(title: "CPU", module: .CPU, view: content) { _ in }
        menu.menuNeedsUpdate(menu)
        let host = try XCTUnwrap(menu.items.first?.view)
        let scrollView = try XCTUnwrap(host.subviews.compactMap { $0 as? NSScrollView }.first)
        let screen = try XCTUnwrap(NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)

        XCTAssertLessThanOrEqual(menu.size.height, screen.visibleFrame.height)
        XCTAssertGreaterThan(scrollView.documentView?.frame.height ?? 0, scrollView.contentSize.height)
        XCTAssertTrue(scrollView.hasVerticalScroller)
    }

    @MainActor
    func testPopupMenuKeepsTheHeaderButtons() throws {
        let menu = PopupMenu(title: "CPU", module: .CPU, view: PopupTestView()) { _ in }
        let host = try XCTUnwrap(menu.items.first?.view)
        let header = try XCTUnwrap(host.subviews.first as? NSStackView)
        let buttons = header.arrangedSubviews.compactMap { $0 as? NSButton }

        XCTAssertEqual(menu.items.count, 1)
        XCTAssertEqual(buttons.count, 2)
        XCTAssertTrue(buttons.allSatisfy { !$0.isHidden })
        XCTAssertEqual(buttons.first?.action, #selector(HeaderView.openActivityMonitor))
        XCTAssertEqual(buttons.last?.action, #selector(HeaderView.openSettings))
    }

    @MainActor
    func testDetachedPopupWindowPreservesItsDragAnchorAcrossResizing() {
        let source = NSRect(x: -1800, y: -900, width: 280, height: 380)
        let mouseDown = NSPoint(x: source.minX + 130, y: source.maxY - 18)
        let anchor = PopupDragAnchor(frame: source, mouseLocation: mouseDown)
        let content = NSView(frame: NSRect(origin: .zero, size: source.size))
        let insets = NSEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
        let window = DetachedPopupWindow(title: "CPU", view: content, frame: source, contentInsets: insets)
        defer { window.close() }

        window.setDragLocation(mouseDown, anchor: anchor)
        XCTAssertEqual(window.frame, source)
        XCTAssertEqual(content.frame.origin, NSPoint(x: 0, y: 5))
        XCTAssertEqual(content.frame.height, source.height - 10)

        window.setPopupContentSize(NSSize(width: 280, height: 500))
        let movedPointer = NSPoint(x: mouseDown.x + 240, y: mouseDown.y - 70)
        window.setDragLocation(movedPointer, anchor: anchor)
        XCTAssertEqual(window.frame.minX, source.minX + 240)
        XCTAssertEqual(window.frame.maxY, source.maxY - 70)
        XCTAssertEqual(window.frame.height, 510)
        XCTAssertEqual(content.frame.origin, NSPoint(x: 0, y: 5))
        XCTAssertEqual(content.frame.size, NSSize(width: 280, height: 500))
    }

    @MainActor
    func testDetachedPopupWindowClosesWithEscapeAndCommandW() throws {
        let shortcuts: [(String, UInt16, NSEvent.ModifierFlags)] = [("\u{1b}", 53, []), ("w", 13, .command)]
        for (characters, keyCode, modifiers) in shortcuts {
            let content = PopupTestView()
            var visibility: [Bool] = []
            let menu = PopupMenu(title: "CPU", module: .CPU, view: content) { visibility.append($0) }
            let host = try XCTUnwrap(menu.items.first?.view)
            let window = DetachedPopupWindow(title: "CPU", view: host, frame: host.frame, contentInsets: NSEdgeInsets())
            window.delegate = menu
            defer {
                window.delegate = nil
                window.close()
            }
            menu.menuWillOpen(menu)

            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ))
            if modifiers == .command {
                XCTAssertTrue(window.performKeyEquivalent(with: event))
            } else {
                window.sendEvent(event)
            }

            XCTAssertFalse(menu.isVisible)
            XCTAssertEqual(visibility, [true, false])
            XCTAssertEqual(content.disappearCount, 1)
        }
    }

    @MainActor
    func testDetachedPopupWindowLeavesOtherKeyEquivalentsAvailable() throws {
        let content = PopupTestView()
        var visibility: [Bool] = []
        let menu = PopupMenu(title: "CPU", module: .CPU, view: content) { visibility.append($0) }
        let host = try XCTUnwrap(menu.items.first?.view)
        let window = DetachedPopupWindow(title: "CPU", view: host, frame: host.frame, contentInsets: NSEdgeInsets())
        window.delegate = menu
        defer {
            window.delegate = nil
            window.close()
        }
        menu.menuWillOpen(menu)

        for modifiers: NSEvent.ModifierFlags in [[], [.command, .shift], [.command, .option], [.command, .control]] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "w",
                charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13
            ))
            XCTAssertFalse(window.performKeyEquivalent(with: event))
            XCTAssertTrue(menu.isVisible)
            XCTAssertEqual(visibility, [true])
            XCTAssertEqual(content.disappearCount, 0)
        }
    }

    @MainActor
    func testDetachedPopupWindowUsesATransparentEffectBackground() throws {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 300))
        let window = DetachedPopupWindow(title: "CPU", view: content, frame: content.frame, contentInsets: NSEdgeInsets())
        defer { window.close() }

        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertTrue(window.hasShadow)
        XCTAssertTrue(window.canBecomeKey)
        if #available(macOS 26.0, *) {
            let glass = try XCTUnwrap(window.contentView as? NSGlassEffectView)
            XCTAssertTrue(content.superview === glass.contentView)
            XCTAssertGreaterThan(glass.cornerRadius, 0)
        } else {
            let effect = try XCTUnwrap(window.contentView as? NSVisualEffectView)
            XCTAssertTrue(content.superview?.superview === effect)
            XCTAssertEqual(effect.material, .menu)
            XCTAssertEqual(effect.blendingMode, .behindWindow)
        }
    }

    @MainActor
    func testPopupMenuKeepsReadersActiveWhenDetachingAndCanCancelTheTransfer() throws {
        let content = PopupTestView()
        var visibility: [Bool] = []
        let menu = PopupMenu(title: "CPU", module: .CPU, view: content) { visibility.append($0) }
        let host = try XCTUnwrap(menu.items.first?.view)
        let header = try XCTUnwrap(host.subviews.first)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.frame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        menu.menuWillOpen(menu)

        let start = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 100, y: host.frame.height - 10),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let drag = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDragged, location: NSPoint(x: 110, y: host.frame.height - 10),
            modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        header.mouseDown(with: start)
        header.mouseDragged(with: drag)
        menu.menuDidClose(menu)

        XCTAssertTrue(menu.isDetached)
        XCTAssertTrue(menu.isVisible)
        XCTAssertEqual(visibility, [true])
        XCTAssertEqual(content.disappearCount, 0)

        menu.hide()
        XCTAssertFalse(menu.isVisible)
        XCTAssertEqual(visibility, [true, false])
        XCTAssertEqual(content.disappearCount, 1)
        window.contentView = nil
        window.close()
    }
}

private final class PopupTestView: PopupWrapper {
    private let cache = PopupCache<Int>()
    private(set) var renderedValue: Int?
    private(set) var disappearCount = 0

    init() {
        super.init(.CPU, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 100))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ value: Int) {
        self.cache.apply(value, visible: false) { self.renderedValue = $0 }
    }

    override func appear() {
        self.replay(self.cache) { self.renderedValue = $0 }
    }

    override func disappear() {
        self.disappearCount += 1
    }
}
