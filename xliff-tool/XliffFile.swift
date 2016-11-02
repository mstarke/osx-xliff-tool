//
//  XliffFile.swift
//  xliff-tool
//
//  Created by Remus Lazar on 09.01.16.
//  Copyright © 2016 Remus Lazar. All rights reserved.
//

import Foundation

/**
 Parses the XLIFF document and provides some convenience methods (e.g. for calculating total count).
 Useful to "front" a XLIFF document implementing the TableView delegate methods.
 */
class XliffFile {

    struct Filter {
        var searchString: String = ""
        var onlyNonTranslated = true
    }
    
    private static let ErrorDomain = "lazar.info.xliff-tool.xliff-file"
    
    private static func parseError(in xmlElement: XMLElement) -> NSError {
        return NSError(
            domain: XliffFile.ErrorDomain,
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "XLIFF format error",
                    comment: "XliffFile Parse Error: Description" ),
                NSLocalizedFailureReasonErrorKey: String.localizedStringWithFormat(
                    NSLocalizedString(
                        "Could not parse the XLIFF XML file at: \"%@\"",
                        comment: "XliffFile Parse Error: Failure Reason" ),
                    xmlElement.xPath!),
                    NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(
                    "Try to re-generate the XLIFF file with Xcode using \"Editor > Export For Localization\" Menu Action and re-open it.",
                    comment: "XliffFile Parse Error: Recovery Suggestion" ),
                ]
        )
    }
    
    // TransUnit must be an @objc class because we're using it in the UndoManager
    @objc class TransUnit: NSObject {
        let id: String
        let source: String
        var target: String? {
            didSet {
                if target != nil {
                    // create the XML tag if needed
                    if xmlElement.elements(forName: "target").count == 0 {
                        xmlElement.addChild(XMLElement(name: "target", stringValue: ""))
                    }
                    // update the value in the XML document as well
                    let targetXMLElement = xmlElement.elements(forName: "target").first!
                    targetXMLElement.stringValue = target
                } else {
                    if let targetTag = xmlElement.elements(forName: "target").first {
                        xmlElement.removeChild(at: targetTag.index)
                    }
                }
            }
        }
        let note: String?
        private let xmlElement: XMLElement
        
        init(xml: XMLElement) throws {
            xmlElement = xml
            
            guard let id = xml.attribute(forName: "id")?.stringValue,
                let source = xml.elements(forName: "source").first?.stringValue
                else { throw XliffFile.parseError(in: xml) }
            
            self.id = id
            self.source = source
            self.target = xml.elements(forName: "target").first?.stringValue
            self.note = xml.elements(forName: "note").first?.stringValue
        }
        
        func validate(targetString: String) throws -> Void {
            let regex = try! NSRegularExpression(
                pattern: "\\%(\\d\\$)?[\\-+ #0]*\\d*(hh|h|l|lell|ll|lell-lell|j|z|t|L)?(\\.\\d+)?.", options: []
            )
            let matches = regex.matches(in: source, options: [], range: NSMakeRange(0,source.characters.count))
            let formatStrings = matches.map { (source as NSString).substring(with: $0.range) }
            let missingFormatStrings = formatStrings.filter { (targetString as NSString).range(of: $0).location == NSNotFound }
            
            if !missingFormatStrings.isEmpty {
                throw NSError(domain: XliffFile.ErrorDomain, code: -1, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString(
                        "Validation Error",
                        comment: "TransUnit Validation Error: Description" ),
                    NSLocalizedFailureReasonErrorKey: NSLocalizedString(
                        "Missing format chars",
                        comment: "TransUnit Validation Error: Failure Reason" ),
                    NSLocalizedRecoverySuggestionErrorKey: String.localizedStringWithFormat(NSLocalizedString("Target does not contain all format characters from the source, missing \"%@\".", comment: "TransUnit Validation Error: Recovery Suggestion"), missingFormatStrings.joined(separator: ",")),
                    ]
                )
            }
        }
        
    }
    
    class File {
        let name: String
        var items: [TransUnit]
        fileprivate let allItems: [TransUnit]
        let sourceLanguage: String?
        let targetLanguage: String?
        
        init(name: String, items: [TransUnit], sourceLanguage: String?, targetLanguage: String?) {
            self.name = name
            self.items = items
            self.allItems = items
            self.sourceLanguage = sourceLanguage
            self.targetLanguage = targetLanguage
        }
    }
    
    /** Array of file containers available in the xliff container */
    let files: [File]
    
    var filter: Filter? {
        didSet {
            for file in files {
                file.items = file.allItems
                if let filter = filter {
                    if filter.onlyNonTranslated {
                        file.items = file.items.filter({
                            if let targetString = $0.target {
                                return targetString.isEmpty
                            }
                            return true
                        })
                    }
                    if !filter.searchString.isEmpty {
                        file.items = file.items.filter({
                            return $0.source.localizedCaseInsensitiveContains(filter.searchString)
                                || ($0.target?.localizedCaseInsensitiveContains(filter.searchString) ?? false)
                                || ($0.note?.localizedCaseInsensitiveContains(filter.searchString) ?? false)
                        })
                    }
                }
            }
        }
    }
    
    init(xliffDocument: XMLDocument) throws {
        var files = [File]()
        if let root = xliffDocument.rootElement() {
            for file in root.elements(forName: "file") {
                
                guard let name = file.attribute(forName: "original")?.stringValue
                    else { throw XliffFile.parseError(in: file) }
                
                let items = try ( file.nodes(forXPath: "body/trans-unit") as! [XMLElement])
                    .map { try TransUnit(xml: $0) }
                
                files.append(File(
                    name: name,
                    items: items,
                    sourceLanguage: file.attribute(forName: "source-language")?.stringValue,
                    targetLanguage: file.attribute(forName: "target-language")?.stringValue
                    ))
            }
        }
        
        self.files = files
    }
    
    var totalCount: Int {
        return files.map({ $0.items.count }).reduce(0, +)
    }
    
}
