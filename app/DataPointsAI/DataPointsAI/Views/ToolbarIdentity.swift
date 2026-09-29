import SwiftUI

/// The single customization identity for the main window's toolbar.
///
/// `NavigationSplitView` merges every column's `.toolbar` content into one
/// `NSToolbar` on the window. That toolbar is what AppKit persists a
/// customized layout into, and it can only key that layout on one identifier
/// — so all four columns (sidebar, article list, Library, reader) declare
/// their items under this same id rather than one id each.
///
/// Two rules follow from sharing it, and both are load-bearing:
///
/// 1. **Item ids must be unique across every column**, since they all land in
///    the same namespace. Hence the `sidebar-` / `articles-` / `library-` /
///    `reader-action-` prefixes.
/// 2. **Items must always be present**, disabled when they don't apply, never
///    conditionally rendered. A saved configuration refers to identifiers; if
///    an item is absent on the next launch the layout can't be restored, and
///    AppKit declines to make the toolbar customizable at all.
let mainWindowToolbarID = "datapoints-main-toolbar"
