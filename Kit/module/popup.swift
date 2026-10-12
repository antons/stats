//
//  popup.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 11/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public final class PopupCache<T> {
    public var value: T?
    public var initialized: Bool = false
    
    public init() {}
    
    public func apply(_ value: T, visible: Bool, render: (T) -> Void) {
        self.value = value
        if visible || !self.initialized {
            render(value)
            self.initialized = true
        }
    }
    
    public func replay(render: (T) -> Void) {
        if let v = self.value { render(v) }
    }
}

public protocol Popup_p: NSView {
    var keyboardShortcut: [UInt16] { get }
    var sizeCallback: ((NSSize) -> Void)? { get set }
    
    func settings() -> NSView?
    
    func appear()
    func disappear()
    func setKeyboardShortcut(_ binding: [UInt16])
}

open class PopupWrapper: NSStackView, Popup_p {
    public var title: String
    public var keyboardShortcut: [UInt16] = []
    open var sizeCallback: ((NSSize) -> Void)? = nil
    
    public init(_ typ: ModuleType, frame: NSRect) {
        self.title = typ.stringValue
        self.keyboardShortcut = Store.shared.array(key: "\(typ.stringValue)_popup_keyboardShortcut", defaultValue: []) as? [UInt16] ?? []
        
        super.init(frame: frame)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open func settings() -> NSView? { return nil }
    open func appear() {}
    open func disappear() {}
    
    open func setKeyboardShortcut(_ binding: [UInt16]) {
        self.keyboardShortcut = binding
        Store.shared.set(key: "\(self.title)_popup_keyboardShortcut", value: binding)
    }
    
    public func apply<T>(_ value: T, to cache: PopupCache<T>, render: @escaping (T) -> Void) {
        DispatchQueue.main.async {
            cache.apply(value, visible: self.window?.isVisible ?? false, render: render)
        }
    }
    
    public func replay<T>(_ cache: PopupCache<T>, render: (T) -> Void) {
        cache.replay(render: render)
    }
}

public final class PopupMenu: NSMenu, NSMenuDelegate, NSWindowDelegate {
    private enum Presentation {
        case hidden
        case menu
        case detaching
        case window
    }

    private struct Detachment {
        let frame: NSRect
        let contentInsets: NSEdgeInsets
        let anchor: PopupDragAnchor
        var mouseLocation: NSPoint
    }

    private let popup: PopupView
    private let contentItem = NSMenuItem()
    private let visibilityCallback: (Bool) -> Void
    private var presentation: Presentation = .hidden
    private var readersVisible = false
    private var detachedWindow: DetachedPopupWindow?
    private var detachment: Detachment?
    private var dragAnchor: PopupDragAnchor?
    private var dragMonitor: Any?
    private var positioningScreen: NSScreen?

    public var isVisible: Bool { self.presentation != .hidden }
    public var isDetached: Bool { self.presentation == .window || self.presentation == .detaching }

