//
//  File.swift
//  Babymonitor
//
//  Created by Krijn Haasnoot on 26/03/2025.
//

import SwiftUI

struct ConnectionIndicator: View {
    var isConnected: Bool
    var isConnecting: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))

            if isConnecting {
                Text("Connecting...")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.top, 10)
        .padding(.trailing, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isConnected ? "Connected" : (isConnecting ? "Connecting" : "Disconnected"))
    }
}
