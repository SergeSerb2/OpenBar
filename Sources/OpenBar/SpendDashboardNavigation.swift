import Foundation
import Observation

@MainActor
@Observable
final class SpendDashboardNavigation {
    var userSelectedBackground = false
    var isDataControlsExpanded = true
    var detailSelections: [String: SpendDashboardDetailSection] = [:]
    @ObservationIgnored private var currencies: [String: SpendDashboardCurrencyNavigation] = [:]

    func currency(for id: String) -> SpendDashboardCurrencyNavigation {
        if let navigation = self.currencies[id] { return navigation }
        let navigation = SpendDashboardCurrencyNavigation()
        self.currencies[id] = navigation
        return navigation
    }
}

@MainActor
@Observable
final class SpendDashboardCurrencyNavigation {
    var detailSection: SpendDashboardDetailSection = .providers
    var trendSection: SpendDashboardTrendSection = .daily
    var focusedDay: Date?
    var selectedTrendSourceID: String?
    var focusedInterval: DateInterval?
    var sessionSourceID: String?
    @ObservationIgnored private var sessionBrowsers: [String: SessionUsageBrowserState] = [:]

    func browser(for sourceID: String) -> SessionUsageBrowserState {
        if let state = self.sessionBrowsers[sourceID] { return state }
        let state = SessionUsageBrowserState()
        self.sessionBrowsers[sourceID] = state
        return state
    }
}

@MainActor
@Observable
final class SessionUsageBrowserState {
    var query = ""
    var sort = SessionUsagePresentation.Sort.activity
    var ascending = false
    var selectedSessionID: String?
}
