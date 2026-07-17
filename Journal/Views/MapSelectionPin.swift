//
//  MapSelectionPin.swift
//  Journal
//

import SwiftUI

struct MapSelectionPin: View {
    var body: some View {
        ZStack(alignment: .top) {
            MapPinTail()
                .fill(.white)
                .frame(width: 9, height: 8)
                .offset(y: 42)

            Circle()
                .fill(.white)
                .frame(width: 45, height: 45)

            Circle()
                .fill(.pink.gradient)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "mappin")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(y: 3.5)
        }
        .frame(width: 45, height: 51)
        .compositingGroup()
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

private struct MapPinTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.width * 0.3, y: rect.height * 0.75)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.width * 0.7, y: rect.height * 0.75)
        )
        path.closeSubpath()
        return path
    }
}
