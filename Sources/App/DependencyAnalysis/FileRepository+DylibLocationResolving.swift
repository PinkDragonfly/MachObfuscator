import Foundation

extension FileRepository {
    func resolvedDylibLocations(loader: URL, rpathsAccumulator: RpathsAccumulator, dependencyNodeLoader: DependencyNodeLoader) -> [String: URL] {
        let loaderPath = loader.deletingLastPathComponent()
//        print("__> Loader Path: \(loaderPath)")
        
        guard let nodes = try? dependencyNodeLoader.load(forURL: loader) else {
            LOGGER.warn("Unable to load \(loader)")
            return [:]
        }
        
        nodes.forEach { node in
            rpathsAccumulator.add(rpaths: node.rpaths, loaderPath: loaderPath, platform: node.platform)
        }
        
        let dylibAndResolvedLocationPairs: [(String, URL)] = nodes.flatMap { node in
            node.dylibs.compactMap { dylibPath in
                guard let resolverDylibLocation = rpathsAccumulator.resolve(dylibEntry: dylibPath,
                                                                            loaderPath: loaderPath,
                                                                            platform: node.platform,
                                                                            fileRepository: self) else {
                    LOGGER.warn("Unable to resolve dylib path \(dylibPath)")
                    return nil
                }
                return (dylibPath, resolverDylibLocation)
            }
        }
        
        /** dylibAndResolvedLocationPairs
         * 将Dylib动态库与对应的文件路径对应起来
         * "/System/Library/Frameworks/Security.framework/Security" : "file:///Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/Security.framework/Security"

         */
//        print("__> DylibAndResolvedLocationPairs: \(dylibAndResolvedLocationPairs)")
        
        // `cstrings` could contain paths for dynamicaly loaded libraries. Let's try to parse `cstrings` the same way as [`cstrings` 可以包含动态加载库的路径。让我们尝试以与以下相同的方式解析“cstrings”]
        // dylib paths, skipping any error silently. [dylib 路径，静默跳过任何错误。]
        let cstringsAndResolvedLocationPairs: [(String, URL)] = nodes.flatMap { node in
            node.cstrings
                .compactMap { cstring in
                    guard let binaryPath = cstring.asLibraryPath,
                        let resolverDylibLocation = rpathsAccumulator.resolve(dylibEntry: binaryPath,
                                                                              loaderPath: loaderPath,
                                                                              platform: node.platform,
                                                                              fileRepository: self) else {
                        // fail silently
                        return nil
                    }
                    return (binaryPath, resolverDylibLocation)
                }
        }
        
        /**
         * CStringsAndResolvedLocationPairs: [("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", file:///Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation), ("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", file:///Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation)]
         */
//        print("__> CStringsAndResolvedLocationPairs: \(cstringsAndResolvedLocationPairs)")
        
        let resolvedLocationPerDylibPath = [String: URL](dylibAndResolvedLocationPairs + cstringsAndResolvedLocationPairs,
                                                         uniquingKeysWith: { path1, path2 in
                                                             if path1 != path2 {
                                                                 fatalError("ambiguous resolved dylib locations in \(self)")
                                                             }
                                                             return path1
        })
        
//        print("__> ResolvedLocationPerDylibPath: \(resolvedLocationPerDylibPath)")
        
        return resolvedLocationPerDylibPath
    }
}

extension String {
    var asLibraryPath: String? {
        // Apps can use `NSBundle.load` to load a framework dynamically. Mach obfuscator needs a path to library file.
        // The library file is located inside the framework and named the same way as the framework.
        let frameworkSuffix = ".framework"
        guard hasPrefix("/"),
            let lastComponent = components(separatedBy: "/").last,
            lastComponent.hasSuffix(frameworkSuffix) else {
            return nil
        }
        let binaryName = lastComponent.dropLast(frameworkSuffix.count)
        return self + String(Paths.separator) + binaryName
    }
}
