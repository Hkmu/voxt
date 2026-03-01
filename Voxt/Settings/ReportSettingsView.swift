import SwiftUI

struct ReportSettingsView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var historyStore: TranscriptionHistoryStore

    private let cardColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: cardColumns, spacing: 12) {
                metricCard(
                    iconName: "clock.badge.checkmark",
                    titleKey: "Total Dictation Time",
                    value: formattedDuration(summary.totalDictationSeconds)
                )
                metricCard(
                    iconName: "character.textbox",
                    titleKey: "Total Dictation Characters",
                    value: localizedNumber(summary.totalCharacters),
                    unitKey: "chars"
                )
                metricCard(
                    iconName: "globe",
                    titleKey: "Total Translation Characters",
                    value: localizedNumber(summary.totalTranslationCharacters),
                    unitKey: "chars"
                )
                metricCard(
                    iconName: "speedometer",
                    titleKey: "Average Dictation Speed",
                    value: localizedNumber(Int(summary.averageCharactersPerMinute)),
                    unitKey: "char/min"
                )
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Daily Characters (Last 7 Days)")
                        .font(.headline)

                    SevenDayBarChart(data: summary.dailyCharacters)
                        .frame(height: 240)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summary: ReportSummary {
        ReportSummary(entries: historyStore.allHistoryEntries, locale: locale)
    }

    @ViewBuilder
    private func metricCard(
        iconName: String,
        titleKey: LocalizedStringKey,
        value: String,
        unitKey: LocalizedStringKey? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(titleKey)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let unitKey {
                    Text(unitKey)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainSeconds = totalSeconds % 60
        if hours > 0 {
            let format = NSLocalizedString("%dh %dm", comment: "")
            return String(format: format, locale: locale, hours, minutes)
        }
        if minutes > 0 {
            let format = NSLocalizedString("%dm %ds", comment: "")
            return String(format: format, locale: locale, minutes, remainSeconds)
        }
        let format = NSLocalizedString("%d s", comment: "")
        return String(format: format, locale: locale, remainSeconds)
    }

    private func localizedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct SevenDayBarChart: View {
    struct DayValue: Identifiable {
        let dayStart: Date
        let label: String
        let value: Int

        var id: Date { dayStart }
    }

    let data: [DayValue]

    var body: some View {
        let maxValue = max(data.map(\.value).max() ?? 0, 1)
        let chartHeight: CGFloat = 150

        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(data) { item in
                    let minBarHeight: CGFloat = item.value > 0 ? 6 : 2
                    let scaledHeight = CGFloat(item.value) / CGFloat(maxValue) * chartHeight
                    let barHeight = max(minBarHeight, scaledHeight)

                    VStack(spacing: 6) {
                        Text("\(item.value)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: barHeight)

                        Text(item.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct ReportSummary {
    let totalDictationSeconds: TimeInterval
    let totalCharacters: Int
    let totalTranslationCharacters: Int
    let averageCharactersPerMinute: Double
    let dailyCharacters: [SevenDayBarChart.DayValue]

    init(entries: [TranscriptionHistoryEntry], locale: Locale) {
        totalDictationSeconds = entries.reduce(0) { $0 + ($1.audioDurationSeconds ?? 0) }
        totalCharacters = entries.reduce(0) { $0 + $1.text.count }
        totalTranslationCharacters = entries
            .filter(\.isTranslation)
            .reduce(0) { $0 + $1.text.count }

        if totalDictationSeconds > 0 {
            averageCharactersPerMinute = Double(totalCharacters) / (totalDictationSeconds / 60.0)
        } else {
            averageCharactersPerMinute = 0
        }

        dailyCharacters = Self.computeDailyCharacters(entries: entries, locale: locale)
    }

    private static func computeDailyCharacters(entries: [TranscriptionHistoryEntry], locale: Locale) -> [SevenDayBarChart.DayValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.date(byAdding: .day, value: -6, to: today) ?? today

        var daily: [Date: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            guard day >= startDay, day <= today else { continue }
            daily[day, default: 0] += entry.text.count
        }

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                return nil
            }
            return SevenDayBarChart.DayValue(
                dayStart: day,
                label: day.formatted(.dateTime.weekday(.abbreviated).locale(locale)),
                value: daily[day, default: 0]
            )
        }
    }
}
