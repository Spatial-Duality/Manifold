import SwiftUI

struct PlainTextEmailView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
