//  M3U8Parser.swift
//
//  Created by Iurii Khvorost <iurii.khvorost@gmail.com> on 2022/05/22.
//  Copyright © 2022 Iurii Khvorost. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

extension String : LocalizedError {
    public var errorDescription: String? { return self }
}

class M3U8Parser {
    private static let regexExtTag = try! NSRegularExpression(pattern: "^#(EXT[^:]+):?(.*)$", options: [])
    private static let regexAttributes = try! NSRegularExpression(pattern: "([^=,]+)=((\"([^\"]+)\")|([^,]+))")
    private static let regexExtInf = try! NSRegularExpression(pattern: "^([^,]+),(.*)$")
    private static let regexByterange = try! NSRegularExpression(pattern: "^(\\d+)@?(\\d*)$")
    private static let regexResolution = try! NSRegularExpression(pattern: "^(\\d+)x(\\d+)$")
    
    private static let boolValues = ["YES", "NO"]
    
    private static let uriKey = "uri"
    private static let arrayTags = [
        "EXTINF", "EXT-X-BYTERANGE", // Playlist
        "EXT-X-MEDIA", "EXT-X-STREAM-INF", "EXT-X-I-FRAME-STREAM-INF" // Master playlist
    ]
    
    var keyDecodingStrategy: M3U8Decoder.KeyDecodingStrategy = .snakeCase
    
    func parse(text: String) -> [String : Any]? {
        guard text.isEmpty == false else {
            return nil
        }
        
        var dict = [String : Any]()
        
        let items = text.components(separatedBy: .newlines)
        for i in 0..<items.count {
            let line = items[i]
            
            // Empty line
            guard line.isEmpty == false else {
                continue
            }
            
            // URI
            guard line.hasPrefix("#EXT") else {
                if var items = dict[Self.uriKey] as? [Any] {
                    items.append(line)
                    dict[Self.uriKey] = items
                }
                else {
                    dict[Self.uriKey] = [line]
                }
                continue
            }
            
            // Tags #EXT
            let range = NSRange(location: 0, length: line.utf16.count)
            Self.regexExtTag.matches(in: line, options: [], range: range).forEach {
                if let tagRange = Range($0.range(at: 1), in: text), let attributesRange = Range($0.range(at: 2), in: line) {
                    let tag = String(line[tagRange])
                    let attributes = String(line[attributesRange])
                    
                    let key = key(text: tag)
                    let value = attributes.isEmpty
                        ? true
                        : parseAttributes(tag: tag, attributes: attributes)
                    
                    if let item = dict[key] {
                        if var items = item as? [Any] {
                            items.append(value)
                            dict[key] = items
                        }
                        else {
                            dict[key] = [item, value]
                        }
                    }
                    else {
                        if Self.arrayTags.contains(tag) {
                            dict[key] = [value]
                        }
                        else {
                            dict[key] = value
                        }
                    }
                }
            }
        }
        return dict
    }
    
    private func key(text: String) -> String {
        switch keyDecodingStrategy {
        case .snakeCase:
            fallthrough
        case .camelCase:
            return text.lowercased().replacingOccurrences(of: "-", with: "_")
            
        case let .custom(f):
            return f(text)
        }
    }
    
    private func convert(text: String) -> Any {
        guard text.count < 10  else {
            return text
        }
        
        if let number = Double(text) {
            return number
        }
        else if Self.boolValues.contains(text) {
            return text == "YES"
        }
        
        return text
    }
    
    private func parseAttribute(name: String, value: String) -> [String : Any]? {
        var dict = [String : Any]()
        let range = NSRange(location: 0, length: value.utf16.count)
        
        switch name {
        // #EXTINF:<duration>,[<title>]
        // https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.1
        case "EXTINF":
            if let match = Self.regexExtInf.matches(in: value, options: [], range: range).first,
               match.numberOfRanges == 3,
               let durationRange = Range(match.range(at: 1), in: value),
               let titleRange = Range(match.range(at: 2), in: value)
            {
                let duration = String(value[durationRange])
                dict["duration"] = self.convert(text: duration)
                
                let title = String(value[titleRange])
                if title.isEmpty == false {
                    dict["title"] = title
                }
            }
            
        // #EXT-X-BYTERANGE:<n>[@<o>]
        // https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.2
        case "EXT-X-BYTERANGE":
            fallthrough
        case "BYTERANGE":
            if let match = Self.regexByterange.matches(in: value, options: [], range: range).first,
               match.numberOfRanges == 3,
               let lengthRange = Range(match.range(at: 1), in: value),
               let startRange = Range(match.range(at: 2), in: value)
            {
                let length = String(value[lengthRange])
                dict["length"] = self.convert(text: length)
                
                let start = String(value[startRange])
                if start.isEmpty == false {
                    dict["start"] = self.convert(text:start)
                }
            }
            
        case "RESOLUTION":
            let matches = Self.regexResolution.matches(in: value, options: [], range: range)
            if let match = matches.first, match.numberOfRanges == 3,
               let widthRange = Range(match.range(at: 1), in: value),
               let heightRange = Range(match.range(at: 2), in: value)
            {
                let width = String(value[widthRange])
                dict["width"] = self.convert(text: width)
                
                let height = String(value[heightRange])
                dict["height"] = self.convert(text:height)
            }
            
        default:
            return nil
        }
        return dict.count > 0 ? dict : nil
    }
    
    private func parseAttributes(tag: String, attributes: String) -> Any {
        if let keyValues = parseAttribute(name: tag, value: attributes) {
            return keyValues
        }
        else {
            var keyValues = [String : Any]()
            let range = NSRange(location: 0, length: attributes.utf16.count)
            Self.regexAttributes.matches(in: attributes, options: [], range: range).forEach {
                guard $0.numberOfRanges >= 3,
                      let keyRange = Range($0.range(at: 1), in: attributes),
                      let valueRange = Range($0.range(at: 2), in: attributes)
                else {
                    return
                }
                
                let name = String(attributes[keyRange])
                let key = key(text: name)
                let value = String(attributes[valueRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                
                if let dict = parseAttribute(name: name, value: value) {
                    keyValues[key] = dict
                }
                else {
                    keyValues[key] = self.convert(text: value)
                }
            }
            
            return keyValues.count > 0
                ? keyValues
                : convert(text: attributes)
        }
    }
}
