import SwiftUI

/// The one-time unlock. No subscription, no ads, no consumables — the pitch is
/// that this is the whole thing, once.
struct PaywallView: View {
    let context: PaywallContext

    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                featureList
                purchaseControls
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .presentationBackground(Theme.paper)
        .task {
            // A failure raised on another screen must not greet the player here.
            entitlements.clearTransientState()
            await entitlements.loadProduct()
        }
        .onChange(of: entitlements.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.feature.headline)
                .font(Theme.heading)
                .foregroundStyle(Theme.ink)
            Text(context.feature.pitch)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The full game includes")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)
            ForEach(PaidFeature.allCases) { feature in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.complete)
                    Text(feature.headline)
                        .font(.subheadline)
                        .foregroundStyle(feature == context.feature ? Theme.ink : Theme.inkSoft)
                        .fontWeight(feature == context.feature ? .semibold : .regular)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }

    private var purchaseControls: some View {
        VStack(spacing: 12) {
            Button {
                Task { await entitlements.purchase() }
            } label: {
                HStack {
                    if entitlements.purchaseState == .purchasing {
                        ProgressView().tint(.white)
                    } else {
                        // Never hardcode the price — App Review rejects a button
                        // that disagrees with the product's real localized price.
                        Text(entitlements.product.map { "Unlock everything · \($0.displayPrice)" }
                             ?? "Unlock everything")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.indigo))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            // Both controls key off the same flag, so a purchase and a restore
            // can never be started on top of each other.
            .disabled(entitlements.purchaseState.isBusy)

            Text("One purchase. No subscription, no ads.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)

            Button {
                Task { await entitlements.restore() }
            } label: {
                HStack(spacing: 6) {
                    if entitlements.purchaseState == .restoring {
                        ProgressView().controlSize(.small)
                    }
                    Text(entitlements.purchaseState == .restoring
                         ? "Checking with the App Store…" : "Restore purchases")
                }
                .font(.footnote)
                .foregroundStyle(Theme.indigo)
            }
            .buttonStyle(.plain)
            .disabled(entitlements.purchaseState.isBusy)

            statusLine
        }
    }

    /// One place for everything the store has to say, so a waiting state, a
    /// neutral note and a failure cannot each invent their own layout.
    @ViewBuilder
    private var statusLine: some View {
        switch entitlements.purchaseState {
        case .awaitingApproval:
            message("Sent for approval. The full game unlocks by itself once it is approved, "
                    + "and you can keep playing in the meantime.", color: Theme.ink)
        case .note(let text):
            message(text, color: Theme.inkSoft)
        case .failed(let text):
            message(text, color: Theme.error)
        default:
            EmptyView()
        }
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Empty state for a screen that is wholly behind the unlock.
struct LockedFeatureView: View {
    let feature: PaidFeature
    @Environment(PaywallPresenter.self) private var paywall

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.indigo)
                Text(feature.headline)
                    .font(Theme.heading)
                    .foregroundStyle(Theme.ink)
                Text(feature.pitch)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                Button("Unlock everything") {
                    paywall.present(feature)
                }
                .font(.headline)
                .tint(Theme.indigo)
                .padding(.top, 4)
            }
            .padding(32)
            .frame(maxWidth: 420)
        }
    }
}
