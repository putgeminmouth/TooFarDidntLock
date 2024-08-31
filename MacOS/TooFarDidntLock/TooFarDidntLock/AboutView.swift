import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct AboutView: View {
    let logger = Log.Logger("AboutView")
    var body: some View {
        VStack {
            Image("AboutImage")
                .resizable()
                .scaledToFit()
                .frame(width: 500, height: 500)
            Text("Too Far; Didn't Lock")
            Text("[Github](https://github.com/putgeminmouth/toofardidntlock)")
        }
            .padding(20)
    }
}
