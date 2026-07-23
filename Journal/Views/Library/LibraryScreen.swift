//
//  LibraryScreen.swift
//  Journal
//
//  Created by Alexandru Simedrea on 12/07/2026.
//

import SwiftData
import SwiftUI

struct LibraryScreen: View {
    var body: some View {
        List {
            NavigationLink(
                "Places",
                destination: PlacesList()
                    .navigationTitle("Places")
                    .navigationBarTitleDisplayMode(.large)
            )

            NavigationLink(
                "People",
                destination: PeopleList()
                    .navigationTitle("People")
                    .navigationBarTitleDisplayMode(.large)
            )
        }
        .navigationTitle("Library")
        .toolbarTitleDisplayMode(.inlineLarge)
    }
}
