import SwiftUI

struct ParentReportView: View {
    @Environment(ParentSettings.self) private var settings
    @Environment(DailyReport.self) private var report
    @Environment(MembershipStore.self) private var membership
    @State private var showMembership = false

    var body: some View {
        let today = report.today
        let overAlert = today.skippedRests >= settings.skippedRestAlertCount

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                weeklyReportCard

                if today.quotaAlertSent {
                    quotaBanner
                }
                if overAlert {
                    alertBanner
                }

                HStack(spacing: 12) {
                    statCard(title: "今日使用", value: "\(today.usedSessions) 次", detail: "上限 \(settings.dailyUseLimit) 次")
                    statCard(title: "还剩", value: leftoverText, detail: "次数用完后不能再开始")
                }

                HStack(spacing: 12) {
                    statCard(title: "完成休息", value: "\(today.completedRests) 次", detail: "留在休息页直到结束")
                    statCard(
                        title: "未休息",
                        value: "\(today.skippedRests) 次",
                        detail: overAlert ? "已超过 \(settings.skippedRestAlertCount) 次" : "阈值 \(settings.skippedRestAlertCount) 次"
                    )
                }

                statCard(
                    title: "测距通过",
                    value: "\(today.distancePasses) 次",
                    detail: settings.requireDistanceCheck ? "每次开始使用前" : "当前未开启测距"
                )

                if !failedCheckIns.isEmpty {
                    Text("眼睛休息失败记录")
                        .font(.headline)
                        .foregroundStyle(Palette.dusk)
                        .padding(.top, 8)

                    ForEach(failedCheckIns) { event in
                        HStack(alignment: .top) {
                            Text(event.at, format: .dateTime.hour().minute())
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Palette.pine)
                            Spacer()
                            Text(event.summary)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Palette.foam)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                                )
                        )
                    }
                }

                Text("近 7 天")
                    .font(.headline)
                    .foregroundStyle(Palette.dusk)
                    .padding(.top, 8)

                ForEach(report.recentDays) { day in
                    HStack(spacing: 10) {
                        Text(day.dayKey)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Palette.dusk)
                        Spacer()
                        dayChip("用 \(day.usedSessions)", color: Palette.moss)
                        dayChip("休 \(day.completedRests)", color: Palette.pine)
                        dayChip(
                            "跳 \(day.skippedRests)",
                            color: day.skippedRests >= settings.skippedRestAlertCount
                                ? Color(red: 0.75, green: 0.3, blue: 0.2)
                                : Palette.pine.opacity(0.55)
                        )
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Palette.foam)
                    )
                }
            }
            .padding(HavenLayout.isPad ? 28 : 16)
            .frame(maxWidth: HavenLayout.pageMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showMembership) {
            MembershipPaywallSheet()
                .environment(membership)
        }
    }

    /// 本周短报告：护眼数据免费看；分享在收费开启后作为会员权益。
    private var weeklyReportCard: some View {
        let text = report.weeklySummaryText(
            dailyUseLimit: settings.dailyUseLimit,
            alertAfter: settings.skippedRestAlertCount
        )
        let canShare = membership.isMember || !membership.billingReady

        return VStack(alignment: .leading, spacing: 10) {
            Text("本周短报告")
                .font(.headline)
                .foregroundStyle(Palette.dusk)
            Text("一张短文，方便发给另一半。护眼计时本身永远免费。")
                .font(.caption)
                .foregroundStyle(Palette.pine.opacity(0.7))

            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.pine)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.foam))

            if canShare {
                ShareLink(item: text) {
                    Label("分享给家人", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(HavenButtonStyle(filled: true))
            } else {
                Button {
                    showMembership = true
                } label: {
                    Text("开通会员后可一键分享（会员含知识更新与好听声音）")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(HavenButtonStyle(filled: false))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.sage.opacity(0.35))
        )
    }

    private var leftoverText: String {
        let left = report.remainingUses(dailyUseLimit: settings.dailyUseLimit)
        return "\(left) 次"
    }

    private var failedCheckIns: [CheckInEvent] {
        report.todaysCheckIns.filter { !$0.succeeded }
    }

    private var quotaBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.fill")
            Text("今天额度已用完，使用报告已通知家长。")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(Palette.foam)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.pine))
    }

    private var alertBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("孩子今天多次没有完成休息，请看看使用习惯。")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.orange.opacity(0.9)))
    }

    private func dayChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func statCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.pine.opacity(0.7))
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.dusk)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(Palette.moss)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.foam)
                .shadow(color: Palette.pine.opacity(0.05), radius: 4, y: 2)
        )
    }
}
