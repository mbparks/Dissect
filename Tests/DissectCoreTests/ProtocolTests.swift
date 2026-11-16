import XCTest
@testable import DissectCore

final class ProtocolTests: XCTestCase {
    func testFragmentedUnicodeAndMultipleMessages() throws {
        let payload="@DISSECT@{\"id\":\"1\",\"result\":{\"text\":\"café 🛠\"}}\n@DISSECT@{\"id\":\"2\",\"error\":\"bad input\"}\n"
        var parser=FrameDecoder()
        var messages: [EngineResponse]=[]
        for byte in payload.utf8 { messages += try parser.append(Data([byte])) }
        XCTAssertEqual(messages.count,2)
        XCTAssertEqual(messages[0].result, .object(["text": .string("café 🛠")]))
        XCTAssertEqual(messages[1].error,"bad input")
    }
    func testNoiseIsIgnoredAndMalformedFrameIsRejected() throws {
        var parser=FrameDecoder()
        XCTAssertTrue(try parser.append(Data("JAVA LOG\n".utf8)).isEmpty)
        XCTAssertThrowsError(try parser.append(Data("@DISSECT@not-json\n".utf8)))
    }
    func testOversizeIncompleteMessageIsRejected() throws {
        var parser=FrameDecoder()
        XCTAssertThrowsError(try parser.append(Data(repeating: 65,count: 8*1024*1024+1)))
    }
    func testRequestEscapesPathsWithoutShellExpansion() throws {
        let path="/Users/mike/a space/$(touch nope)\"é"
        let request=EngineRequest(id:"1",method:"open",params:["workspace":.string(path)])
        let json=try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        XCTAssertEqual((json["params"] as! [String: String])["workspace"],path)
    }
    func testWorkspaceContractAndLargeAddressStrings() throws {
        let data=Data(#"{"opened":true,"name":"sample","functions":3,"imageBase":"ffffffff80000000","canUndo":true}"#.utf8)
        let info=try JSONDecoder().decode(WorkspaceInfo.self,from:data)
        XCTAssertEqual(info.imageBase,"ffffffff80000000")
        XCTAssertEqual(info.canUndo,true)
        XCTAssertNil(info.path)
    }
}
