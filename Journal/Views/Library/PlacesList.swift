import SwiftData
import SwiftUI

struct PlacesList: View {
    @Query private var places: [Place]
    @State private var selectedPlace: Place?

    var body: some View {
        List(places) { place in
            Button {
                selectedPlace = place
            } label: {
                PlaceRow(
                    name: place.name,
                    address: place.location.formattedAddress,
                    systemImage: place.systemImage
                )
            }
            .buttonStyle(.plain)
        }
        .sheet(item: $selectedPlace) { place in
            PlaceDetailSheet(place: place)
        }
    }
}

private struct PlaceRow: View {
    let name: String
    let address: String?
    let systemImage: PlaceSystemImage

    var body: some View {
        HStack(spacing: 12) {
            PlaceSymbolImage(systemImage: systemImage)
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)

                if let address {
                    Text(address)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .contentShape(.rect)
    }
}