    public init(title: String, module: ModuleType, view: Popup_p?, visibilityCallback: @escaping (Bool) -> Void) {
        self.popup = PopupView(module: module)
        self.visibilityCallback = visibilityCallback
        super.init(title: title)

        self.autoenablesItems = false
        self.delegate = self
        self.popup.setTitle(title)
        self.popup.setView(view)
        self.popup.header.setDetached(false)
        self.popup.header.dragCallback = { [weak self] event, mouseLocation in
            self?.drag(with: event, mouseLocation: mouseLocation)
        }
        self.popup.header.actionCallback = { [weak self] in
            guard let self = self, self.presentation == .menu else { return }
            self.cancelTracking()
        }
        self.popup.sizeCallback = { [weak self] in
            guard let self = self, let window = self.detachedWindow else { return }
            let top = window.frame.maxY
            window.setPopupContentSize(self.popup.frame.size)
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        }

        self.contentItem.title = title
        self.contentItem.isEnabled = false
        self.contentItem.view = self.popup
        self.addItem(self.contentItem)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = self.dragMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    public func toggle(at origin: NSPoint, center: CGFloat) {
        if self.isVisible {
            self.hide()
            return
        }

        let anchor = NSPoint(x: origin.x + center, y: origin.y)
        self.positioningScreen = NSScreen.screens.first { $0.frame.contains(anchor) }
        self.menuNeedsUpdate(self)
        let point = NSPoint(x: anchor.x - self.size.width / 2, y: anchor.y - 3)
        self.popUp(positioning: nil, at: point, in: nil)
        self.positioningScreen = nil
    }

    public func hide() {
        switch self.presentation {
        case .menu:
            self.cancelTracking()
        case .window:
            self.detachedWindow?.close()
        case .detaching:
            self.endDrag()
            self.detachment = nil
            self.presentation = .hidden
            self.popup.disappear()
            self.setReadersVisible(false)
        case .hidden:
            break
        }
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        self.endDrag()
        self.detachment = nil
        if let window = self.detachedWindow {
            window.delegate = nil
            window.contentView = nil
            window.close()
            self.detachedWindow = nil
        }
        if self.isDetached {
            self.presentation = .menu
        }
        self.popup.header.setDetached(false)
        self.contentItem.view = self.popup
        let screen = self.positioningScreen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let reservedHeight = max(0, self.size.height - self.popup.frame.height)
        self.popup.prepare(screen: screen, reservedHeight: reservedHeight)
    }

    public func menuWillOpen(_ menu: NSMenu) {
        self.presentation = .menu
        self.popup.appear()
        self.setReadersVisible(true)
    }

    public func menuDidClose(_ menu: NSMenu) {
        if self.presentation == .detaching {
            DispatchQueue.main.async { [weak self] in
                self?.finishDetaching()
            }
            return
        }
        self.presentation = .hidden
        self.popup.disappear()
        self.setReadersVisible(false)
    }

    public func windowWillClose(_ notification: Notification) {
        self.endDrag()
        self.detachedWindow?.contentView = nil
        self.detachedWindow = nil
        self.presentation = .hidden
        self.popup.disappear()
        self.setReadersVisible(false)
    }

    public func windowDidChangeScreen(_ notification: Notification) {
        guard let window = self.detachedWindow else { return }
        self.popup.prepare(screen: window.screen, reservedHeight: window.contentInsets.top + window.contentInsets.bottom)
    }

    private func setReadersVisible(_ visible: Bool) {
        guard visible != self.readersVisible else { return }
        self.readersVisible = visible
        self.visibilityCallback(visible)
        NotificationCenter.default.post(name: .popupVisibilityChanged, object: nil, userInfo: ["state": visible])
    }

    private func drag(with event: NSEvent, mouseLocation: NSPoint) {
        if let window = self.detachedWindow {
            window.performDrag(with: event)
            return
        }
        guard self.presentation == .menu, let window = self.popup.window else { return }
        let contentFrame = window.convertToScreen(self.popup.convert(self.popup.bounds, to: nil))
        let frame = window.frame
        let contentInsets = NSEdgeInsets(
            top: max(0, frame.maxY - contentFrame.maxY),
            left: max(0, contentFrame.minX - frame.minX),
            bottom: max(0, contentFrame.minY - frame.minY),
            right: max(0, frame.maxX - contentFrame.maxX)
        )
        let anchor = PopupDragAnchor(frame: frame, mouseLocation: mouseLocation)
        self.detachment = Detachment(
            frame: frame,
            contentInsets: contentInsets,
            anchor: anchor,
            mouseLocation: NSEvent.mouseLocation
        )
        self.dragAnchor = anchor
        self.dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return event }
            let location = NSEvent.mouseLocation
            self.detachment?.mouseLocation = location
            if let window = self.detachedWindow, let anchor = self.dragAnchor {
                window.setDragLocation(location, anchor: anchor)
            }
            if event.type == .leftMouseUp {
                self.endDrag()
            }
            return nil
        }
        self.presentation = .detaching
        self.cancelTrackingWithoutAnimation()
    }

    private func endDrag() {
        if let monitor = self.dragMonitor {
            NSEvent.removeMonitor(monitor)
            self.dragMonitor = nil
        }
        self.dragAnchor = nil
    }

    private func finishDetaching() {
        guard self.presentation == .detaching, let detachment = self.detachment else { return }
        self.detachment = nil
        self.contentItem.view = nil
        self.popup.header.setDetached(true)

        let window = DetachedPopupWindow(title: self.title, view: self.popup, frame: detachment.frame,
                                         contentInsets: detachment.contentInsets)
        window.delegate = self
        self.detachedWindow = window
        self.presentation = .window
        self.popup.prepare(screen: window.screen, reservedHeight: window.contentInsets.top + window.contentInsets.bottom)
        window.setPopupContentSize(self.popup.frame.size)
        let mouseLocation = NSEvent.pressedMouseButtons & 1 != 0 ? NSEvent.mouseLocation : detachment.mouseLocation
        window.setDragLocation(mouseLocation, anchor: detachment.anchor)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.popup.appear()

        if NSEvent.pressedMouseButtons & 1 == 0 {
            self.endDrag()
        }
    }
}

