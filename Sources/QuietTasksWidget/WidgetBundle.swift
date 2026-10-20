import SwiftUI
import WidgetKit

@main
struct QuietTasksWidgetBundle: WidgetBundle {
    init() { GroupSharingProbe.runIfRequested(writer: false) }
    var body: some Widget {
        QuietTasksWidget()
    }
}
