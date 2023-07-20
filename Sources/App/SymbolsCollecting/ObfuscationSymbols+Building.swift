import Foundation

extension ObfuscationSymbols {
    static func buildFor(obfuscationPaths: ObfuscationPaths,
                         loader: SymbolsSourceLoader,
                         sourceSymbolsLoader: RecursiveSourceSymbolsLoaderProtocol,
                         symbolListLoader: TextFileSymbolListLoaderProtocol,
                         skippedSymbolsSources: [URL],
                         skippedSymbolsLists: [URL],
                         objcOptions: ObjcOptions = ObjcOptions()) -> ObfuscationSymbols {
        let skippedSymbols =
            (
                skippedSymbolsSources.map(sourceSymbolsLoader.load(fromDirectory:))
                + skippedSymbolsLists.map(symbolListLoader.load(fromTextFile:))
            ).flatten()

        /** 系统*/
        let systemSources = time(withTag: "systemSources") { try! obfuscationPaths.unobfuscableDependencies.flatMap { try loader.load(forURL: $0) } }

        /** 用户*/
        let userSourcesPerPath = time(withTag: "userSources") { [URL: [SymbolsSource]](uniqueKeysWithValues: obfuscationPaths.obfuscableImages.map { ($0, try! loader.load(forURL: $0)) }) }
        let userSources = userSourcesPerPath.values.flatMap { $0 }

//        print("__> User Sources: \(userSources)")
        
        
        print("==================== Start Show ====================")
        print("==================== User Selectors ====================")
        let userSelectors = userSources.flatMap { $0.selectors }.uniq
//        print("__> User Selectors: \(userSelectors)")
        print("==================== User Classes ====================")
        let userClasses = userSources.flatMap { $0.classNames }.uniq
        print("==================== User CStrings ====================")
        let userCStrings = userSources.flatMap { $0.cstrings }.uniq
        print("==================== User DynamicProperties ====================")
        let userDynamicProperties = userSources.flatMap { $0.dynamicPropertyNames }.uniq
        
        print("==================== System Selectors ====================")
        var systemSelectors = systemSources.flatMap { $0.selectors }.uniq
        print("==================== System Classes ====================")
        var systemClasses = systemSources.flatMap { $0.classNames }.uniq
        print("==================== System CStrings ====================")
        var systemCStrings = systemSources.flatMap { $0.cstrings }.uniq
        print("==================== End ====================")
        
        /** 系统头文件符号表*/
        let systemHeaderSymbols = time(withTag: "systemHeaderSymbols") { obfuscationPaths.systemFrameworks
            .concurrentMap(sourceSymbolsLoader.load(fromDirectory:))
            .flatten()
        }
        
        print("__> System Header Symbols: \(systemHeaderSymbols)")

        // TODO: Array(userCStrings) should be opt-in
        let blackListGetters: Set<String> =
            systemHeaderSymbols.selectors
            .union(systemSelectors)
            .union(systemCStrings)
            .union(userDynamicProperties)
            .union(userCStrings)
            .union(skippedSymbols.selectors)
        let blacklistSetters = blackListGetters.map { $0.asSetter }.uniq

        let blacklistedSelectorsByRegex = userSelectors.matching(regexes: objcOptions.selectorsBlacklistRegex)
        let notFoundBlacklistedSelectors = Set(objcOptions.selectorsBlacklist).subtracting(userSelectors)
        if !notFoundBlacklistedSelectors.isEmpty {
            LOGGER.warn("Some selectors specified on blacklist were not found: \(notFoundBlacklistedSelectors)")
        }

        let blacklistSelectors = blackListGetters
            .union(blacklistSetters)
            .union(Mach.libobjcSelectors)
            .union(objcOptions.selectorsBlacklist)
            .union(blacklistedSelectorsByRegex)
        // TODO: Array(userCStrings) should be opt-in

        let blacklistedClassesByRegex = userClasses.matching(regexes: objcOptions.classesBlacklistRegex)
        let notFoundBlacklistedClasses = Set(objcOptions.classesBlacklist).subtracting(userClasses)
        if !notFoundBlacklistedClasses.isEmpty {
            LOGGER.warn("Some classes specified on blacklist were not found: \(notFoundBlacklistedClasses)")
        }

        let blacklistClasses: Set<String> =
            systemHeaderSymbols.classNames
            .union(systemClasses)
            .union(systemCStrings)
            .union(userCStrings)
            .union(skippedSymbols.classNames)
            .union(objcOptions.classesBlacklist)
            .union(blacklistedClassesByRegex)

        let whitelistSelectors = userSelectors.subtracting(blacklistSelectors)
        let whitelistClasses = userClasses.subtracting(blacklistClasses)

        let whitelistExportTriePerCpuIdPerURL: [URL: [CpuId: Trie]] =
            userSourcesPerPath.mapValues { symbolsSources in
                // LLVM-IR (Bitcode) images may not have export trie
                [CpuId: Trie](symbolsSources.filter { $0.exportedTrie != nil }
                    .map { ($0.cpu.asCpuId, $0.exportedTrie!) },
                              uniquingKeysWith: { _, _ in fatalError("Duplicated cpuId") })
            }

        let whiteList = ObjCSymbols(selectors: whitelistSelectors, classes: whitelistClasses)
        let blackList = ObjCSymbols(selectors: blacklistSelectors, classes: blacklistClasses)
        let removedList = ObjCSymbols(selectors: userSelectors.intersection(blacklistSelectors), classes: userClasses.intersection(blacklistClasses))

        print("============================ White List Symbols ============================")
        print(whiteList)
        print("============================ End ============================")
        
        return ObfuscationSymbols(whitelist: whiteList, blacklist: blackList, removedList: removedList, exportTriesPerCpuIdPerURL: whitelistExportTriePerCpuIdPerURL)
    }
}

extension Image {
    var machPerOffset: [UInt64: Mach] {
        switch contents {
        case let .fat(fat):
            return [UInt64: Mach](fat.architectures.map { ($0.offset, $0.mach) },
                                  uniquingKeysWith: { _, _ in
                                      fatalError("Two architectures at the same offset. Programming error?")
            })
        case let .mach(mach):
            return [0: mach]
        }
    }
}

private extension String {
    var asSetter: String {
        guard count >= 1 else {
            return self
        }
        return "set\(capitalizedOnFirstLetter):"
    }
}
