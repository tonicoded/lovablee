//
//  LovableeWidgetLiveActivity.swift
//  LovableeWidget
//
//  Created by Anthony Verruijt on 02/12/2025.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LovableeWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct LovableeWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LovableeWidgetAttributes.self) { context in
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

extension LovableeWidgetAttributes {
    fileprivate static var preview: LovableeWidgetAttributes {
        LovableeWidgetAttributes(name: "World")
    }
}

extension LovableeWidgetAttributes.ContentState {
    fileprivate static var smiley: LovableeWidgetAttributes.ContentState {
        LovableeWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: LovableeWidgetAttributes.ContentState {
         LovableeWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: LovableeWidgetAttributes.preview) {
   LovableeWidgetLiveActivity()
} contentStates: {
    LovableeWidgetAttributes.ContentState.smiley
    LovableeWidgetAttributes.ContentState.starEyes
}
