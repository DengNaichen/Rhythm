//
//  AboutView.swift
//  Rhythm
//
//  Created by Naicheng Deng on 2026-03-12.
//

import SwiftUI

struct AboutView: View {
  var body: some View {
    Form {
      LabeledContent("App") {
        Text(Bundle.main.name ?? "Rhythm")
      }

      LabeledContent("Version") {
        Text(Bundle.main.shortVersionString ?? "Unknown")
      }

      if let copyright = Bundle.main.copyright {
        Text(copyright)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("About")
  }
}

#Preview {
  AboutView()
}
