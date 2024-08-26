import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct AboutView: View {
    let logger = Log.Logger("AboutView")
    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        VStack {
            Image("AboutImage")
                .resizable()
                .scaledToFit()
                .frame(width: 500, height: 500)
            Text("Too Far; Didn't Lock")
            Text("Version \(version ?? "unknown")")
            Text("[Github](https://github.com/putgeminmouth/toofardidntlock)")
        }
        .frame(width: 500, height: 570)
    }
}
