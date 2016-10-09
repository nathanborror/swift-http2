//
//  SwiftHttp2/Sources/Frames.swift - HTTP/2 Library
//
//  This source file is part of the SwiftHttp2 open source project
//  https://github.com/nathanborror/swift-http2
//  Created by Nathan Borror on 10/1/16.
//

import Foundation
import hpack

public enum FrameType: UInt8 {
    case data           = 0x0
    case headers        = 0x1
    case priority       = 0x2
    case rstStream      = 0x3
    case settings       = 0x4
    case pushPromise    = 0x5
    case ping           = 0x6
    case goaway         = 0x7
    case windowUpdate   = 0x8
    case continuation   = 0x9
}

public typealias FrameFlag = UInt8
extension FrameFlag {
    public static let endStream:    FrameFlag = 0x1
    public static let settingsAck:  FrameFlag = 0x1
    public static let pingAck:      FrameFlag = 0x1
    public static let endHeaders:   FrameFlag = 0x4
    public static let streamClosed: FrameFlag = 0x5
    public static let padded:       FrameFlag = 0x8
    public static let priority:     FrameFlag = 0x20
}

public struct Frame {
    public let type:    FrameType
    public let stream:  StreamID
    public let flags:   FrameFlag
    public let length:  Int
    public var payload: [UInt8]?

    public init(type: FrameType, stream: StreamID = 0, flags: FrameFlag = 0, length: Int = 0, payload: [UInt8]? = nil) {
        self.type = type
        self.stream = stream
        self.flags = flags
        self.length = length
        self.payload = payload
    }

    public init(headers: [(String, String)], stream: StreamID = 0, flags: FrameFlag = 0) {
        self.type = .headers
        self.stream = stream
        self.flags = flags

        let encoder = hpack.Encoder()
        let payload = encoder.encode(headers)

        self.payload = payload
        self.length = payload.count
    }

    public init(data: [UInt8], stream: StreamID = 0, flags: FrameFlag = 0) {
        self.type = .data
        self.stream = stream
        self.flags = flags
        self.payload = data
        self.length = data.count
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count >= 9 else { return nil }
        let length = (UInt32(bytes[0]) << 16) + (UInt32(bytes[1]) << 8) + UInt32(bytes[2])
        self.length = Int(length)
        guard let type = FrameType(rawValue: bytes[3]) else {
            return nil
        }
        self.type = type
        self.flags = bytes[4]
        var stream = UInt32(bytes[5])
        stream <<= 8
        stream += UInt32(bytes[6])
        stream <<= 8
        stream += UInt32(bytes[7])
        stream <<= 8
        stream += UInt32(bytes[8])
        stream &= ~0x80000000
        self.stream = Int(stream)
        self.payload = nil
    }

    public func bytes() -> [UInt8] {
        var data = [UInt8]()

        let l = htonl(UInt32(self.length)) >> 8
        data.append(UInt8(l & 0xFF))
        data.append(UInt8((l >> 8) & 0xFF))
        data.append(UInt8((l >> 16) & 0xFF))

        data.append(self.type.rawValue)
        data.append(self.flags)

        let s = htonl(UInt32(self.stream))
        data.append(UInt8(s & 0xFF))
        data.append(UInt8((s >> 8) & 0xFF))
        data.append(UInt8((s >> 16) & 0xFF))
        data.append(UInt8((s >> 24) & 0xFF))
        return data
    }
}
