//
//  AssetSubfolders.swift
//  rswift
//
//  Created by Tom Lokhorst on 2017-05-27.
//
//

import Foundation

struct AssetSubfolders {
  let folders: [NamespacedAssetSubfolder]
  let duplicates: [NamespacedAssetSubfolder]

  init(all subfolders: [NamespacedAssetSubfolder], assetIdentifiers: [SwiftIdentifier]) {
    var dict: [SwiftIdentifier: NamespacedAssetSubfolder] = [:]

    for subfolder in subfolders {
      let name = SwiftIdentifier(name: subfolder.name)
      if let duplicate = dict[name] {
        duplicate.subfolders += subfolder.subfolders
        duplicate.imageAssets += subfolder.imageAssets
      } else {
        dict[name] = subfolder
      }
    }

    self.folders = dict.values.filter { !assetIdentifiers.contains(SwiftIdentifier(name: $0.name)) }
    self.duplicates = dict.values.filter { assetIdentifiers.contains(SwiftIdentifier(name: $0.name)) }
  }

  func printWarningsForDuplicates() {
    for subfolder in duplicates {
      warn("Skipping asset subfolder because symbol '\(subfolder.name)' would conflict with image: \(subfolder.name)")
    }
  }
}


protocol NamespacedAssetSubfolderType {
  var url: URL { get }
  var name: String { get }
  var path: String { get }
  var resourcePath: String { get }
  var imageAssets: [String] { get set }
  var subfolders: [NamespacedAssetSubfolder] { get set }

  mutating func dive(subfolder: NamespacedAssetSubfolder)
  mutating func dive(asset: URL)
}

extension NamespacedAssetSubfolderType {
  mutating func dive(subfolder: NamespacedAssetSubfolder) {
    if var parent = subfolders.first(where: { subfolder.isSubfolderOf($0) }) {
      parent.dive(subfolder: subfolder)
    } else {
      let name = SwiftIdentifier(name: subfolder.name)
      let resourceName = SwiftIdentifier(rawValue: subfolder.name)
      subfolder.path = path != "" ? "\(path).\(name)" : "\(name)"
      subfolder.resourcePath = resourcePath != "" ? "\(resourcePath)/\(resourceName)" : "\(resourceName)"
      subfolders.append(subfolder)
    }
  }

  mutating func dive(asset: URL) {
    if var parent = subfolders.first(where: { asset.matches($0.url) }) {
      parent.dive(asset: asset)
    } else {
      imageAssets.append(asset.filename!)
    }
  }

  func isSubfolderOf(_ subfolder: NamespacedAssetSubfolder) -> Bool {
    return url.absoluteString != subfolder.url.absoluteString && url.matches(subfolder.url)
  }
}

class NamespacedAssetSubfolder: NamespacedAssetSubfolderType {
  let url: URL
  let name: String
  var path: String = ""
  var resourcePath: String = ""
  var imageAssets: [String] = []
  var subfolders: [NamespacedAssetSubfolder] = []

  init(url: URL) {
    self.url = url
    self.name = url.namespace
  }
}

extension NamespacedAssetSubfolder: ExternalOnlyStructGenerator {
  func generatedStruct(at externalAccessLevel: AccessLevel, prefix: SwiftIdentifier) -> Struct {
    let allFunctions = imageAssets
    let groupedFunctions = allFunctions.groupedBySwiftIdentifier { $0 }

    groupedFunctions.printWarningsForDuplicatesAndEmpties(source: "image", result: "image")


    let assetSubfolders = AssetSubfolders(
      all: subfolders,
      assetIdentifiers: allFunctions.map { SwiftIdentifier(name: $0) })

    assetSubfolders.printWarningsForDuplicates()


    let imagePath = resourcePath + (!path.isEmpty ? "/" : "")
    let structName = SwiftIdentifier(name: self.name)
    let qualifiedName = prefix + structName
    let structs = assetSubfolders.folders
      .map { $0.generatedStruct(at: externalAccessLevel, prefix: qualifiedName) }

    let imageLets = groupedFunctions
      .uniques
      .map { name in
        Let(
          comments: ["Image `\(name)`."],
          accessModifier: externalAccessLevel,
          isStatic: true,
          name: SwiftIdentifier(name: name),
          typeDefinition: .inferred(Type.ImageResource),
          value: "Rswift.ImageResource(bundle: R.hostingBundle, name: \"\(imagePath)\(name)\")"
        )
    }

    return Struct(
      comments: ["This `\(qualifiedName)` struct is generated, and contains static references to \(imageLets.count) images."],
      accessModifier: externalAccessLevel,
      type: Type(module: .host, name: structName),
      implements: [],
      typealiasses: [],
      properties: imageLets,
      functions: groupedFunctions.uniques.map { imageFunction(for: $0, at: externalAccessLevel) },
      structs: structs,
      classes: []
    )
  }

  private func imageFunction(for name: String, at externalAccessLevel: AccessLevel) -> Function {
    return Function(
      comments: ["`UIImage(named: \"\(name)\", bundle: ..., traitCollection: ...)`"],
      accessModifier: externalAccessLevel,
      isStatic: true,
      name: SwiftIdentifier(name: name),
      generics: nil,
      parameters: [
        Function.Parameter(
          name: "compatibleWith",
          localName: "traitCollection",
          type: Type._UITraitCollection.asOptional(),
          defaultValue: "nil"
        )
      ],
      doesThrow: false,
      returnType: Type._UIImage.asOptional(),
      body: "return UIKit.UIImage(resource: R.image.\(path).\(SwiftIdentifier(name: name)), compatibleWith: traitCollection)"
    )
  }
}

fileprivate extension URL {
  var namespace: String {
    return lastPathComponent
  }

  // Returns whether self is descendant of namespace
  func matches(_ namespace: URL) -> Bool {
    return self.absoluteString.hasPrefix(namespace.absoluteString)
  }
}
