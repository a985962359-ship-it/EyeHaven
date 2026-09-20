import SwiftUI

struct ParentReportView: View {
    @Environment(ParentSettings.self) private var settings
    @Environment(DailyReport.self) private var report

    var body: some View {
        let today = report.today
        let overAlert = today.skippedRests >= settings.skippedRestAlertCount

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if today.quotaAlertSent {
                    quotaBanner
                }
                if overAlert {
                    alertBanner
                }

                HStack(spacing: 12) {
                    statCard(title: "今日使用", value: "\(today.usedMinutes) 分钟", detail: "上限 \(settings.dailyLimitMinutes) 分钟")
                    statCard(title: "还剩", value: leftoverText, detail: "到点后不能再开始")
                }

                HStack(spacing: 12) {
                    statCard(title: "完成休息", value: "\(today.completedRests) 次", detail: "留在休息页直到结束")
                    statCard(
                        title: "未休息",
                        value: "\(today.skippedRests) 次",
                        detail: overAlert ? "已超过 \(settings.skippedRestAlertCount) 次" : "阈值 \(settings.skippedRestAlertCount) 次"
                    )
                }

                    statCard(title: "测距通过", value: "\(today.distancePasses) 次", detail: settings.requireDistanceCheck ? "每次开始使用前" : "当前未开启测距")

                if !failedCheckIns.isEmpty {
                    Text("打卡失败记录")
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
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.foam))
                    }
                }

                Text("近 7 天")
                    .font(.headline)
                    .foregroundStyle(Palette.dusk)
                    .padding(.top, 8)

                ForEach(report.recentDays) { day in
                    HStack {
                        Text(day.dayKey)
                            .font(.subheadline.monospaced())
                        Spacer()
                        Text("用 \(day.usedMinutes) 分")
                        Text("休 \(day.completedRests)")
                        Text("跳 \(day.skippedRests)")
                            .foregroundStyle(day.skippedRests >= settings.skippedRestAlertCount ? .red : Palette.pine)
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.pine)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.foam))
                }
            }
            .padding(HavenLayout.isPad ? 28 : 16)
            .frame(maxWidth: HavenLayout.pageMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var leftoverText: String {
        let left = report.remainingSeconds(dailyLimitMinutes: settings.dailyLimitMinutes)
        if left <= 0 { return "0 分钟" }
        if left < 60 { return "不到 1 分钟" }
        return "\(left / 60) 分钟"
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
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.foam))
    }
}
