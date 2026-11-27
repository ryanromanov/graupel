//
//  TopBar.swift
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

/// The bar across the top of a document window, made of square cells.
///
/// It takes the place of the toolbar and the title, and its colors follow the columns below it.
final class TopBar: NSView, ChromeColoring {

    /// What the bar shows.
    struct State {

        struct Toggle {

            var isOn: Bool
            var isEnabled: Bool
            var toolTip: String
        }

        /// The sidebar toggle, or `nil` if the window has no sidebar.
        var sidebar: Toggle?

        /// Whether the document history can go back and forward, or `nil` if the window has no history.
        var history: (back: Bool, forward: Bool)?

        var isRunning: Bool
        var canRun: Bool
        var inspector: Toggle
        var title: String
        var subtitle: String
        var isEdited: Bool
    }


    /// The widths of the columns beside the content, from the window’s leading and trailing edges.
    struct Columns {

        var leading: CGFloat
        var trailing: CGFloat
    }


    // MARK: Public Properties

    /// The height of the bar, which is also the height of the title bar with an empty compact toolbar.
    static let height: CGFloat = 40

    /// Returns the current widths of the side columns.
    var columnProvider: (() -> Columns)?

    let sidebarCell = TopBarCell()
    let backCell = TopBarCell()
    let forwardCell = TopBarCell()
    let runCell = TopBarCell()
    let inspectorCell = TopBarCell()


    // MARK: Private Properties

    private static let cellWidth: CGFloat = 42
    private static let titlePadding: CGFloat = 12

    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let editedField = NSTextField(labelWithString: "•")
    private var state: State?

    /// The lines to draw between cells and columns.
    private var lines: [NSRect] = []
    private var columnRects: [NSRect] = []
    private var contentRect: NSRect = .zero


    // MARK: Lifecycle

