import SwiftUI
import WidgetKit

@main
struct CodingStatusLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 17.0, *) {
            CodingStatusLiveActivity()
        }
    }
}
