import SwiftUI

/// The one-time unlock. No subscription, no ads, no consumables — the pitch is
/// that this is the whole thing, once.
struct PaywallView: View {
    let context: PaywallContext

    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall
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
        .task { await entitlements.loadProduct() }
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
            .disabled(entitlements.purchaseState == .purchasing)

            Text("One purchase. No subscription, no ads.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)

            Button("Restore purchases") {
                Task { await entitlements.restore() }
            }
            .font(.footnote)
            .tint(Theme.indigo)
            .disabled(entitlements.purchaseState == .restoring)

            if case .failed(let message) = entitlements.purchaseState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
                    .multilineTextAlignment(.center)
            }
        }
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
