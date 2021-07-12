import Foundation

struct EraseSectionConfiguration {
    var sectionName: String
    var segmentName: String
}

private extension EraseSectionConfiguration {
    init(sectionDef: String) {
        let sectionParts = sectionDef.split(separator: ",")
        guard sectionParts.count == 2 else {
            fatalError("Section must by pointed with SEGMENT,SECTION format")
        }
        self.init(sectionName: String(sectionParts[1]), segmentName: String(sectionParts[0]))
    }
}

struct ObjcOptions {
    /// Do not obfuscate given classes
    var classesBlacklist: [String] = []
    /// Do not obfuscate classes matching regexes
    var classesBlacklistRegex: [NSRegularExpression] = []

    /// Do not obfuscate given selectors
    var selectorsBlacklist: [String] = []
    // Do not obfuscate selectors matching regexes
    var selectorsBlacklistRegex: [NSRegularExpression] = []
}

enum ReportTarget {
    case None
    case Console
}

struct Options {
    var unknownOption = false
    var help = false
    var dryrun = false
    var quiet = false
    var verbose = false
    var debug = false
    var dumpMetadata = false
    var machOViewDoom = false
    var eraseMethType = false
    var eraseSymtab = true
    var swiftReflectionObfuscation = false
    var objcOptions = ObjcOptions()
    var eraseSections: [EraseSectionConfiguration] = []
    // TODO: paths could be replaced by something more useful
    var sourceFileNamesReplacement = "FILENAME_REMOVED"
    var sourceFileNamesPrefixes: [String] = []
    var cstringsReplacements: [String: String] = [:]
    var obfuscableFilesFilter = ObfuscableFilesFilter.defaultObfuscableFilesFilter()
    var analyzeDependencies = true
    var findSymbols: [String] = []
    var manglerType: SymbolManglers? = SymbolManglers.defaultMangler
    var skippedSymbolsSources: [URL] = []
    var skippedSymbolsLists: [URL] = []
    var appDirectoryOrFile: URL?

    var reportTarget: ReportTarget = .None
}

extension Options {
    typealias UnsafeArgv = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>

    static func fromCommandLine() -> Options {
        return self.init(argc: CommandLine.argc,
                         unsafeArgv: CommandLine.unsafeArgv,
                         argv: CommandLine.arguments)
    }

    static func newCCharPtrFromStaticString(_ str: StaticString) -> UnsafePointer<CChar> {
        let rp = UnsafeRawPointer(str.utf8Start)
        let rplen = str.utf8CodeUnitCount
        return rp.bindMemory(to: CChar.self, capacity: rplen)
    }

