import SwiftUI

enum WorkspaceLayout {
    static func contentInset(isFocusModeEnabled: Bool) -> CGFloat {
        isFocusModeEnabled ? 72 : 48
    }
}
