import SwiftUI

struct TerminalTextView: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "Waiting for terminal output..." : text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .id("terminal-bottom")
            }
            .background(Color.black.opacity(0.96))
            .onChange(of: text) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
        }
    }
}
