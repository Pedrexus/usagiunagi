// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Testing
import WaniKaniAPI

struct URLRequestSetBodyTest {
  @Test(arguments: [
    ("foo+bar", "foo%2Bbar"),
    ("foo&bar", "foo%26bar"),
    ("bob=bob", "bob%3Dbob"),
    ("foo%bar", "foo%25bar"),
    ("かな", "%E3%81%8B%E3%81%AA"),
    ("", ""),
  ])
  func formEscaping(value: String, encoded: String) throws {
    var request = try URLRequest(url: #require(URL(string: "https://example.com")))
    try request.setFormBody(
      method: "POST",
      queryItems: [URLQueryItem(name: "password", value: value)])
    let body = try #require(request.httpBody)
    #expect(String(data: body, encoding: .utf8) == "password=\(encoded)")
    #expect(request.httpMethod == "POST")
    #expect(
      request
        .value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    #expect(request.value(forHTTPHeaderField: "Content-Length") == String(body.count))
  }

  @Test func formSeparatorsAreDistinctFromEscapedValues() throws {
    var request = try URLRequest(url: #require(URL(string: "https://example.com")))
    try request.setFormBody(
      method: "POST",
      queryItems: [
        URLQueryItem(name: "username", value: "bob=bob"),
        URLQueryItem(name: "password", value: "foo&bar"),
      ])
    let body = try #require(request.httpBody)
    #expect(String(data: body, encoding: .utf8) == "username=bob%3Dbob&password=foo%26bar")
  }
}
