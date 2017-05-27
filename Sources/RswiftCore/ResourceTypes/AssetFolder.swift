//
//  AssetFolder.swift
//  R.swift
//
//  Created by Mathijs Kadijk on 09-12-15.
//  From: https://github.com/mac-cain13/R.swift
//  License: MIT License
//

import Foundation

struct AssetFolder: WhiteListedExtensionsResourceType, NamespacedAssetSubfolderType {
  static let supportedExtensions: Set<String> = ["xcassets"]

  // Note: "appiconset" is not loadable by default, so it's not included here
  private static let assetExtensions: Set<String> = ["launchimage", "imageset", "imagestack"]

  // Ignore everything in folders with these extensions
  private static let ignoredExtensions: Set<String> = ["brandassets", "imagestacklayer"]

  // Files checked for asset folder and subfolder properties
  fileprivate static let assetPropertiesFilenames: Array<(fileName: String, fileExtension: String)> = [("Contents","json")]

  let url: URL
  let name: String
  let path = ""
  let resourcePath = ""
  var imageAssets: [String]
  var subfolders: [NamespacedAssetSubfolder]

  init(url: URL, fileManager: FileManager) throws {
    self.url = url
    try AssetFolder.throwIfUnsupportedExtension(url.pathExtension)

    guard let filename = url.filename else {
      throw ResourceParsingError.parsingFailed("Couldn't extract filename from URL: \(url)")
    }
    name = filename

    // Browse asset directory recursively and list only the assets folders
    var assets = [URL]()
    var namespaces = [URL]()
    let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles, errorHandler: nil)
    if let enumerator = enumerator {
      for case let fileURL as URL in enumerator {
        let pathExtension = fileURL.pathExtension
        if fileURL.providesNamespace {
          namespaces.append(fileURL.namespaceURL)
        }
        if AssetFolder.assetExtensions.contains(pathExtension) {
          assets.append(fileURL)
        }
        if AssetFolder.ignoredExtensions.contains(pathExtension) {
          enumerator.skipDescendants()
        }
      }
    }

    subfolders = []
    imageAssets = []
    namespaces.sort { $0.absoluteString < $1.absoluteString }
    namespaces.map(NamespacedAssetSubfolder.init).forEach {
      dive(subfolder: $0)
    }

    assets.forEach {
      dive(asset: $0)
    }
  }
}

fileprivate extension URL {
  var providesNamespace: Bool {
    guard isFileURL else { return false }

    let isPropertiesFile = AssetFolder.assetPropertiesFilenames.contains(where: { (fileName: String, fileExtension: String) -> Bool in
      guard let pathFilename = self.filename else {
        return false
      }
      let pathExtension = self.pathExtension
      return pathFilename == fileName && pathExtension == fileExtension
    })

    guard isPropertiesFile else { return false }
    guard let data = try? Data(contentsOf: self) else { return false }
    guard let json = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) else { return false }
    guard let dict = json as? [String: Any] else { return false }
    guard let properties = dict["properties"] as? [String: Any] else { return false }
    guard let providesNamespace = properties["provides-namespace"] as? Bool else { return false }

    return providesNamespace
  }

  var namespaceURL: URL {
    return deletingLastPathComponent()
  }
}
