import SwiftUI

/// Consistent spacing scale used across all views.
/// Base-4 scale inspired by Things 3 and Raycast.
enum Spacing {
    /// 4pt — tight inline spacing (icon-to-text gaps)
    static let tight: CGFloat = 4
    /// 8pt — standard list row internal padding
    static let standard: CGFloat = 8
    /// 12pt — section spacing within a view
    static let section: CGFloat = 12
    /// 16pt — standard view edge padding
    static let edge: CGFloat = 16
    /// 24pt — section separation, onboarding elements
    static let large: CGFloat = 24
    /// 32pt — large separation between major sections
    static let xlarge: CGFloat = 32
}
