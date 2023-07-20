import Foundation

public func run() {
    let options = Options.fromCommandLine()
    guard !options.help, !options.unknownOption, let manglerType = options.manglerType, let appDirectoryOrFile = options.appDirectoryOrFile else {
        print(Options.usage)
        if options.help {
            return
        } else {
            exit(EXIT_FAILURE)
        }
    }

    LOGGER = SoutLogger(options: options)
    let mangler = manglerType.resolveMangler(machOViewDoomEnabled: options.machOViewDoom)
    
    print("__> AppDirectoryOrFile: \(appDirectoryOrFile)")
    
    let obfuscator = Obfuscator(directoryOrFileURL: appDirectoryOrFile,
                                mangler: mangler,
                                options: options)
    obfuscator.run()
}
