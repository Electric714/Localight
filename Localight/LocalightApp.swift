//
//  LocalightApp.swift
//  Localight
//
//  Created by Timo Köthe on 06.07.25.
//

import SwiftUI

@main
struct LocalightApp: App {
    var body: some Scene {
        WindowGroup {
            if #available(iOS 27.0, *) {
                ContentView_27()
            } else {
                // Fallback for iOS 26 (ContentView_26 was removed)
                // You can put a simple fallback view here if needed
                Text("This app requires iOS 27 or later")
            }
        }
    }
}
