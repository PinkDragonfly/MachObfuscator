import XCTest

class ObfuscationSymbols_Building_buildForObfuscationPaths_Tests: XCTestCase {
    var sampleObfuscationPaths: ObfuscationPaths! = ObfuscationPaths()
    var testLoader: ObfuscationSymbolsTestSymbolsSourceLoader! = ObfuscationSymbolsTestSymbolsSourceLoader()
    var testSymbolsLoader: ObfuscationSymbolsTestSourceSymbolsLoader! = ObfuscationSymbolsTestSourceSymbolsLoader()
    var sut: ObfuscationSymbols!

    override func setUp() {
        super.setUp()

        sampleObfuscationPaths.obfuscableImages = [
            URL(fileURLWithPath: "/tmp/ob1"), URL(fileURLWithPath: "/tmp/ob2"),
        ]
        sampleObfuscationPaths.unobfuscableDependencies = [
            URL(fileURLWithPath: "/tmp/x1"), URL(fileURLWithPath: "/tmp/x2"),
        ]
        sampleObfuscationPaths.systemFrameworks = [
            "/tmp/sys1.framework".asURL, "/tmp/sys2.framework".asURL,
        ]
        testLoader["/tmp/ob1"] = [
            SymbolsSourceMock.with(selectors: ["s1", "s2", "d1"],
                                   classNames: ["c1", "c2"],
                                   exportedTrie: Trie.with(label: "ob1t1"),
                                   cpuType: 0x17,
                                   cpuSubtype: 0x42),
            SymbolsSourceMock.with(selectors: ["s1", "s3"],
                                   classNames: ["c1", "c3"],
                                   cstrings: ["s4", "c4"],
                                   exportedTrie: Trie.with(label: "ob1t2"),
                                   cpuType: 0x17,
                                   cpuSubtype: 0x43),
        ]
        testLoader["/tmp/ob2"] = [
            SymbolsSourceMock.with(selectors: ["s1", "s2", "s5", "s6", "s7"],
                                   classNames: ["c1", "c2", "c5", "c6", "c7"],
                                   dynamicPropertyNames: ["d1"],
                                   exportedTrie: Trie.with(label: "ob2"),
                                   cpuType: 0x17,
                                   cpuSubtype: 0x42),
        ]
        testLoader["/tmp/x1"] = [
            SymbolsSourceMock.with(selectors: ["s2"],
                                   classNames: ["c2"]),
        ]
        testLoader["/tmp/x2"] = [
            SymbolsSourceMock.with(selectors: ["s5"],
                                   classNames: ["c5"],
                                   cstrings: ["s6", "c6"]),
        ]
        testSymbolsLoader["/tmp/sys1.framework"] = ObjectSymbols(
            selectors: ["sys1s"],
            classNames: ["sys1c"]
        )
        testSymbolsLoader["/tmp/sys2.framework"] = ObjectSymbols(
            selectors: ["sys2s"],
            classNames: ["sys2c"]
        )

        sut = buildSUT()
    }

    func buildSUT(objcOptions: ObjcOptions = ObjcOptions()) -> ObfuscationSymbols {
        return ObfuscationSymbols.buildFor(obfuscationPaths: sampleObfuscationPaths,
                                           loader: testLoader,
                                           sourceSymbolsLoader: testSymbolsLoader,
                                           skippedSymbols: ObjectSymbols.sample,
                                           objcOptions: objcOptions)
    }

    func test_whitelistSelectors_shouldContainObfuscableImagesAccessors_withoutBlacklistedAccessors() {
        XCTAssertEqual(sut.whitelist.selectors, ["s1", "s3", "s7"])
        XCTAssert(sut.whitelist.selectors.intersection(sut.blacklist.selectors).isEmpty)
    }

    func test_whitelistClassNames_shouldContainObfuscableImagesClassNames_withoutBlacklistedClassNames() {
        XCTAssertEqual(sut.whitelist.classes, ["c1", "c3", "c7"])
        XCTAssert(sut.whitelist.classes.intersection(sut.blacklist.classes).isEmpty)
    }

    func test_whitelistClasses_shouldContainObfuscableClasses_withoutBlacklistedClassesAndCustomBlacklist() {
        var objcOptions = ObjcOptions()
        objcOptions.classesBlacklist = ["c3", "notexisting"]
        sut = buildSUT(objcOptions: objcOptions)
        XCTAssertEqual(sut.whitelist.classes, ["c1", "c7"])
        XCTAssert(sut.whitelist.classes.intersection(sut.blacklist.classes).isEmpty)
    }

