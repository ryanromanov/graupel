//
//  TabStrip.swift
//
//  Graupel
//  https://github.com/ryanromanov/graupel
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit

/// A row of square tabs, one for each document open in a folder window.
final class TabStrip: NSView, ChromeColoring {

    /// What a tab shows.
    struct Item: Equatable {

        var id: ObjectIdentifier
        var title: String
        /// What tells the tab apart from another with the same title.
        var detail: String?
        var toolTip: String?
        var isSelected: Bool
        var isPreview: Bool
        var isEdited: Bool
    }


    /// What the user asks of a tab.
    enum Command: Equatable {

        case select
        case keep
        case close
        case closeOthers
        case openInNewWindow
        case reveal
        case move(Int)
    }


    // MARK: Public Properties

    /// The height of the strip in a row of its own, which matches the sidebar’s tabs.
    static let height: CGFloat = 32

    /// Called when the user asks something of a tab.
    var perform: ((Command, ObjectIdentifier) -> Void)?

    var overflow: TabOverflow = .scroll {

        didSet {
            guard overflow != oldValue else { return }

            self.revealsSelection = true
            self.needsLayout = true
        }
    }


    // MARK: Private Properties

    private static let listButtonWidth: CGFloat = 36

    private let clipView = NSView()
    private let listButton = TopBarCell()
    private var items: [Item] = []
    private var cells: [ObjectIdentifier: TabCell] = [:]
    private var tabWidth = TabLayout.preferredWidth
    private var scrollOffset: CGFloat = 0
    private var revealsSelection = false


    // MARK: Lifecycle

