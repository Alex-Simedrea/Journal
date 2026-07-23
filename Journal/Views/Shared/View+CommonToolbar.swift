//
//  View+CommonToolbar.swift
//  Journal
//
//  Created by Alexandru Simedrea on 12/07/2026.
//

import SwiftUI

struct CommonToolbar: ViewModifier {
    @State private var isAddingPlace = false
    @State private var isAddingPerson = false
    let title: String

    func body(content: Content) -> some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                isAddingPlace = true
                            } label: {
                                Label("New Place", systemImage: "plus")
                            }

                            Button {
                                isAddingPerson = true
                            } label: {
                                Label("New Person", systemImage: "person.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $isAddingPlace) {
                    AddPlaceSheet()
                }
                .sheet(isPresented: $isAddingPerson) {
                    AddPersonSheet()
                }
        }
    }
}

extension View {
    func commonToolbar(title: String) -> some View {
        modifier(CommonToolbar(title: title))
    }
}