    func test_whitelistClasses_shouldContainObfuscableClasses_withoutBlacklistedClassesAndCustomBlacklistRegex() {
        var objcOptions = ObjcOptions()
        objcOptions.classesBlacklistRegex = [try! NSRegularExpression(pattern: "^c[17]$", options: []),
                                             try! NSRegularExpression(pattern: "notexisting", options: [])]
        sut = buildSUT(objcOptions: objcOptions)
        XCTAssertEqual(sut.whitelist.classes, ["c3"])
        XCTAssert(sut.blacklist.classes.contains("c1"))
        XCTAssert(sut.blacklist.classes.contains("c7"))
        XCTAssert(sut.whitelist.selectors.intersection(sut.blacklist.selectors).isEmpty)
    }

    func test_whitelistSelectors_shouldContainObfuscableImagesAccessors_withoutBlacklistedAccessorsAndCustomBlacklist() {
        var objcOptions = ObjcOptions()
        objcOptions.selectorsBlacklist = ["s3", "notexisting"]
        sut = buildSUT(objcOptions: objcOptions)
        XCTAssertEqual(sut.whitelist.selectors, ["s1", "s7"])
        XCTAssert(sut.whitelist.selectors.intersection(sut.blacklist.selectors).isEmpty)
    }

    func test_whitelistSelectors_shouldContainObfuscableImagesAccessors_withoutBlacklistedAccessorsAndCustomBlacklistRegex() {
        var objcOptions = ObjcOptions()
        objcOptions.selectorsBlacklistRegex = [try! NSRegularExpression(pattern: "^s[17]$", options: []),
                                               try! NSRegularExpression(pattern: "notexisting", options: [])]
        sut = buildSUT(objcOptions: objcOptions)
        XCTAssertEqual(sut.whitelist.selectors, ["s3"])
        XCTAssert(sut.blacklist.selectors.contains("s1"))

        XCTAssert(sut.blacklist.selectors.contains("s7"))
        XCTAssert(sut.whitelist.selectors.intersection(sut.blacklist.selectors).isEmpty)
    }

    // TODO: make it opt-out
    func test_blacklistSelectors_shouldContainDynamicPropertyAccessors_andUnobfuscableDependenciesAccessors_andCstringsAccessors_andFrameworkHeaderAccessors() {
        let dynamicPropertySymbols: Set<String> = ["d1", "setD1:"]
        let unobfuscableDependenciesSymbols: Set<String> = ["s2", "setS2:", "s5", "setS5:"]
        let cstringsSymbols: Set<String> = ["s4", "setS4:", "c4", "setC4:", "s6", "setS6:", "c6", "setC6:"]
        let frameworkHeaderSymbols: Set<String> = ["sys1s", "setSys1s:", "sys2s", "setSys2s:"]
        let skippedSymbols: Set<String> = ["sourceSelector", "setSourceSelector:"]
        XCTAssertEqual(sut.blacklist.selectors,
                       dynamicPropertySymbols
                           .union(unobfuscableDependenciesSymbols)
                           .union(cstringsSymbols)
                           .union(frameworkHeaderSymbols)
                           .union(skippedSymbols)
                           .union(Mach.libobjcSelectors))
    }

    func test_blacklistClassNames_shouldContainUnobfuscableDependenciesClassNames_andAllCstringsClassNames_andFrameworkHeaderClassNames() {
        let unobfuscableDependenciesClassNames: Set<String> = ["c2", "c5"]
        let cstringsClassNames: Set<String> = ["s4", "c4", "s6", "c6"]
        let frameworkHeaderClassNames: Set<String> = ["sys1c", "sys2c"]
        let skippedSymbols: Set<String> = ["sourceClass"]
        XCTAssertEqual(sut.blacklist.classes,
                       unobfuscableDependenciesClassNames
                           .union(cstringsClassNames)
                           .union(frameworkHeaderClassNames)
                           .union(skippedSymbols))
    }

    func test_exportTriesPerURL_shouldContainTriesOfObfuscableImages() {
        let ob1TriePerCpuId: [CpuId: Trie]! = sut.exportTriesPerCpuIdPerURL[URL(fileURLWithPath: "/tmp/ob1")]
        XCTAssertNotNil(ob1TriePerCpuId)
        XCTAssertEqual(ob1TriePerCpuId.count, 2)
        XCTAssertEqual(ob1TriePerCpuId[0x17_0000_0042]?.labelString, "ob1t1")
        XCTAssertEqual(ob1TriePerCpuId[0x17_0000_0043]?.labelString, "ob1t2")

        let ob2TriePerCpuId: [CpuId: Trie]! = sut.exportTriesPerCpuIdPerURL[URL(fileURLWithPath: "/tmp/ob2")]
        XCTAssertNotNil(ob2TriePerCpuId)
        XCTAssertEqual(ob2TriePerCpuId.count, 1)
        XCTAssertEqual(ob2TriePerCpuId[0x17_0000_0042]?.labelString, "ob2")
    }
}

private extension ObjectSymbols {
    static let sample = ObjectSymbols(selectors: ["sourceSelector"],
                                      classNames: ["sourceClass"])
}