    override init(frame frameRect: NSRect) {

        super.init(frame: frameRect)

        self.titleField.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        for field in [self.titleField, self.subtitleField, self.editedField] {
            field.lineBreakMode = .byTruncatingMiddle
            self.addSubview(field)
        }
        self.editedField.toolTip = String(localized: "Document has unsaved changes", table: "Document",
                                          comment: "tooltip for the “edited” indicator in the window tab")

        self.sidebarCell.symbolName = "sidebar.leading"
        self.backCell.symbolName = "chevron.backward"
        self.forwardCell.symbolName = "chevron.forward"
        self.inspectorCell.symbolName = "sidebar.trailing"

        self.backCell.label = String(localized: "Toolbar.documentHistory.back.label",
                                     defaultValue: "Back", table: "Document")
        self.backCell.toolTip = String(localized: "Toolbar.documentHistory.back.tooltip",
                                       defaultValue: "Go to the previous document", table: "Document")
        self.forwardCell.label = String(localized: "Toolbar.documentHistory.forward.label",
                                        defaultValue: "Forward", table: "Document")
        self.forwardCell.toolTip = String(localized: "Toolbar.documentHistory.forward.tooltip",
                                          defaultValue: "Go to the next document", table: "Document")

        for cell in [self.sidebarCell, self.backCell, self.forwardCell, self.runCell, self.inspectorCell] {
            self.addSubview(cell)
        }

        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.toolbar)
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }


    // MARK: View Methods

    override var isFlipped: Bool  { true }

    override var mouseDownCanMoveWindow: Bool  { false }


    override func hitTest(_ point: NSPoint) -> NSView? {

        // the title behaves as the empty bar does, to drag and double-click the window
        guard let view = super.hitTest(point) else { return nil }

        return (view is TopBarCell) ? view : self
    }


    override func layout() {

        super.layout()

        guard let state = self.state else { return }

        let width = self.bounds.width
        let height = self.bounds.height
        let cellWidth = Self.cellWidth
        let columns = self.columnProvider?() ?? Columns(leading: 0, trailing: 0)
        let buttonsEnd = self.windowButtonsExtent

        var lines: [NSRect] = []

        // frames are measured from the leading edge, and mirrored for right-to-left layouts
        func line(at x: CGFloat) {
            lines.append(self.mirrored(NSRect(x: x, y: 0, width: 1, height: height)))
        }
        func place(_ view: NSView, at x: CGFloat) {
            view.frame = self.mirrored(NSRect(x: x, y: 0, width: cellWidth, height: height))
        }

        // the sidebar toggle ends the sidebar’s part, but stays clear of the window buttons
        var contentStart = (columns.leading > 0) ? columns.leading + 1 : buttonsEnd
        if state.sidebar != nil {
            let x = max(columns.leading - cellWidth, buttonsEnd)
            place(self.sidebarCell, at: x)
            if x + cellWidth >= contentStart {
                contentStart = x + cellWidth
                if columns.leading == 0 {
                    if x > 0 { line(at: x - 1) }
                    line(at: contentStart)
                    contentStart += 1
                }
            }
        }
        if columns.leading > 0 {
            line(at: columns.leading)
        }

        if state.history != nil {
            for cell in [self.backCell, self.forwardCell] {
                place(cell, at: contentStart)
                line(at: contentStart + cellWidth)
                contentStart += cellWidth + 1
            }
        }

        // the trailing end
        place(self.inspectorCell, at: width - cellWidth)
        var contentEnd = width - columns.trailing
        if columns.trailing > 0 {
            contentEnd -= 1
            line(at: contentEnd)
        } else {
            contentEnd = width - cellWidth - 1
            line(at: contentEnd)
        }
        contentEnd = min(contentEnd, width - cellWidth)
        place(self.runCell, at: contentEnd - cellWidth)

        // the title
        var x = contentStart + Self.titlePadding
        let titleEnd = contentEnd - cellWidth - Self.titlePadding
        for field in [self.titleField, self.subtitleField, self.editedField] where !field.isHidden {
            let size = field.cell?.cellSize ?? field.intrinsicContentSize
            let fieldWidth = max(min(ceil(size.width), titleEnd - x), 0)
            field.frame = self.mirrored(NSRect(x: x, y: ((height - size.height) / 2).rounded(), width: fieldWidth, height: size.height))
            x += fieldWidth + 6
        }

        let leadingWidth = columns.leading
        let trailingWidth = columns.trailing
        self.columnRects = [NSRect(x: 0, y: 0, width: leadingWidth, height: height),
                            NSRect(x: width - trailingWidth, y: 0, width: trailingWidth, height: height)]
            .map(self.mirrored)
        let bottomStart = (leadingWidth > 0) ? leadingWidth : 0
        let bottomEnd = width - trailingWidth
        lines.append(self.mirrored(NSRect(x: bottomStart, y: height - 1, width: max(bottomEnd - bottomStart, 0), height: 1)))
        self.contentRect = self.bounds
        self.lines = lines
        self.needsDisplay = true
    }


    override func draw(_ dirtyRect: NSRect) {

        let style = self.style

        (style?.background ?? .windowBackgroundColor).setFill()
        self.contentRect.fill()

        (style?.sidebar ?? .underPageBackgroundColor).setFill()
        self.columnRects.forEach { $0.fill() }

        (style?.border ?? .separatorColor).setFill()
        self.lines.forEach { $0.fill() }
    }


    // MARK: Public Methods

    /// Shows the given state.
    func apply(_ state: State) {

        self.state = state

        self.sidebarCell.isHidden = (state.sidebar == nil)
        if let sidebar = state.sidebar {
            self.sidebarCell.isOn = sidebar.isOn
            self.sidebarCell.isEnabled = sidebar.isEnabled
            self.sidebarCell.toolTip = sidebar.toolTip
            self.sidebarCell.label = sidebar.toolTip
        }

        self.backCell.isHidden = (state.history == nil)
        self.forwardCell.isHidden = (state.history == nil)
        self.backCell.isEnabled = state.history?.back ?? false
        self.forwardCell.isEnabled = state.history?.forward ?? false

        self.runCell.symbolName = state.isRunning ? "stop.fill" : "play.fill"
        self.runCell.isEnabled = state.canRun || state.isRunning
        self.runCell.label = state.isRunning
            ? String(localized: "Toolbar.run.label.stop", defaultValue: "Stop", table: "Document", comment: "verb")
            : String(localized: "Toolbar.run.label", defaultValue: "Run", table: "Document", comment: "verb")
        self.runCell.toolTip = state.isRunning
            ? String(localized: "Toolbar.run.tooltip.stop", defaultValue: "Stop the program", table: "Document")
            : String(localized: "Toolbar.run.tooltip", defaultValue: "Save and run the document", table: "Document")

        self.inspectorCell.isOn = state.inspector.isOn
        self.inspectorCell.toolTip = state.inspector.toolTip
        self.inspectorCell.label = state.inspector.toolTip

        self.titleField.stringValue = state.title
        self.subtitleField.stringValue = state.subtitle
        self.subtitleField.isHidden = state.subtitle.isEmpty
        self.editedField.isHidden = !state.isEdited

        self.updateChromeColors()
        self.needsLayout = true
    }


    func updateChromeColors() {

        let style = self.style
        let text = style?.text ?? .labelColor
        let secondaryText = style?.secondaryText ?? .secondaryLabelColor

        self.titleField.textColor = text
        self.subtitleField.textColor = secondaryText
        self.editedField.textColor = secondaryText

        for cell in [self.sidebarCell, self.backCell, self.forwardCell, self.runCell, self.inspectorCell] {
            cell.fillColor = cell.isOn ? (style?.selection ?? .controlAccentColor) : nil
            cell.pressedColor = style?.fill ?? .quaternaryLabelColor
            cell.contentTintColor = if cell.isOn {
                style?.onSelection ?? .alternateSelectedControlTextColor
            } else if !cell.isEnabled {
                secondaryText.withAlphaComponent(0.4)
            } else if cell === self.runCell {
                style?.accent ?? .controlAccentColor
            } else {
                secondaryText
            }
        }

        self.needsDisplay = true
    }


    // MARK: Private Methods

    private var style: ChromeStyle? {

        (self.window as? DocumentWindow)?.chrome?.style
    }


    /// How far the window buttons reach from the leading edge, with a margin; zero when they aren’t shown.
    private var windowButtonsExtent: CGFloat {

        guard
            let window = self.window,
            !window.styleMask.contains(.fullScreen)
        else { return 0 }

        let extents = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
            .map { self.mirrored(self.convert($0.bounds, from: $0)).maxX }

        return extents.max().map { $0 + 12 } ?? 0
    }


    /// Converts a frame between leading-edge coordinates and view coordinates.
    private func mirrored(_ rect: NSRect) -> NSRect {

        guard self.userInterfaceLayoutDirection == .rightToLeft else { return rect }

        var rect = rect
        rect.origin.x = self.bounds.width - rect.maxX

        return rect
    }
}


