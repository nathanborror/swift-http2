//
//  SwiftHttp2/Sources/Streams.swift - HTTP/2 Library
//
//  This source file is part of the SwiftHttp2 open source project
//  https://github.com/nathanborror/swift-http2
//  Created by Nathan Borror on 10/1/16.
//

import Foundation

enum StreamState {
    case none
    case idle
    case reservedLocal
    case reservedRemote
    case open
    case halfClosedRemote
    case halfClosedLocal
    case closed
}

public typealias StreamID = Int

public struct StreamCache {

    var streams = [Int: StreamState]()
    var counter = 1

    public mutating func next() -> StreamID {
        streams[counter] = .none
        let s = counter
        counter += 2
        return s
    }
}
