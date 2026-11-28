//
//  DocumentTabs.swift
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

/// The tabs of a window: their order, the selected one, and the preview.
///
/// The preview is a temporary tab that the next preview replaces, until it's kept.
struct DocumentTabs<Item: Equatable> {

    private(set) var items: [Item] = []
    private(set) var selection: Item?
    private(set) var preview: Item?


    /// Selects the tab of the item, adding one if there is none.
    ///
    /// - Parameters:
    ///   - item: The item to show.
    ///   - asPreview: Whether a new tab is a preview. If `false`, an existing preview tab of the item is kept.
    /// - Returns: The preview that the item replaced, which no longer has a tab.
    @discardableResult mutating func open(_ item: Item, asPreview: Bool) -> Item? {

        self.selection = item

        guard !self.items.contains(item) else {
            if !asPreview {
                self.keep(item)
            }
            return nil
        }

        guard asPreview else {
            self.items.append(item)
            return nil
        }

        let replaced = self.preview
        if let replaced, let index = self.items.firstIndex(of: replaced) {
            self.items[index] = item
        } else {
            self.items.append(item)
        }
        self.preview = item

        return replaced
    }


    /// Selects the tab of the item, if it has one.
    mutating func select(_ item: Item) {

        guard self.items.contains(item) else { return }

        self.selection = item
    }


    /// Makes the tab of the item stay open, if it's the preview.
    mutating func keep(_ item: Item) {

        guard self.preview == item else { return }

        self.preview = nil
    }


    /// Puts another item in the tab of an item, as a tab that stays open.
    mutating func replace(_ item: Item, with newItem: Item) {

        guard let index = self.items.firstIndex(of: item) else { return }

        self.items[index] = newItem
        if self.preview == item {
            self.preview = nil
        }
        if self.selection == item {
            self.selection = newItem
        }
    }


    /// Removes the tab of the item.
    ///
    /// If it was selected, the tab that takes its place is selected, or the one before it at the end.
    mutating func close(_ item: Item) {

        guard let index = self.items.firstIndex(of: item) else { return }

        self.items.remove(at: index)
        if self.preview == item {
            self.preview = nil
        }
        if self.selection == item {
            self.selection = self.items.isEmpty ? nil : self.items[min(index, self.items.count - 1)]
        }
    }


    /// Moves the tab of the item to the given position.
    mutating func move(_ item: Item, to destination: Int) {

        guard let index = self.items.firstIndex(of: item) else { return }

        self.items.remove(at: index)
        self.items.insert(item, at: min(max(destination, 0), self.items.count))
    }


    /// Returns the item whose tab is the given number of places after the selected one, going around at the ends.
    func item(offsetFromSelection offset: Int) -> Item? {

        guard
            let selection,
            let index = self.items.firstIndex(of: selection)
        else { return nil }

        let count = self.items.count

        return self.items[((index + offset) % count + count) % count]
    }
}