    init(argc: Int32, unsafeArgv: UnsafeArgv, argv: [String]) {
        optreset = 1

        struct OptLongChars {
            static let unknownOption = Int32(Character("?").asciiValue!)
            static let help = Int32(Character("h").asciiValue!)
            static let verbose = Int32(Character("v").asciiValue!)
            static let quiet = Int32(Character("q").asciiValue!)
            static let debug = Int32(Character("d").asciiValue!)
            static let machOViewDoom = Int32(Character("D").asciiValue!)
            static let manglerKey = Int32(Character("m").asciiValue!)
        }
        enum OptLongCases: Int32 {
            case OPT_FIRST = 256
            case preserveSymtab
            case swiftReflection
            case objcBlacklistClass
            case objcBlacklistClassRegex
            case objcBlacklistSelector
            case objcBlacklistSelectorRegex
            case eraseSection
            case eraseMethType
            case eraseSourceFileNames
            case obfuscateFramework
            case skipFramework
            case skipAllFrameworks
            case skipSymbolsFromSources
            case skipSymbolsFromList
            case dryrun
            case replaceCstring
            case replaceWith

            // reporting options
            case reportToConsole

            // extra/development options
            case xxNoAnalyzeDependencies
            case xxDumpMetadata
            case xxFindSymbol
        }

        var currentCstringToReplace: String?

        var obfuscableFilesWhitelistFilter = ObfuscableFilesFilter.none()
        var obfuscableFilesBlacklistFilter = ObfuscableFilesFilter.defaultObfuscableFilesFilter()

        // Command line options should be named according to following rules:
        // - be consistent with GNU standards (https://www.gnu.org/prep/standards/html_node/Command_002dLine-Interfaces.html, https://www.gnu.org/prep/standards/html_node/Option-Table.html)
        // - for options that disable some default behaviour prefer to use `no-` prefix
        let longopts: [option] = [
            option(name: Options.newCCharPtrFromStaticString("help"), has_arg: no_argument, flag: nil, val: OptLongChars.help),
            option(name: Options.newCCharPtrFromStaticString("verbose"), has_arg: no_argument, flag: nil, val: OptLongChars.verbose),
            option(name: Options.newCCharPtrFromStaticString("dry-run"), has_arg: no_argument, flag: nil, val: OptLongCases.dryrun.rawValue),
            option(name: Options.newCCharPtrFromStaticString("erase-methtype"), has_arg: no_argument, flag: nil, val: OptLongCases.eraseMethType.rawValue),
            option(name: Options.newCCharPtrFromStaticString("machoview-doom"), has_arg: no_argument, flag: nil, val: OptLongChars.machOViewDoom),
            option(name: Options.newCCharPtrFromStaticString("preserve-symtab"), has_arg: no_argument, flag: nil, val: OptLongCases.preserveSymtab.rawValue),
            option(name: Options.newCCharPtrFromStaticString("objc-blacklist-class"), has_arg: required_argument, flag: nil, val: OptLongCases.objcBlacklistClass.rawValue),
            option(name: Options.newCCharPtrFromStaticString("objc-blacklist-class-regex"), has_arg: required_argument, flag: nil, val: OptLongCases.objcBlacklistClassRegex.rawValue),
            option(name: Options.newCCharPtrFromStaticString("objc-blacklist-selector"), has_arg: required_argument, flag: nil, val: OptLongCases.objcBlacklistSelector.rawValue),
            option(name: Options.newCCharPtrFromStaticString("objc-blacklist-selector-regex"), has_arg: required_argument, flag: nil, val: OptLongCases.objcBlacklistSelectorRegex.rawValue),
            option(name: Options.newCCharPtrFromStaticString("erase-section"), has_arg: required_argument, flag: nil, val: OptLongCases.eraseSection.rawValue),
            option(name: Options.newCCharPtrFromStaticString("erase-source-file-names"), has_arg: required_argument, flag: nil, val: OptLongCases.eraseSourceFileNames.rawValue),
            option(name: Options.newCCharPtrFromStaticString("replace-cstring"), has_arg: required_argument, flag: nil, val: OptLongCases.replaceCstring.rawValue),
            option(name: Options.newCCharPtrFromStaticString("replace-cstring-with"), has_arg: required_argument, flag: nil, val: OptLongCases.replaceWith.rawValue),
            option(name: Options.newCCharPtrFromStaticString("obfuscate-framework"), has_arg: required_argument, flag: nil, val: OptLongCases.obfuscateFramework.rawValue),
            option(name: Options.newCCharPtrFromStaticString("skip-framework"), has_arg: required_argument, flag: nil, val: OptLongCases.skipFramework.rawValue),
            option(name: Options.newCCharPtrFromStaticString("skip-all-frameworks"), has_arg: no_argument, flag: nil, val: OptLongCases.skipAllFrameworks.rawValue),
            option(name: Options.newCCharPtrFromStaticString("mangler"), has_arg: required_argument, flag: nil, val: OptLongChars.manglerKey),
            option(name: Options.newCCharPtrFromStaticString("skip-symbols-from-sources"), has_arg: required_argument, flag: nil, val: OptLongCases.skipSymbolsFromSources.rawValue),
            option(name: Options.newCCharPtrFromStaticString("skip-symbols-from-list"), has_arg: required_argument, flag: nil, val: OptLongCases.skipSymbolsFromList.rawValue),

            // reporting options
            option(name: Options.newCCharPtrFromStaticString("report-to-console"), has_arg: no_argument, flag: nil, val: OptLongCases.reportToConsole.rawValue),

            // extra options
            option(name: Options.newCCharPtrFromStaticString("xx-no-analyze-dependencies"), has_arg: no_argument, flag: nil, val: OptLongCases.xxNoAnalyzeDependencies.rawValue),
            option(name: Options.newCCharPtrFromStaticString("xx-dump-metadata"), has_arg: no_argument, flag: nil, val: OptLongCases.xxDumpMetadata.rawValue),
            option(name: Options.newCCharPtrFromStaticString("xx-find-symbol"), has_arg: required_argument, flag: nil, val: OptLongCases.xxFindSymbol.rawValue),

            option(), // { NULL, NULL, NULL, NULL }
        ]

        while case let option = getopt_long(argc, unsafeArgv, "qvdhDm:", longopts, nil), option != -1 {
            switch option {
            case OptLongChars.quiet:
                quiet = true
            case OptLongChars.verbose:
                verbose = true
            case OptLongChars.debug:
                debug = true
            case OptLongChars.help:
                help = true
            case OptLongCases.dryrun.rawValue:
                dryrun = true
            case OptLongCases.eraseMethType.rawValue:
                eraseMethType = true
            case OptLongChars.machOViewDoom:
                machOViewDoom = true
            case OptLongChars.manglerKey:
                manglerType = SymbolManglers(rawValue: String(cString: optarg))
            case OptLongCases.preserveSymtab.rawValue:
                eraseSymtab = false
            case OptLongCases.swiftReflection.rawValue:
                swiftReflectionObfuscation = true
            case OptLongCases.objcBlacklistClass.rawValue:
                objcOptions.classesBlacklist += String(cString: optarg).split(separator: ",").map { String($0) }
            case OptLongCases.objcBlacklistClassRegex.rawValue:
                do {
                    let regex = try NSRegularExpression(pattern: String(cString: optarg), options: [])
                    objcOptions.classesBlacklistRegex.append(regex)
                } catch {
                    fatalError("Class blacklist regex '\(String(cString: optarg))' is invalid: \(error.localizedDescription)")
                }
            case OptLongCases.objcBlacklistSelector.rawValue:
                objcOptions.selectorsBlacklist += String(cString: optarg).split(separator: ",").map { String($0) }
            case OptLongCases.objcBlacklistSelectorRegex.rawValue:
                do {
                    let regex = try NSRegularExpression(pattern: String(cString: optarg), options: [])
                    objcOptions.selectorsBlacklistRegex.append(regex)
                } catch {
                    fatalError("Selector blacklist regex '\(String(cString: optarg))' is invalid: \(error.localizedDescription)")
                }
            case OptLongCases.eraseSection.rawValue:
                eraseSections.append(EraseSectionConfiguration(sectionDef: String(cString: optarg)))
            case OptLongCases.eraseSourceFileNames.rawValue:
                sourceFileNamesPrefixes.append(String(cString: optarg))
            case OptLongCases.replaceCstring.rawValue:
                guard currentCstringToReplace == nil else {
                    fatalError("Previous --replace-cstring not followed by --replace-cstring-with")
                }
                currentCstringToReplace = String(cString: optarg)
            case OptLongCases.replaceWith.rawValue:
                // Set replacement for most recent string
                guard let currentCstring = currentCstringToReplace else {
                    fatalError("--replace-cstring-with may be used only after --replace-cstring")
                }
                let replacement = String(cString: optarg)
                guard currentCstring.utf8.count >= replacement.utf8.count else {
                    fatalError("Replacement must be the same length or shorter that CString to replace")
                }
                cstringsReplacements[currentCstring] = replacement
                // wait for next pair
                currentCstringToReplace = nil
            case OptLongCases.obfuscateFramework.rawValue:
                obfuscableFilesWhitelistFilter = obfuscableFilesWhitelistFilter.or(ObfuscableFilesFilter.isFramework(framework: String(cString: optarg)))
            case OptLongCases.skipFramework.rawValue:
                obfuscableFilesBlacklistFilter = obfuscableFilesBlacklistFilter.and(ObfuscableFilesFilter.skipFramework(framework: String(cString: optarg)))
            case OptLongCases.skipAllFrameworks.rawValue:
                obfuscableFilesBlacklistFilter = obfuscableFilesBlacklistFilter.and(ObfuscableFilesFilter.skipAllFrameworks())
            case OptLongCases.skipSymbolsFromSources.rawValue:
                let sourcesPath = URL(fileURLWithPath: String(cString: optarg))
                skippedSymbolsSources.append(sourcesPath)
            case OptLongCases.skipSymbolsFromList.rawValue:
                let listPath = URL(fileURLWithPath: String(cString: optarg))
                skippedSymbolsLists.append(listPath)

            // reporting options
            case OptLongCases.reportToConsole.rawValue:
                reportTarget = .Console

            // extra options
            case OptLongCases.xxNoAnalyzeDependencies.rawValue:
                analyzeDependencies = false
            case OptLongCases.xxDumpMetadata.rawValue:
                dumpMetadata = true
            case OptLongCases.xxFindSymbol.rawValue:
                findSymbols += String(cString: optarg).split(separator: ",").map { String($0) }

            case OptLongChars.unknownOption:
                unknownOption = true
            default:
                fatalError("Unexpected argument: \(option)")
            }
        }

        guard currentCstringToReplace == nil else {
            fatalError("Last --replace-cstring not followed by --replace-cstring-with")
        }

        // Create final obfuscable files filter. Grouping of checks is important.
        // Adding whitelisted frameworks as one group and blacklisted as another
        // makes the system behave more user friendly, because it creates following expression:
        // isObfuscable = (whitelist1 || whitelist2 || whitelist3) || ( !blacklist1 && !blacklist2 )
        // This allows for example to specify whitelist and blacklist options in any order
        // and they will not interfere with each other.
        obfuscableFilesFilter = obfuscableFilesWhitelistFilter.or(obfuscableFilesBlacklistFilter)

        var appDirectory: String?
        if optind < argc {
            appDirectory = argv[Int(optind)]
        }

        appDirectoryOrFile = appDirectory
            .flatMap(URL.init(fileURLWithPath:))?
            .resolvingSymlinksInPath()
    }

