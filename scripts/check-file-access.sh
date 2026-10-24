#!/bin/bash
set -euo pipefail

access_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
access_tmp="$(mktemp -d "${TMPDIR:-/tmp}/lplayer-file-access.XXXXXX")"
trap 'rm -rf "$access_tmp"' EXIT

# Command Line Tools installations do not ship XCTest. Run the exact same
# permission tests with a tiny assertion adapter instead of duplicating them.
python3 - "$access_root" "$access_tmp/AccessChecks.swift" <<'PY'
from pathlib import Path
import re
import sys

root, output = Path(sys.argv[1]), Path(sys.argv[2])
source = (root / "Tests/PalmPlayerTests/FileAccessStoreTests.swift").read_text()
source = source.replace("import XCTest\n", "").replace("@testable import PalmPlayer\n", "")
tests = re.findall(r"    func (test\w+)\(", source)
adapter = '''
class XCTestCase {
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
}
func XCTAssertTrue(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) { precondition(condition(), "Expected true", file: file, line: line) }
func XCTAssertFalse(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) { precondition(!condition(), "Expected false", file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, file: StaticString = #filePath, line: UInt = #line) { precondition(lhs() == rhs(), "Values differ", file: file, line: line) }
func XCTAssertNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) { precondition(value() == nil, "Expected nil", file: file, line: line) }
func XCTAssertNotNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) { precondition(value() != nil, "Expected a value", file: file, line: line) }
'''
main = "\n@main enum AccessChecks { static func main() throws {\n"
for test in tests:
    main += f'''do {{
let fixture = FileAccessStoreTests()
try fixture.setUpWithError()
defer {{ try! fixture.tearDownWithError() }}
try fixture.{test}()
print("PASS {test}")
}}\n'''
main += f'print("All {len(tests)} file-access checks passed.")\n}} }}\n'
output.write_text(source + adapter + main)
PY

swiftc -swift-version 5 -suppress-warnings -parse-as-library \
  "$access_root/Sources/PalmPlayer/FileAccessStore.swift" \
  "$access_root/Sources/PalmPlayer/LibraryStore.swift" \
  "$access_tmp/AccessChecks.swift" \
  -o "$access_tmp/access-checks"
"$access_tmp/access-checks"
