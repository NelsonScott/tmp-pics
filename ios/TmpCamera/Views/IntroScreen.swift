import SwiftUI

/// One screen, shown once on first launch and again from Settings > How it works. No permission asks here:
/// camera access is asked when the camera first opens, Photos access on the first shot.
struct IntroScreen: View {
    @EnvironmentObject private var model: AppModel
    var buttonTitle = "Start"
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 16) {
                    Image("AppMark")
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Tmp")
                        .font(.system(.largeTitle, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: 28) {
                    row("photo.on.rectangle", "Photos you take here go to your \(model.albumName) album.")
                    row("clock", expiryLine)
                    row("lock", "No account, no ads, no network. Open source.")
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onDone) {
                Text(buttonTitle)
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Capsule().fill(Color.brightAccent))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressScale())
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Color(.systemBackground))
            .accessibilityIdentifier("intro-start")
        }
    }

    private var expiryLine: String {
        switch model.lifetime {
        case .never: return "Pick how long they last in Settings. You confirm every delete."
        case .oneHour: return "They expire after an hour. You confirm the delete."
        case .oneDay: return "They expire after a day. You confirm the delete."
        default: return "They expire after \(model.lifetime.label). You confirm the delete."
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(minWidth: 30)
                .accessibilityHidden(true)
            Text(text)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
