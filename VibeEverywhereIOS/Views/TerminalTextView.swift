import SwiftUI

struct TerminalTextView: View {
    let text: String
    let placeholder: String
    let compact: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? placeholder : text)
                    .font(.system(compact ? .caption : .footnote, design: .monospaced))
                    .foregroundStyle(compact ? Color(red: 0.79, green: 0.88, blue: 0.7) : Color(red: 0.88, green: 0.95, blue: 0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(compact ? 10 : 14)
                    .background(Color.black.opacity(compact ? 0.84 : 0.92))
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 20))
                    .id("terminal-bottom")
            }
            .background(Color.black.opacity(compact ? 0.8 : 0.96))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 20))
            .onChange(of: text) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
        }
    }
}
