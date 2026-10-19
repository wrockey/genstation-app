//
//  CustomDivider.swift


import SwiftUI

struct CustomDivider: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)  // Fixed thin height
            .padding(.vertical, 8) // Full width
    }

    private var dividerColor: Color {
        colorScheme == .light ? Color.gray.opacity(0.3) : Color.white.opacity(0.2)  // Adjust opacity/colors to match your theme
    }
}

