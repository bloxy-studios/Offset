//
//  OffsetWidgetsLiveActivity.swift
//  OffsetWidgets
//
//  Created by Abdul Karim Ali on 7/22/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct OffsetWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct OffsetWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OffsetWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension OffsetWidgetsAttributes {
    fileprivate static var preview: OffsetWidgetsAttributes {
        OffsetWidgetsAttributes(name: "World")
    }
}

extension OffsetWidgetsAttributes.ContentState {
    fileprivate static var smiley: OffsetWidgetsAttributes.ContentState {
        OffsetWidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: OffsetWidgetsAttributes.ContentState {
         OffsetWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: OffsetWidgetsAttributes.preview) {
   OffsetWidgetsLiveActivity()
} contentStates: {
    OffsetWidgetsAttributes.ContentState.smiley
    OffsetWidgetsAttributes.ContentState.starEyes
}