    override init(frame frameRect: NSRect) {

        super.init(frame: frameRect)

        self.clipView.clipsToBounds = true
        self.addSubview(self.clipView)

        self.listButton.symbolName = "chevron.down"
        self.listButton.label = String(localized: "List Tabs", table: "Document", comment: "button; lists all the open tabs")
        self.listButton.toolTip = self.listButton.label
        self.listButton.target = self
        self.listButton.action = #selector(showList)
        self.listButton.isHidden = true
        self.addSubview(self.listButton)

        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.tabGroup)
        self.setAccessibilityLabel(String(localized: "Tabs", table: "Document", comment: "accessibility label"))
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }


    // MARK: View Methods

    override var isFlipped: Bool  { true }

    override var allowsVibrancy: Bool  { false }

    override var mouseDownCanMoveWindow: Bool  { false }


    override func layout() {

        super.layout()

        let height = max(self.bounds.height - 1, 0)  // above the line at the bottom
        let metrics = TabLayout(count: self.items.count, width: self.bounds.width,
                                listButtonWidth: Self.listButtonWidth, overflow: self.overflow)
        let viewport = max(self.bounds.width - (metrics.overflows ? Self.listButtonWidth : 0), 0)

        self.tabWidth = metrics.tabWidth
        self.listButton.isHidden = !metrics.overflows
        self.listButton.frame = self.mirrored(NSRect(x: viewport, y: 0, width: Self.listButtonWidth, height: height), in: self.bounds.width)
        self.clipView.frame = self.mirrored(NSRect(x: 0, y: 0, width: viewport, height: height), in: self.bounds.width)

        let selection = self.revealsSelection ? self.items.firstIndex(where: \.isSelected) : nil
        self.scrollOffset = TabLayout.offset(self.scrollOffset, revealing: selection, tabWidth: metrics.tabWidth,
                                             count: self.items.count, viewport: viewport)
        // -> Keep the request until the strip has a size.
        if viewport > 0 {
            self.revealsSelection = false
        }

        for (index, item) in self.items.enumerated() {
            let x = CGFloat(index) * metrics.tabWidth - self.scrollOffset
            self.cells[item.id]?.frame = self.mirrored(NSRect(x: x, y: 0, width: metrics.tabWidth, height: height), in: viewport)
        }
    }


    override func draw(_ dirtyRect: NSRect) {

        let style = self.style

        (style?.background ?? .windowBackgroundColor).setFill()
        self.bounds.fill()

        (style?.border ?? .separatorColor).setFill()
        NSRect(x: 0, y: self.bounds.height - 1, width: self.bounds.width, height: 1).fill()
    }


    override func scrollWheel(with event: NSEvent) {

        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        let step = event.hasPreciseScrollingDeltas ? delta : delta * 10
        let direction: CGFloat = (self.userInterfaceLayoutDirection == .rightToLeft) ? -1 : 1

        self.scrollOffset -= step * direction
        self.needsLayout = true
    }


    // MARK: Public Methods

    /// Shows the tabs of the given items.
    func apply(_ items: [Item]) {

        guard items != self.items else { return }

        // bring the selected tab into view when it changes or moves, but not while the user scrolls
        let selectionPlace = items.firstIndex(where: \.isSelected).map { (items[$0].id, $0) }
        let oldSelectionPlace = self.items.firstIndex(where: \.isSelected).map { (self.items[$0].id, $0) }
        if selectionPlace?.0 != oldSelectionPlace?.0 || selectionPlace?.1 != oldSelectionPlace?.1 || items.count != self.items.count {
            self.revealsSelection = true
        }
        self.items = items

        let ids = Set(items.map(\.id))
        for (id, cell) in self.cells where !ids.contains(id) {
            cell.removeFromSuperview()
            self.cells[id] = nil
        }
        for item in items {
            if let cell = self.cells[item.id] {
                cell.item = item
            } else {
                let cell = TabCell(item: item, strip: self)
                self.cells[item.id] = cell
                self.clipView.addSubview(cell)
            }
        }
        self.setAccessibilityChildren(items.compactMap { self.cells[$0.id] } + [self.listButton])

        self.updateChromeColors()
        self.needsLayout = true
    }


    func updateChromeColors() {

        let style = self.style

        self.listButton.pressedColor = style?.fill ?? .quaternaryLabelColor
        self.listButton.contentTintColor = style?.secondaryText ?? .secondaryLabelColor
        self.cells.values.forEach { $0.updateChromeColors() }
        self.needsDisplay = true
    }


    // MARK: Private Methods

    fileprivate var style: ChromeStyle? {

        (self.window as? DocumentWindow)?.chrome?.style
    }


    /// Moves the tab of the item to where the pointer is.
    fileprivate func drag(_ id: ObjectIdentifier, with event: NSEvent) {

        let point = self.clipView.convert(event.locationInWindow, from: nil)
        let x = (self.userInterfaceLayoutDirection == .rightToLeft) ? self.clipView.bounds.width - point.x : point.x
        let index = min(max(Int((x + self.scrollOffset) / max(self.tabWidth, 1)), 0), self.items.count - 1)

        guard self.items.firstIndex(where: { $0.id == id }) != index else { return }

        self.perform?(.move(index), id)
    }


    /// Shows a menu of all the tabs.
    @objc private func showList(_ sender: NSButton) {

        let menu = NSMenu()
        for item in self.items {
            let title = [item.title, item.detail].compactMap(\.self).joined(separator: " — ")
            let menuItem = NSMenuItem(title: title, action: #selector(selectFromList), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.id
            menuItem.state = item.isSelected ? .on : .off
            menu.addItem(menuItem)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
    }


    @objc private func selectFromList(_ sender: NSMenuItem) {

        guard let id = sender.representedObject as? ObjectIdentifier else { return }

        self.perform?(.select, id)
    }


    /// Converts a frame between leading-edge coordinates and view coordinates.
    private func mirrored(_ rect: NSRect, in width: CGFloat) -> NSRect {

        guard self.userInterfaceLayoutDirection == .rightToLeft else { return rect }

        var rect = rect
        rect.origin.x = width - rect.maxX

        return rect
    }
}


/// The sizes of the tabs in a strip.
struct TabLayout: Equatable {

    static let preferredWidth: CGFloat = 150
    static let minimumWidth: CGFloat = 64

    var tabWidth: CGFloat
    /// Whether some tabs are out of view.
    var overflows: Bool


    /// - Parameters:
    ///   - count: The number of tabs.
    ///   - width: The width of the strip.
    ///   - listButtonWidth: The width that the list button takes when some tabs are out of view.
    ///   - overflow: What to do with tabs that don’t fit.
    init(count: Int, width: CGFloat, listButtonWidth: CGFloat, overflow: TabOverflow) {

        let fits = CGFloat(count) * Self.preferredWidth <= width

        switch overflow {
            case .scroll:
                self.tabWidth = Self.preferredWidth
                self.overflows = !fits

            case .shrink:
                let shared = count > 0 ? (width / CGFloat(count)).rounded(.down) : Self.preferredWidth
                if shared >= Self.minimumWidth {
                    self.tabWidth = min(shared, Self.preferredWidth)
                    self.overflows = false
                } else {
                    // past the minimum width, they scroll
                    self.tabWidth = Self.minimumWidth
                    self.overflows = true
                }
        }
    }


    /// Returns how far the tabs are scrolled, kept within them.
    ///
    /// - Parameters:
    ///   - offset: The current offset.
    ///   - index: The tab to bring into view, if any.
    ///   - tabWidth: The width of a tab.
    ///   - count: The number of tabs.
    ///   - viewport: The width the tabs show in.
    static func offset(_ offset: CGFloat, revealing index: Int?, tabWidth: CGFloat, count: Int, viewport: CGFloat) -> CGFloat {

        var offset = offset
        if let index {
            let start = CGFloat(index) * tabWidth
            offset = max(min(offset, start), start + tabWidth - viewport)
        }

        return min(max(offset, 0), max(CGFloat(count) * tabWidth - viewport, 0))
    }
}


/// A tab: its title and a button to close it.
private final class TabCell: NSView {

    var item: TabStrip.Item  { didSet { self.update() } }

    private weak var strip: TabStrip?
    private let label = NSTextField(labelWithString: "")
    private let closeButton = TabCloseButton()
    private var isHovered = false  { didSet { if isHovered != oldValue { self.update() } } }


    init(item: TabStrip.Item, strip: TabStrip) {

        self.item = item
        self.strip = strip

        super.init(frame: .zero)

        self.addSubview(self.label)

        self.closeButton.target = self
        self.closeButton.action = #selector(close)
        self.addSubview(self.closeButton)

        self.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))

        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.radioButton)
        self.update()
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }


    // MARK: View Methods

    override var isFlipped: Bool  { true }

    override var allowsVibrancy: Bool  { false }

    override var mouseDownCanMoveWindow: Bool  { false }


    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {

        true
    }


    override func hitTest(_ point: NSPoint) -> NSView? {

        guard let view = super.hitTest(point) else { return nil }

        return (view is TabCloseButton) ? view : self
    }


    override func layout() {

        super.layout()

        let isRightToLeft = (self.userInterfaceLayoutDirection == .rightToLeft)
        let width = self.bounds.width
        func mirrored(_ rect: NSRect) -> NSRect {
            isRightToLeft ? NSRect(x: width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) : rect
        }

        let buttonSize: CGFloat = 18
        let padding: CGFloat = (width < 100) ? 6 : 12
        self.closeButton.frame = mirrored(NSRect(x: width - buttonSize - 5, y: ((self.bounds.height - buttonSize) / 2).rounded(), width: buttonSize, height: buttonSize))

        let labelEnd = self.closeButton.isHidden ? width - padding : width - buttonSize - 8
        let labelHeight = ceil(self.label.cell?.cellSize.height ?? 16)
        self.label.frame = mirrored(NSRect(x: padding, y: ((self.bounds.height - labelHeight) / 2).rounded(), width: max(labelEnd - padding, 0), height: labelHeight))

        // a narrow tab shows the button only where it’s needed
        let showsButton = width >= 100 || self.item.isSelected || self.isHovered || self.item.isEdited
        if self.closeButton.isHidden == showsButton {
            self.closeButton.isHidden = !showsButton
            self.needsLayout = true
        }
    }


    override func draw(_ dirtyRect: NSRect) {

        let style = self.strip?.style

        if self.item.isSelected {
            (style?.selection ?? .controlAccentColor).setFill()
            self.bounds.fill()
        } else if self.isHovered {
            (style?.fill ?? .quaternaryLabelColor).setFill()
            self.bounds.fill()
        }

        (style?.border ?? .separatorColor).setFill()
        let lineX = (self.userInterfaceLayoutDirection == .rightToLeft) ? 0 : self.bounds.width - 1
        NSRect(x: lineX, y: 0, width: 1, height: self.bounds.height).fill()
    }


    override func mouseEntered(with event: NSEvent) {

        self.isHovered = true
    }


    override func mouseExited(with event: NSEvent) {

        self.isHovered = false
    }


    override func mouseDown(with event: NSEvent) {

        let id = self.item.id
        self.strip?.perform?(.select, id)

        if event.clickCount == 2 {
            self.strip?.perform?(.keep, id)
            return
        }

        // drag along the strip to reorder
        guard let window = self.window else { return }

        let start = event.locationInWindow.x
        var isDragging = false
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]), next.type != .leftMouseUp {
            isDragging = isDragging || abs(next.locationInWindow.x - start) > 4
            if isDragging {
                self.strip?.drag(id, with: next)
            }
        }
    }


    override func menu(for event: NSEvent) -> NSMenu? {

        let menu = NSMenu()
        menu.autoenablesItems = false

        func add(_ title: String, _ action: Selector, isEnabled: Bool = true) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = isEnabled
        }
        add(String(localized: "Close Tab", table: "Document", comment: "menu item"), #selector(close))
        add(String(localized: "Close Other Tabs", table: "Document", comment: "menu item"), #selector(closeOthers),
            isEnabled: (self.superview?.subviews.count ?? 0) > 1)
        if self.item.isPreview {
            add(String(localized: "Keep Tab Open", table: "Document", comment: "menu item; the preview tab stays"), #selector(keep))
        }
        menu.addItem(.separator())
        add(String(localized: "Open in New Window", table: "Document", comment: "menu item"), #selector(openInNewWindow))
        add(String(localized: "Show in File Browser", table: "Document", comment: "menu item"), #selector(reveal))

        return menu
    }


    // MARK: Accessibility

    override func accessibilityPerformPress() -> Bool {

        self.strip?.perform?(.select, self.item.id)

        return true
    }


    // MARK: Public Methods

    func updateChromeColors() {

        self.update()
    }


    // MARK: Private Methods

    @objc private func close()  { self.strip?.perform?(.close, self.item.id) }
    @objc private func closeOthers()  { self.strip?.perform?(.closeOthers, self.item.id) }
    @objc private func keep()  { self.strip?.perform?(.keep, self.item.id) }
    @objc private func openInNewWindow()  { self.strip?.perform?(.openInNewWindow, self.item.id) }
    @objc private func reveal()  { self.strip?.perform?(.reveal, self.item.id) }


    private func update() {

        let item = self.item
        let style = self.strip?.style
        let color: NSColor = if item.isSelected {
            style?.onSelection ?? .alternateSelectedControlTextColor
        } else if self.isHovered {
            style?.text ?? .labelColor
        } else {
            style?.secondaryText ?? .secondaryLabelColor
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        var font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        if item.isPreview {
            let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
            font = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        }
        let title = NSMutableAttributedString(string: item.title, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        if let detail = item.detail {
            title.append(NSAttributedString(string: "  " + detail, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: color.withAlphaComponent(0.75),
                .paragraphStyle: paragraph,
            ]))
        }
        self.label.attributedStringValue = title
        self.toolTip = item.toolTip

        // the dot of unsaved changes turns into the close button under the pointer
        self.closeButton.symbolName = (item.isEdited && !self.isHovered) ? "circle.fill" : "xmark"
        self.closeButton.contentTintColor = color

        self.setAccessibilityLabel([item.title, item.detail].compactMap(\.self).joined(separator: ", "))
        self.setAccessibilityValue(item.isSelected ? 1 : 0)
        self.setAccessibilityHelp(item.isEdited
            ? String(localized: "Document has unsaved changes", table: "Document", comment: "tooltip for the “edited” indicator in the window tab")
            : nil)
        self.setAccessibilityChildren([self.closeButton])

        self.needsLayout = true
        self.needsDisplay = true
    }
}


/// The button in a tab that closes it, which shows a dot while there are unsaved changes.
private final class TabCloseButton: NSButton {

    var symbolName = ""  { didSet { if symbolName != oldValue { self.updateImage() } } }


    init() {

        super.init(frame: .zero)

        self.isBordered = false
        self.imagePosition = .imageOnly
        self.setButtonType(.momentaryChange)
        self.cell?.setAccessibilityLabel(String(localized: "Close Tab", table: "Document", comment: "menu item"))
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }


    override var alignmentRectInsets: NSEdgeInsets  { NSEdgeInsets() }

    override var allowsVibrancy: Bool  { false }

    override var mouseDownCanMoveWindow: Bool  { false }


    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {

        true
    }


    private func updateImage() {

        let size: CGFloat = (self.symbolName == "circle.fill") ? 7 : 9
        self.image = NSImage(systemSymbolName: self.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
    }
}