/// A square button that fills the height of the top bar.
///
/// A cell with a menu also opens it when the user holds the button down.
final class TopBarCell: NSButton {

    var symbolName: String = ""  { didSet { self.updateImage() } }
    var label: String = ""  { didSet { self.cell?.setAccessibilityLabel(label); self.updateImage() } }

    /// Whether the cell stands for something that is shown.
    var isOn = false  { didSet { self.cell?.setAccessibilityValue(isOn ? 1 : 0) } }

    var fillColor: NSColor?  { didSet { self.needsDisplay = true } }
    var pressedColor: NSColor?


    init() {

        super.init(frame: .zero)

        self.isBordered = false
        self.imagePosition = .imageOnly
        self.setButtonType(.momentaryChange)
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")
    }


    // the button’s usual margins would make the fill spill over the lines around the cell
    override var alignmentRectInsets: NSEdgeInsets  { NSEdgeInsets() }

    override var allowsVibrancy: Bool  { false }

    override var mouseDownCanMoveWindow: Bool  { false }


    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {

        true
    }


    override func draw(_ dirtyRect: NSRect) {

        if let color = self.fillColor ?? (self.isHighlighted ? self.pressedColor : nil) {
            color.setFill()
            self.bounds.fill()
        }

        super.draw(dirtyRect)
    }


    override func mouseDown(with event: NSEvent) {

        guard self.menu != nil, self.isEnabled, let window = self.window else { return super.mouseDown(with: event) }

        // click to act, or hold or drag downward to open the menu
        self.highlight(true)
        let deadline = Date(timeIntervalSinceNow: 0.35)
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: deadline, inMode: .eventTracking, dequeue: true) {
            let location = self.convert(next.locationInWindow, from: nil)

            if next.type == .leftMouseUp {
                self.highlight(false)
                if self.bounds.contains(location) {
                    self.sendAction(self.action, to: self.target)
                }
                return
            }
            if location.y > self.bounds.maxY { break }
        }
        self.highlight(false)
        self.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: self.bounds.maxY), in: self)
    }


    private func updateImage() {

        self.image = NSImage(systemSymbolName: self.symbolName, accessibilityDescription: self.label)
    }
}
