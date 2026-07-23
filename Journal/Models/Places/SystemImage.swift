//
//  PlaceSystemImage.swift
//  Journal
//

import AnyLanguageModel

@Generable(description: "An SF Symbol supported by the Journal place picker")
enum PlaceSystemImage: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case mappin
    case house = "house.fill"
    case buildings = "building.2.fill"
    case civicBuilding = "building.columns.fill"
    case storefront = "storefront.fill"
    case cart = "cart.fill"
    case bag = "bag.fill"
    case dining = "fork.knife"
    case cafe = "cup.and.saucer.fill"
    case bar = "wineglass.fill"
    case cake = "birthday.cake.fill"
    case hotel = "bed.double.fill"
    case medical = "cross.case.fill"
    case pharmacy = "pills.fill"
    case stethoscope
    case school = "graduationcap.fill"
    case library = "book.fill"
    case work = "briefcase.fill"
    case computer = "desktopcomputer"
    case walking = "figure.walk"
    case running = "figure.run"
    case gym = "dumbbell.fill"
    case sports = "sportscourt.fill"
    case soccer = "soccerball"
    case basketball = "basketball.fill"
    case nature = "leaf.fill"
    case park = "tree.fill"
    case mountain = "mountain.2.fill"
    case beach = "beach.umbrella.fill"
    case camping = "tent.fill"
    case water = "water.waves"
    case airport = "airplane"
    case car = "car.fill"
    case bus = "bus.fill"
    case tram = "tram.fill"
    case ferry = "ferry.fill"
    case cycling = "bicycle"
    case gasStation = "fuelpump.fill"
    case parking = "parkingsign.circle.fill"
    case camera = "camera.fill"
    case music = "music.note"
    case theater = "theatermasks.fill"
    case ticket = "ticket.fill"
    case gaming = "gamecontroller.fill"
    case pets = "pawprint.fill"
    case heart = "heart.fill"
    case star = "star.fill"
    case people = "person.2.fill"

    var id: String { rawValue }
}
