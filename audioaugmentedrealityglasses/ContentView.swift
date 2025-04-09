//
//  ContentView.swift
//  audioaugmentedrealityglasses
//
//  Created by Customer on 3/25/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject var bleReceiver = BLEImageReceiver()
    
    var body: some View {
        VStack {
            if let image = bleReceiver.receivedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
            } else {
                Text("Waiting for some image...")
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