internal struct PopupDragAnchor {
    private let offset: NSPoint

    init(frame: NSRect, mouseLocation: NSPoint) {
        self.offset = NSPoint(x: mouseLocation.x - frame.minX, y: mouseLocation.y - frame.maxY)
    }

    func origin(at location: NSPoint, size: NSSize) -> NSPoint {
        NSPoint(x: location.x - self.offset.x, y: location.y - self.offset.y - size.height)
    }
}

internal final class DetachedPopupWindow: NSWindow {
    let contentInsets: NSEdgeInsets

    override var canBecomeKey: Bool { true }

    init(title: String, view: NSView, frame: NSRect, contentInsets: NSEdgeInsets) {
        self.contentInsets = contentInsets
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        self.title = title
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        self.collectionBehavior = .moveToActiveSpace
        let content = DetachedPopupContentView(frame: NSRect(origin: .zero, size: frame.size),
                                               view: view, contentInsets: contentInsets)
        content.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: frame.size))
            glass.style = .regular
            glass.cornerRadius = 12
            glass.wantsLayer = true
            glass.layer?.cornerRadius = glass.cornerRadius
            glass.layer?.masksToBounds = true
            glass.contentView = content
            self.contentView = glass
        } else {
            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
            effect.material = .menu
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Constants.Popup.radius
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            self.contentView = effect
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cancelOperation(_ sender: Any?) {
        self.close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            self.cancelOperation(event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .keyDown, modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            self.close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func setDragLocation(_ location: NSPoint, anchor: PopupDragAnchor) {
        self.setFrameOrigin(anchor.origin(at: location, size: self.frame.size))
    }

    func setPopupContentSize(_ size: NSSize) {
        self.setContentSize(NSSize(width: size.width + self.contentInsets.left + self.contentInsets.right,
                                   height: size.height + self.contentInsets.top + self.contentInsets.bottom))
    }
}

private final class DetachedPopupContentView: NSView {
    private let popup: NSView
    private let contentInsets: NSEdgeInsets

    init(frame: NSRect, view: NSView, contentInsets: NSEdgeInsets) {
        self.popup = view
        self.contentInsets = contentInsets
        super.init(frame: frame)
        view.autoresizingMask = []
        self.addSubview(view)
        self.resizeSubviews(withOldSize: frame.size)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        self.popup.frame = NSRect(
            x: self.contentInsets.left,
            y: self.contentInsets.bottom,
            width: max(0, self.bounds.width - self.contentInsets.left - self.contentInsets.right),
            height: max(0, self.bounds.height - self.contentInsets.top - self.contentInsets.bottom)
        )
    }
}

internal class PopupView: NSView {
    private var view: Popup_p? = nil

    fileprivate let header: HeaderView
    private let body: NSScrollView
    fileprivate var sizeCallback: (() -> Void)?
    private var screen: NSScreen?
    private var reservedHeight: CGFloat = 0
    private var containerHeight: CGFloat = 0

    override var allowsVibrancy: Bool { true }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: self.frame.width, height: self.frame.height)
    }
    init(module: ModuleType) {
        let frame = NSRect(
            x: 0, y: 0,
            width: Constants.Popup.width + Constants.Popup.margins * 2,
            height: Constants.Popup.headerHeight + Constants.Popup.margins * 2
        )
        self.header = HeaderView(frame: NSRect(
            x: 0,
            y: frame.height - Constants.Popup.headerHeight,
            width: frame.width,
            height: Constants.Popup.headerHeight
        ), module: module)
        self.body = NSScrollView(frame: NSRect(
            x: Constants.Popup.margins,
            y: Constants.Popup.margins,
            width: frame.width - Constants.Popup.margins*2,
            height: frame.height - self.header.frame.height - Constants.Popup.margins*2
        ))
        super.init(frame: frame)
        
        self.body.drawsBackground = false
        self.body.translatesAutoresizingMaskIntoConstraints = true
        self.body.borderType = .noBorder
        self.body.hasVerticalScroller = true
        self.body.hasHorizontalScroller = false
        self.body.autohidesScrollers = true
        self.body.scrollerStyle = .overlay
        self.body.horizontalScrollElasticity = .none

        self.addSubview(self.header)
        self.addSubview(self.body)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.window?.acceptsMouseMovedEvents = true
    }

    fileprivate func setView(_ view: Popup_p?) {
        self.view = view
        self.body.documentView = view
        view?.sizeCallback = { [weak self] size in
            self?.recalculateHeight(size)
        }
        self.recalculateHeight(view?.frame.size ?? NSSize(width: Constants.Popup.width, height: 0))
    }
    
    fileprivate func setTitle(_ newTitle: String) {
        self.header.setTitle(newTitle)
    }
    
    fileprivate func prepare(screen: NSScreen?, reservedHeight: CGFloat) {
        self.screen = screen ?? NSScreen.main
        self.reservedHeight = reservedHeight
        self.recalculateHeight(self.view?.frame.size ?? NSSize(width: Constants.Popup.width, height: 0))
    }
    
    internal func appear() {
        self.view?.appear()
        
        self.needsDisplay = true
        if let documentView = self.body.documentView {
            documentView.scroll(NSPoint(x: 0, y: documentView.bounds.size.height))
        }
    }
    internal func disappear() {
        self.view?.disappear()
    }
    
    private func recalculateHeight(_ size: NSSize) {
        var viewSize = NSSize(
            width: size.width + (Constants.Popup.margins*2),
            height: size.height + Constants.Popup.headerHeight + (Constants.Popup.margins*2)
        )
        let previousHeight = self.containerHeight
        let previousOrigin = self.body.documentVisibleRect.origin.y
        self.containerHeight = size.height
        if let screenSize = self.screen?.visibleFrame.size {
            let maximumHeight = max(Constants.Popup.headerHeight + Constants.Popup.margins * 2,
                                    screenSize.height - self.reservedHeight - Constants.Popup.margins * 2)
            viewSize.height = min(viewSize.height, maximumHeight)
            viewSize.width = min(viewSize.width, screenSize.width)
        }

        self.setFrameSize(viewSize)
        self.header.frame = NSRect(x: 0, y: viewSize.height - Constants.Popup.headerHeight,
                                  width: viewSize.width, height: Constants.Popup.headerHeight)
        self.body.frame = NSRect(
            x: Constants.Popup.margins,
            y: Constants.Popup.margins,
            width: max(0, viewSize.width - Constants.Popup.margins * 2),
            height: max(0, viewSize.height - Constants.Popup.headerHeight - Constants.Popup.margins * 2)
        )

        if let documentView = self.body.documentView {
            let maximumOrigin = max(0, size.height - self.body.contentSize.height)
            let origin = min(maximumOrigin, max(0, previousOrigin + size.height - previousHeight))
            documentView.scroll(NSPoint(x: 0, y: origin))
        }
        self.invalidateIntrinsicContentSize()
        self.sizeCallback?()
    }
}

