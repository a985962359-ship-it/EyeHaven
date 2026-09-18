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

            SecureField("4 位数字", text: $pin)
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
            .disabled(pin.count != 4)
        }
        .padding(28)
    }

    private func submitPIN() {
        let trimmed = String(pin.filter(\.isNumber).prefix(4))
        guard trimmed.count == 4 else { return }

        if settings.hasPIN {
            if settings.matchesPIN(trimmed) {
                pinError = false
                unlocked = true
                ParentNotifier.requestPermission()
            } else {
                pinError = true
            }
        } else {
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

            Section("多休息奖励") {
                Toggle("多休息可增加下次使用时间", isOn: $settings.rewardExtraRest)
                Text("打开后，最少休息结束后再多休息 \(ExtraRestReward.extraMinutes) 分钟，下次使用时间增加 \(ExtraRestReward.nextUseMinutes) 分钟。关掉则不奖励。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("眼睛到屏幕的距离") {
                Toggle("开始前测一次距离", isOn: $settings.requireDistanceCheck)
                if settings.requireDistanceCheck {
                    Stepper(value: $settings.minimumDistanceCm, in: 30...80, step: 5) {
                        Text("至少 \(settings.minimumDistanceCm) 厘米才可以开始")
                    }
                    Text("只在点开始时测一次，不持续开摄像头。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("未休息提醒") {
                Stepper(value: $settings.skippedRestAlertCount, in: 1...10, step: 1) {
                    Text("未休息 \(settings.skippedRestAlertCount) 次后再加一次提醒")
                }
                Text("每次打卡失败都会在本机弹出家长通知，并写进「家长 → 报告」。达到设定次数会再发一条汇总。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    ParentAreaView()
        .environment(ParentSettings())
        .environment(DailyReport())
}
