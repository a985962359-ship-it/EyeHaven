import StoreKit
import SwiftUI

/// 会员说明与购买。文案只写知识更新 / 好听声音 / 每周报告；不写「解锁全部功能」。
struct MembershipPaywallView: View {
    @Environment(MembershipStore.self) private var membership
    var compact: Bool = false

    var body: some View {
        @Bindable var membership = membership
        VStack(alignment: .leading, spacing: 14) {
            Text("光光知识会员")
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.dusk)

            Text("护眼计时、休息、打卡永远免费。会员只加学习内容。")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.moss)

            benefitRow(icon: "lightbulb.fill", title: "知识连载更新", detail: "为什么、人物、寻宝、安全完整听")
            benefitRow(icon: "waveform", title: "好听的声音", detail: "优先用录好的声音陪听")
            benefitRow(icon: "doc.text.fill", title: "每周家长报告", detail: "一张短报告，方便发给另一半")

            Text("免费可试听每书架前几篇；目录标题都能看。故事书架会多留几篇免费。")
                .font(.caption)
                .foregroundStyle(Palette.pine.opacity(0.7))

            if membership.isMember {
                Label("你已是会员", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.moss)
            } else {
                priceButtons
            }

            Button("恢复购买") {
                Task { await membership.restore() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.pine)

            Text("订阅由苹果账户扣款，可随时在系统「订阅」里取消。取消后当期结束前仍可用。")
                .font(.caption2)
                .foregroundStyle(Palette.pine.opacity(0.55))

            if let msg = membership.statusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Palette.gold)
            }
        }
        .padding(compact ? 0 : 16)
        .task {
            await membership.refresh()
        }
    }

    private var priceButtons: some View {
        VStack(spacing: 10) {
            if let yearly = membership.yearlyProduct {
                Button {
                    Task { await membership.purchase(yearly) }
                } label: {
                    VStack(spacing: 2) {
                        Text("年费 \(yearly.displayPrice)")
                            .font(.headline.weight(.bold))
                        Text("更省 · 约合每月不到 7 元")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(HavenButtonStyle(filled: true))
                .disabled(membership.isLoading)
            }

            if let monthly = membership.monthlyProduct {
                Button {
                    Task { await membership.purchase(monthly) }
                } label: {
                    Text("月费 \(monthly.displayPrice)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(HavenButtonStyle(filled: false))
                .disabled(membership.isLoading)
            }

            if membership.products.isEmpty, !membership.isLoading {
                Text("价格：月费约 9.9 元，年费约 78 元。商品上架后这里可直接购买。")
                    .font(.caption)
                    .foregroundStyle(Palette.pine.opacity(0.65))
            }
        }
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.moss)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Palette.sage.opacity(0.35)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.dusk)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.pine.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.foam.opacity(0.95))
        )
    }
}

struct MembershipPaywallSheet: View {
    @Environment(MembershipStore.self) private var membership
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                MembershipPaywallView()
                    .padding()
            }
            .background(Palette.mist.ignoresSafeArea())
            .navigationTitle("开通会员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onChange(of: membership.isMember) { _, isMember in
            if isMember { dismiss() }
        }
    }
}