private final class HeaderButton: NSButtonWithPadding {
    override var alignmentRectInsets: NSEdgeInsets {
        var insets = super.alignmentRectInsets
        insets.top += 3
        insets.bottom -= 3
        return insets
    }
}

internal class HeaderView: NSStackView {
    private var titleView: NSTextField? = nil
    private var activityButton: NSButtonWithPadding?
    private var mouseDownEvent: NSEvent?
    private var mouseDownLocation: NSPoint = .zero
    fileprivate var dragCallback: ((NSEvent, NSPoint) -> Void)?
    fileprivate var actionCallback: (() -> Void)?
    
    private var title: String = ""
    private var isCloseAction: Bool = false
    private let activityMonitor: URL?
    private let calendar: URL?
    private var module: ModuleType
    
    init(frame: NSRect, module: ModuleType) {
        self.module = module
        self.activityMonitor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
        self.calendar = URL(fileURLWithPath: "/System/Applications/Calendar.app")
        
        super.init(frame: CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height))
        
        self.orientation = .horizontal
        self.distribution = .gravityAreas
        self.spacing = 0
        
        let activity = HeaderButton()
        activity.frame = CGRect(x: 0, y: 0, width: 24, height: self.frame.height)
        activity.bezelStyle = .regularSquare
        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.imageScaling = .scaleNone
        activity.contentTintColor = .secondaryLabelColor
        activity.isBordered = false
        activity.target = self
        activity.focusRingType = .none
        self.activityButton = activity
        self.setupActionButton()
        
