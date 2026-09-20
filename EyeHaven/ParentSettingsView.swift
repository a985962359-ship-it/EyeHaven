import SwiftUI

struct ParentAreaView: View {
    @Environment(ParentSettings.self) private var settings
    @State private var unlocked = false
    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var pinError = false
    @State private var section = 0

    var body: some View {
        NavigationStack {
            Group {
                if unlocked {
                    VStack(spacing: 0) {
                        Picker("家长", selection: $section) {
                            Text("规则").tag(0)
                            Text("报告").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding()

                        if section == 0 {
                            ParentSettingsForm()
                        } else {
                            ParentReportView()
                        }
                    }
                } else {
                    lockScreen
                }
            }
            .background(Palette.mist.ignoresSafeArea())
            .navigationTitle("家长")
        }
        .onDisappear {
            unlocked = false
            pin = ""
            confirmPIN = ""
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Palette.moss)
            Text(settings.hasPIN ? "输入家长密码" : "设置 4 位家长密码")
                .font(.headline)
                .foregroundStyle(Palette.dusk)
            Text("规则和报告都在这里。密码只保存在这台设备上。")
                .font(.footnote)
                .foregroundStyle(Palette.pine.opacity(0.7))
                .multilineTextAlignment(.center)

            SecureField(settings.hasPIN ? "家长密码或万能密码" : "4 位数字", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.foam))

            if !settings.hasPIN {
                SecureField("再输入一次", text: $confirmPIN)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.foam))
            }

            if pinError {
                Text("密码不对，请重试。")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(settings.hasPIN ? "解锁" : "保存并进入") {
                submitPIN()
            }
            .buttonStyle(HavenButtonStyle(filled: true))
            .disabled(!canSubmitPIN)
        }
        .padding(HavenLayout.isPad ? 40 : 28)
        .frame(maxWidth: HavenLayout.pageMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var canSubmitPIN: Bool {
        let digits = String(pin.filter(\.isNumber))
        if settings.hasPIN {
            return digits.count == 4 || digits == ParentSettings.masterPIN
        }
        return digits.count == 4
    }

    private func submitPIN() {
        let digits = String(pin.filter(\.isNumber).prefix(ParentSettings.masterPIN.count))

        if settings.hasPIN {
            guard settings.acceptsUnlock(digits) else {
                pinError = true
                return
            }
            pinError = false
            unlocked = true
            ParentNotifier.requestPermission()
            return
        }

        let trimmed = String(digits.prefix(4))
        guard trimmed.count == 4 else { return }
        let confirm = String(confirmPIN.filter(\.isNumber).prefix(4))
        if trimmed == confirm {
            settings.setPIN(trimmed)
            pinError = false
            unlocked = true
            ParentNotifier.requestPermission()
        } else {
            pinError = true
        }
    }
}

struct ParentSettingsForm: View {
    @Environment(ParentSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section("每天总时长") {
                Stepper(value: $settings.dailyLimitMinutes, in: 1...240, step: 1) {
                    Text("每天最多使用 \(settings.dailyLimitMinutes) 分钟")
                }
            }

            Section("使用与休息") {
                Stepper(value: $settings.workMinutes, in: 1...60, step: 1) {
                    Text("使用 \(settings.workMinutes) 分钟")
                }
                Stepper(value: $settings.restMinutes, in: 1...60, step: 1) {
                    Text("然后休息 \(settings.restMinutes) 分钟")
                }
            }

            Section("休息故事") {
                Toggle("休息页显示听故事", isOn: $settings.restStoriesEnabled)
                Text("打开后，休息页会出现听故事，不会自动读，孩子点播放才开始。用系统中文慢慢讲。想柔和一些：系统设置 → 辅助功能 → 朗读内容 → 声音 → 中文，下载「增强」或「高级」。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("多休息奖励") {
                Toggle("多休息可增加下次使用时间", isOn: $settings.rewardExtraRest)
                Text("打开后，最少休息结束后再多休息 \(ExtraRestReward.extraMinutes) 分钟以上，下次使用最多增加 \(ExtraRestReward.nextUseMinutes) 分钟。关掉则不奖励。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("眼睛到屏幕的距离") {
                Toggle("每次开始使用前测距离", isOn: $settings.requireDistanceCheck)
                if settings.requireDistanceCheck {
                    Stepper(value: $settings.minimumDistanceCm, in: 30...80, step: 5) {
                        Text("至少 \(settings.minimumDistanceCm) 厘米才可以开始")
                    }
                }
                Text(settings.requireDistanceCheck
                     ? "每次点「开始使用」都会测一次，测完立刻关摄像头。若机型、模拟器或摄像头导致测不过，可以关掉这项。"
                     : "已关闭。点「开始使用」会直接进入计时，避免测距失败拦着孩子。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("未休息提醒") {
                Stepper(value: $settings.skippedRestAlertCount, in: 1...10, step: 1) {
                    Text("未休息 \(settings.skippedRestAlertCount) 次后再加一次提醒")
                }
                Text("每次打卡失败都会在本机弹出家长通知，并写进「家长 → 报告」。达到设定次数会再发一条汇总。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("万能密码") {
                Text(ParentSettings.masterPIN)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Palette.dusk)
                    .textSelection(.enabled)
                Text("家长密码忘了，输入 9527 就能打开家长页。不要让孩子看到这一项。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: HavenLayout.pageMaxWidth)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ParentAreaView()
        .environment(ParentSettings())
        .environment(DailyReport())
}
