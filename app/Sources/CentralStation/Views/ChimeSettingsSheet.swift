import SwiftUI

struct ChimeSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = Notifier.settings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notification Settings")
                .font(.title2.bold())

            Form {
                Toggle("Enable chime", isOn: $settings.enabled)

                if settings.enabled {
                    Picker("Sound", selection: $settings.soundName) {
                        ForEach(ChimeSettings.availableSounds, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .onChange(of: settings.soundName) {
                        Notifier.settings = settings
                        Notifier.previewSound()
                    }

                    HStack {
                        Text("Volume")
                        Slider(value: $settings.volume, in: 0...1, step: 0.1)
                            .onChange(of: settings.volume) {
                                Notifier.settings = settings
                                Notifier.previewSound()
                            }
                        Text("\(Int(settings.volume * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 35, alignment: .trailing)
                    }

                    HStack {
                        Text("Cooldown")
                        Slider(value: $settings.cooldownSeconds, in: 5...120, step: 5)
                        Text("\(Int(settings.cooldownSeconds))s")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 35, alignment: .trailing)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    Notifier.settings = settings
                    settings.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
