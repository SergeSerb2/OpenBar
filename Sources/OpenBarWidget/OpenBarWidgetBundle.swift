import SwiftUI
import WidgetKit

@main
struct OpenBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        OpenBarSwitcherWidget()
        OpenBarUsageWidget()
        OpenBarHistoryWidget()
        OpenBarCompactWidget()
        OpenBarBurnDownWidget()
        OpenBarCombinedBurnDownWidget()
        OpenBarAccountUsageWidget()
        OpenBarAccountsWidget()
    }
}

struct OpenBarSwitcherWidget: Widget {
    private let kind = "OpenBarSwitcherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: self.kind,
            provider: OpenBarSwitcherTimelineProvider())
        { entry in
            OpenBarSwitcherWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("OpenBar Switcher")))
        .description(Text(W("Usage widget with a provider switcher.")))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct OpenBarUsageWidget: Widget {
    private let kind = "OpenBarUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: OpenBarTimelineProvider())
        { entry in
            OpenBarUsageWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("OpenBar Usage")))
        .description(Text(W("Session and weekly usage with credits and costs.")))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct OpenBarHistoryWidget: Widget {
    private let kind = "OpenBarHistoryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: OpenBarTimelineProvider(payload: .history))
        { entry in
            OpenBarHistoryWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("OpenBar History")))
        .description(Text(W("Usage history chart with recent totals.")))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct OpenBarCompactWidget: Widget {
    private let kind = "OpenBarCompactWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: CompactMetricSelectionIntent.self,
            provider: OpenBarCompactTimelineProvider())
        { entry in
            OpenBarCompactWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("OpenBar Metric")))
        .description(Text(W("Compact widget for credits or cost.")))
        .supportedFamilies([.systemSmall])
    }
}

enum BurnDownWidgetBackgroundConfiguration {
    static let isRemovable = true
}

struct OpenBarBurnDownWidget: Widget {
    private let kind = "OpenBarBurnDownWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: BurnDownSelectionIntent.self,
            provider: BurnDownTimelineProvider())
        { entry in
            BurnDownWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("OpenBar Burn Down")))
        .description(Text(W("Remaining budget compared with an ideal steady burn rate.")))
        .supportedFamilies([.systemMedium])
        .containerBackgroundRemovable(BurnDownWidgetBackgroundConfiguration.isRemovable)
    }
}

struct OpenBarCombinedBurnDownWidget: Widget {
    private let kind = "OpenBarCombinedBurnDownWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: BurnProviderSelectionIntent.self,
            provider: CombinedBurnDownTimelineProvider())
        { entry in
            CombinedBurnDownWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("OpenBar Burn Down (Combined)")))
        .description(Text(W("Two quota burn-down charts in one tile.")))
        .supportedFamilies([.systemMedium])
        .containerBackgroundRemovable(BurnDownWidgetBackgroundConfiguration.isRemovable)
    }
}
