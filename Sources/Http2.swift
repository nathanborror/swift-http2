//
//  SwiftHttp2/Sources/Http2.swift - HTTP/2 Library
//
//  This source file is part of the SwiftHttp2 open source project
//  https://github.com/nathanborror/swift-http2
//  Created by Nathan Borror on 10/1/16.
//

import Foundation

public protocol Http2SessionDelegate: class {

    func sessionConnected(session: Http2Session)
    func session(session: Http2Session, hasFrame frame: Frame)
}

public enum Http2SessionError: Error {

    case missingInput
    case missingOutput
    case connectionTimeout
}

public enum Http2Error: Error {
    case none
    case protocol_
    case internal_
    case flowControl
    case settingsTimeout
    case streamClosed
    case frameSize
    case refusedStream
    case cancel
    case compression
    case connect
    case enhanceYourCalm
    case inadequateSecurity
    case http1_1Required

    init?(hex: UInt8) {
        switch hex {
        case 0x1: self = .protocol_
        case 0x2: self = .internal_
        case 0x3: self = .flowControl
        case 0x4: self = .settingsTimeout
        case 0x5: self = .streamClosed
        case 0x6: self = .frameSize
        case 0x7: self = .refusedStream
        case 0x8: self = .cancel
        case 0x9: self = .compression
        case 0xa: self = .connect
        case 0xb: self = .enhanceYourCalm
        case 0xc: self = .inadequateSecurity
        case 0xd: self = .http1_1Required
        default:  return nil
        }
    }
}

public enum Http2SessionState {
    case disconnected
    case connecting
    case connected
    case ready
}

public class Http2Session: NSObject {

    let url: URL

    public var delegate: Http2SessionDelegate?

    var inputStream: InputStream?
    var outputStream: OutputStream?

    var state: Http2SessionState = .disconnected {
        didSet { handleStateChange(previous: oldValue) }
    }

    var isCertValidated = false

    private var inputQueue: [UInt8]
    private let writeQueue: OperationQueue
    private var fragBuffer: Data?

    private static let sharedQueue = DispatchQueue(label: "org.swift.http2.session", attributes: [])

    public var streams: StreamCache

    public init(url: URL) {
        self.url = url
        self.writeQueue = OperationQueue()
        self.writeQueue.maxConcurrentOperationCount = 1
        self.inputQueue = []
        self.streams = StreamCache()
    }

    func handleStateChange(previous: Http2SessionState) {
        if state == .connected {
            writeHandshake()
        }
    }

    public func connect() {
        guard state == .disconnected else { return }
        state = .connecting
        makeConnection()
    }

    func makeConnection() {
        guard let req = makeRequest() else {
            print("HTTP/2 connection attempt failed")
            return
        }
        makeStreams(with: req)
    }

    func makeRequest() -> Data? {
        let req = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true).takeRetainedValue()

        CFHTTPMessageAppendBytes(req, prism, prism.count)

        // TODO: Figure out how to get rid of the above without having
        // CFHTTPMessageCopySerializedMessage returning nil.

        guard let cfData = CFHTTPMessageCopySerializedMessage(req) else {
            print("CFHTTPMessageCopySerializedMessage returned nil")
            return nil
        }
        return cfData.takeRetainedValue() as Data
    }

    func makeStreams(with request: Data) {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        guard let host = url.host,
            let port = url.port else { fatalError() }

        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)

        inputStream = readStream!.takeRetainedValue()
        outputStream = writeStream!.takeRetainedValue()

        guard let input = inputStream,
            let output = outputStream else { fatalError() }

        input.delegate = self
        output.delegate = self

        if let scheme = url.scheme, scheme == "https" {
            input.setProperty(StreamSocketSecurityLevel.negotiatedSSL.rawValue,
                              forKey: Stream.PropertyKey.socketSecurityLevelKey)
            output.setProperty(StreamSocketSecurityLevel.negotiatedSSL.rawValue,
                               forKey: Stream.PropertyKey.socketSecurityLevelKey)

            let settings: [NSObject: NSObject] = [
                kCFStreamSSLValidatesCertificateChain: NSNumber(booleanLiteral: false),
                ]

            input.setProperty(settings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
            output.setProperty(settings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
        }

        CFReadStreamSetDispatchQueue(input, Http2Session.sharedQueue)
        CFWriteStreamSetDispatchQueue(output, Http2Session.sharedQueue)

        input.open()
        output.open()
    }

    func writeHandshake() {
        var bytes = [UInt8]()
        bytes += prism
        bytes += settings

        guard let output = outputStream else { fatalError() }
        output.write(bytes, maxLength: bytes.count)

        state = .ready
        delegate?.sessionConnected(session: self)
    }

    lazy var prism: [UInt8] = {
        return [UInt8]("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)
    }()

    lazy var settings: [UInt8] = {
        return Frame(type: .settings).bytes()
    }()

    func processInput() throws {
        guard let input = inputStream else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let read = input.read(&buffer, maxLength: buffer.count)
        guard read > 0 else { print("processInput: failed -1"); return }
        inputQueue += Array(buffer[0..<read])

        try dequeueInput()
    }

    func dequeueInput() throws {
        guard inputQueue.count >= 9 else {
            throw Http2Error.frameSize
        }
        while !inputQueue.isEmpty {
            let buffer = Array(inputQueue[0..<9])
            inputQueue = Array(inputQueue[buffer.count..<inputQueue.count])
            guard var frame = Frame(bytes: buffer) else {
                throw Http2Error.frameSize
            }
            if frame.length > 0 {
                let count = Int(frame.length)
                frame.payload = Array(inputQueue[0..<count])
                inputQueue = Array(inputQueue[count..<inputQueue.count])
            }
            delegate?.session(session: self, hasFrame: frame)
        }
    }

    public func disconnect(error: Error? = nil) {
        writeQueue.cancelAllOperations()
        if let stream = inputStream {
            stream.close()
            CFReadStreamSetDispatchQueue(stream, nil)
            stream.delegate = nil
            inputStream = nil
        }
        if let stream = outputStream {
            stream.close()
            CFWriteStreamSetDispatchQueue(stream, nil)
            stream.delegate = nil
            outputStream = nil
        }
        state = .disconnected
    }

    public func write(frame: Frame) throws {
        var out = frame.bytes()
        if let payload = frame.payload {
            out += payload
        }
        try write(bytes: out)
    }

    public func write(bytes: [UInt8]) throws {
        guard let output = outputStream else {
            throw Http2SessionError.missingOutput
        }
        writeQueue.addOperation {
            var timeout = 5 * 1_000_000
            while self.state != .ready {
                usleep(100)
                timeout -= 100
                if timeout < 0 {
                    self.disconnect()
                }
            }
            output.write(bytes, maxLength: bytes.count)
        }
    }
}

extension Http2Session: StreamDelegate {

    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event.openCompleted:
            if aStream == outputStream {
                state = .connected
            }
            break

        case Stream.Event.hasSpaceAvailable:
            break

        case Stream.Event.hasBytesAvailable:
            guard aStream == inputStream else { return }
            do { try processInput() }
            catch { print("Http2Session.StreamDelegate.stream:", error) }
            break

        case Stream.Event.endEncountered:
            disconnect()
            break

        case Stream.Event.errorOccurred:
            disconnect()
            break
            
        default:
            print("unknown", eventCode)
        }
    }
}

// Utils

let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
let htonl  = isLittleEndian ? _OSSwapInt32 : { $0 } // host-to-network-long