        let title = NSTextField(frame: NSRect(x: 0, y: 0, width: frame.width/2, height: 18))
        title.isEditable = false
        title.isSelectable = false
        title.isBezeled = false
        title.wantsLayer = true
        title.textColor = .textColor
        title.backgroundColor = .clear
        title.canDrawSubviewsIntoLayer = true
        title.alignment = .center
        title.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        title.stringValue = ""
        self.titleView = title
        
        let settings = HeaderButton()
        settings.frame = CGRect(x: 0, y: 0, width: 24, height: self.frame.height)
        settings.horizontalPadding = Constants.Popup.headerHeight - 24 + (Constants.Popup.margins - 3) * 2
        settings.bezelStyle = .regularSquare
        settings.translatesAutoresizingMaskIntoConstraints = false
        settings.imageScaling = .scaleNone
        settings.image = self.symbolImage("command")
        settings.contentTintColor = .secondaryLabelColor
        settings.isBordered = false
        settings.action = #selector(self.openSettings)
        settings.target = self
        settings.toolTip = localizedString("Open module")
        settings.focusRingType = .none
        
        self.addView(activity, in: .leading)
        self.addView(title, in: .center)
        self.addView(settings, in: .trailing)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    fileprivate func setTitle(_ newTitle: String) {
        self.title = newTitle
        self.titleView?.stringValue = localizedString(newTitle)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if let title = self.titleView, let view = view, view.isDescendant(of: title) {
            return self
        }
        return view
    }

    override func mouseDown(with event: NSEvent) {
        if self.isCloseAction {
            self.dragCallback?(event, NSEvent.mouseLocation)
        } else {
            self.mouseDownEvent = event
            self.mouseDownLocation = NSEvent.mouseLocation
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = self.mouseDownEvent,
              hypot(event.locationInWindow.x - start.locationInWindow.x,
                    event.locationInWindow.y - start.locationInWindow.y) >= 4 else { return }
        self.mouseDownEvent = nil
        self.dragCallback?(start, self.mouseDownLocation)
    }

    override func mouseUp(with event: NSEvent) {
        self.mouseDownEvent = nil
    }

    private func symbolImage(_ name: String, pointSize: CGFloat = 16, paletteColors: [NSColor]? = nil) -> NSImage? {
        var configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        if let colors = paletteColors {
            configuration = configuration.applying(NSImage.SymbolConfiguration(paletteColors: colors))
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    private func setupActionButton() {
        guard let button = self.activityButton else { return }
        button.contentTintColor = .secondaryLabelColor
        button.horizontalPadding = Constants.Popup.headerHeight - 24 + (self.isCloseAction ? 0 : (Constants.Popup.margins - 3) * 2)
        
        if self.isCloseAction {
            button.action = #selector(self.closePopup)
            button.image = self.symbolImage("xmark.circle.fill", pointSize: 22, paletteColors: [.secondaryLabelColor, .quaternaryLabelColor])
            button.contentTintColor = nil
            button.toolTip = localizedString("Close")
            return
        }
        
        if self.module == .clock {
            button.action = #selector(self.openCalendar)
            button.image = self.symbolImage("calendar")
            button.toolTip = localizedString("Open Calendar")
            return
        } else if self.module == .remote {
            button.action = #selector(self.openSystemStats)
            button.image = self.symbolImage("globe")
            button.toolTip = localizedString("Open System Stats")
            return
        }
        
        button.action = #selector(self.openActivityMonitor)
        button.image = self.symbolImage("waveform.path.ecg")
        button.toolTip = localizedString("Open Activity Monitor")
    }
    
    @objc func openActivityMonitor() {
        guard let app = self.activityMonitor else { return }
        self.actionCallback?()
        if let tab = self.module.activityMonitorTab {
            UserDefaults(suiteName: "com.apple.ActivityMonitor")?.set(tab, forKey: "SelectedTab")
        }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    
    @objc func openCalendar() {
        guard let app = self.calendar else { return }
        self.actionCallback?()
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    
    @objc func openSystemStats() {
        guard let url = URL(string: "https://app.system-stats.com") else { return }
        self.actionCallback?()
        NSWorkspace.shared.open(url)
    }
    
    @objc func openSettings() {
        self.actionCallback?()
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": self.title])
    }
    
    @objc private func closePopup() {
        self.window?.close()
    }

    fileprivate func setDetached(_ detached: Bool) {
        self.isCloseAction = detached
        self.mouseDownEvent = nil
        self.setupActionButton()
    }
}