    static var usage: String {
        return """
        usage: \(CommandLine.arguments[0]) [-qvdhtD] [-m mangler_key] APP_BUNDLE|FILE

          Obfuscates application bundle in given directory (APP_BUNDLE) or Mach-O file (FILE) in-place.

        Options:
          -h, --help              help screen (this screen)
          -q, --quiet             quiet mode, no output to stdout
          -v, --verbose           verbose mode, output verbose info to stdout
          -d, --debug             debug mode, output more verbose info to stdout
          --dry-run               analyze only, do not save obfuscated files
        
          --erase-methtype        erase methType section (objc/runtime.h methods may work incorrectly)
          -D, --machoview-doom    MachOViewDoom, MachOView crashes after trying to open your binary (doesn't work with caesarMangler)
          --swift-reflection      obfuscate Swift reflection sections (typeref and reflstr). May cause problems for Swift >= 4.2

          --objc-blacklist-class NAME[,NAME...]     do not obfuscate given classes. Option may occur mutliple times.
          --objc-blacklist-class-regex REGEXP       do not obfuscate classes matching given regular expression. Option may occur mutliple times.
          --objc-blacklist-selector NAME[,NAME...]  do not obfuscate given selectors. Option may occur mutliple times.
          --objc-blacklist-selector-regex REGEXP    do not obfuscate selectors matching given regular expression. Option may occur mutliple times.

          --preserve-symtab       do not erase SYMTAB strings
          --erase-section SEGMENT,SECTION    erase given section, for example: __TEXT,__swift5_reflstr
        
          --erase-source-file-names PREFIX   erase source file paths from binary. Erases paths starting with given prefix
                                             by replacing them by constant string
          --replace-cstring STRING           replace arbitrary __cstring with given replacement (use with caution). Matches entire string,
          --replace-cstring-with STRING      adds padding 0's if needed. These options must be used as a pair.
        
          --skip-all-frameworks              do not obfuscate frameworks
          --skip-framework framework         do not obfuscate given framework
          --obfuscate-framework framework    obfuscate given framework (whitelist for --skip-all-frameworks)
        
          -m mangler_key,
          --mangler mangler_key   select mangler to generate obfuscated symbols

          --skip-symbols-from-sources PATH
                                  Don't obfuscate all the symbols found in PATH (searches for all nested *.[hm] files).
                                  This option can be used multiple times to add multiple paths.
          --skip-symbols-from-list PATH
                                  Don't obfuscate all the symbols from the list in PATH (symbols need to be new-line
                                  separated). This option can be used multiple times to add multiple lists. `strings`
                                  output can be used as a symbols list.
        
          --report-to-console     report obfuscated symbols mapping to console

        Development options:
          --xx-no-analyze-dependencies       do not analyze dependencies
          --xx-dump-metadata                 dump ObjC metadata of images being obfuscated
          --xx-find-symbol NAME[,NAME...]    find given ObjC symbol in all analysed images

        \(SymbolManglers.helpSummary)
        """
    }
}
