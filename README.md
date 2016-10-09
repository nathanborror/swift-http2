# Swift Http2

A very simple [HTTP/2][1] library for Swift.

---

:warning: There is active work going on here that will result in API changes. :warning:

---

## Usage

```swift
class MyDelegate: NSObject, Http2SessionDelegate {

  public func sessionConnected(session: http2Session) {}
  public func session(session: http2Session, hasFrame frame: Frame) {}
}

let session = Http2Session(url: URL(string: "http://localhost")!)
let sessionDelegate = MyDelegate()
session.delegate = sessionDelegate

// Connect to host
session.connect()

// Get a new stream ID
let stream = session.streams.next()


// Set some headers
let headers = [
  (":method", "POST"),
  (":scheme", "http"),
  (":path", "/"),
  ("content-type", "application/json"),
  ("te", "trailers"),
]

// Create a header frame and write it to the session
let frame = Frame(headers: headers, stream: stream, flags: .endHeaders)
try? session.write(frame: frame)

// Create a data frame and send some bytes
let bytes = [UInt8]()
let data = Frame(data: bytes, stream: stream, flags: .endStream)
try? session.write(frame: data)

// Disconnect from host
session.disconnect()
```

[1]:https://tools.ietf.org/html/rfc7540
