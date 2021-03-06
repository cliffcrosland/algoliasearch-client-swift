//
//  Copyright (c) 2015 Algolia
//  http://www.algolia.com/
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
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation


// ----------------------------------------------------------------------------
// IMPLEMENTATION NOTES
// ----------------------------------------------------------------------------
// # Typed vs untyped parameters
//
// All parameters are stored as untyped, string values. They can be
// accessed via the low-level `get` and `set` methods (or the subscript
// operator).
//
// Besides, the class provides typed properties, acting as wrappers on top
// of the untyped storage (i.e. serializing to and parsing from string
// values).
//
// # Bridgeability
//
// **This Swift client must be bridgeable to Objective-C.**
//
// Unfortunately, query parameters with primitive types (Int, Bool...) are not
// bridgeable, because all parameters are optional, and primitive optionals are
// not bridgeable to Objective-C.
//
// To avoid polluting the Swift interface with suboptimal types, the following
// policy is used:
//
// - The `Query` class is exposed to Objective-C as `BaseQuery`.
//
// - A special derived class `_objc_Query` is exposed in Objective-C as `Query`.
//
// - Any Objective-C specific artifact is **not** documented, so that it does
//   not appear in the reference documentation.
//
// - Any parameter whose type is representable in Objective-C is implemented
//   in the `Query` class and marked as `@objc`.
//
// - A parameter whose type is not representable in Objective-C is implemented:
//     - in the `Query` class as a Swift-only type;
//     - in the `_objc_Query` class as an Objective-C compatible type, by an
//       underscore-prefixed property, that is then mapped to the name without
//       underscore in Objective-C. (Is everyone still following?) =:)
//
// This way, each platform sees a properties with the right name and the most
// adequate type. The only drawback is the added clutter:
//
// - The `_objc_Query` class has unfortunately to be visible from Swift, but its
//   odd name should deter any use.
//
// - The `BaseQuery` class is visible from Objective-C and is missing properties.
//   However, since the documentation mentions `Query` and not `BaseQuery`,
//   we hope it will not be too confusing.
//
// ## The case of enums
//
// Enums can only be bridged to Objective-C if their raw type is integral.
// We could do that, but since parameters are optional and optional value types
// cannot be bridged anyway (see above), this would be pointless: the type
// safety of the enum would be lost in the wrapping into `NSNumber`. Therefore,
// enums have a string raw value, and the Objective-C bridge uses a plain
// `NSString`.
//
// ## The case of structs
//
// Auxiliary types used for query parameters, like `LatLng` or `GeoRect`, have
// value semantics. However, structs are not bridgeable to Objective-C. Therefore
// we use plain classes (inheriting from `NSObject`) and we make them immutable.
//
// Equality comparison is implemented in those classes only for the sake of
// testability (we use comparisons extensively in unit tests).
//
// ## Annotations
//
// Properties and methods visible in Objective-C are annotated with `@objc`.
// From an implementation point of view, this is not necessary, because `Query`
// derives from `NSObject` and thus every brdigeable property/method is
// automatically bridged. We use these annotations as hints for maintainers
// (so please keep them).
//
// ----------------------------------------------------------------------------


/// A pair of (latitude, longitude).
/// Used in geo-search.
///
@objc public class LatLng: NSObject {
    // IMPLEMENTATION NOTE: Cannot be `struct` because of Objective-C bridgeability.
    
    /// Latitude.
    public let lat: Double
    
    /// Longitude.
    public let lng: Double
    
    /// Create a geo location.
    ///
    /// - parameter lat: Latitude.
    /// - parameter lng: Longitude.
    ///
    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }
    
    // MARK: Equatable
    
    public override func isEqual(_ object: Any?) -> Bool {
        if let rhs = object as? LatLng {
            return self.lat == rhs.lat && self.lng == rhs.lng
        } else {
            return false
        }
    }
}


/// A rectangle in geo coordinates.
/// Used in geo-search.
///
@objc public class GeoRect: NSObject {
    // IMPLEMENTATION NOTE: Cannot be `struct` because of Objective-C bridgeability.
    
    /// One of the rectangle's corners (typically the northwesternmost).
    public let p1: LatLng
    
    /// Corner opposite from `p1` (typically the southeasternmost).
    public let p2: LatLng
    
    /// Create a geo rectangle.
    ///
    /// - parameter p1: One of the rectangle's corners (typically the northwesternmost).
    /// - parameter p2: Corner opposite from `p1` (typically the southeasternmost).
    ///
    public init(p1: LatLng, p2: LatLng) {
        self.p1 = p1
        self.p2 = p2
    }
    
    public override func isEqual(_ object: Any?) -> Bool {
        if let rhs = object as? GeoRect {
            return self.p1 == rhs.p1 && self.p2 == rhs.p2
        } else {
            return false
        }
    }
}


/// Describes all parameters of a search query.
///
/// There are two ways to access parameters:
///
/// 1. Using the high-level, **typed properties** for individual parameters (recommended).
/// 2. Using the low-level, **untyped accessors** `parameter(withName:)` and `setParameter(withName:to:)` or (better)
///    the **subscript operator**. Use this approach if the parameter you wish to set is not supported by this class.
///
/// + Warning: All parameters are **optional**. When a parameter is `nil`, the API applies a default value.
///
@objc(BaseQuery) // moved away in Objective-C; "real" class is below
public class Query : NSObject, NSCopying {
    
    // MARK: - Low-level (untyped) parameters
    
    /// Parameters, as untyped values.
    private var parameters: [String: String] = [:]
    
    /// Get a parameter in an untyped fashion.
    ///
    /// - parameter name:   The parameter's name.
    /// - returns: The parameter's value, or nil if a parameter with the specified name does not exist.
    ///
    @objc public func parameter(withName name: String) -> String? {
        return parameters[name]
    }
    
    /// Set a parameter in an untyped fashion.
    /// This low-level accessor is intended to access parameters that this client does not yet support.
    ///
    /// - parameter name:   The parameter's name.
    /// - parameter value:  The parameter's value, or nill to remove it.
    ///
    @objc public func setParameter(withName name: String, to value: String?) {
        if value == nil {
            parameters.removeValue(forKey: name)
        } else {
            parameters[name] = value!
        }
    }
    
    /// Convenience shortcut to `parameter(withName:)` and `setParameter(withName:to:)`.
    @objc public subscript(index: String) -> String? {
        get {
            return parameter(withName: index)
        }
        set(newValue) {
            setParameter(withName: index, to: newValue)
        }
    }
    
    // MARK: -
    
    // MARK: Full text search parameters

    /// The instant-search query string, all words of the query are interpreted as prefixes (for example “John Mc” will
    /// match “John Mccamey” and “Johnathan Mccamey”). If no query parameter is set, retrieves all objects.
    @objc public var query: String? {
        get { return self["query"] }
        set { self["query"] = newValue }
    }
    
    /// Values applicable to the `queryType` parameter.
    public enum QueryType: String {
        /// All query words are interpreted as prefixes.
        case prefixAll = "prefixAll"
        /// Only the last word is interpreted as a prefix (default behavior).
        case prefixLast = "prefixLast"
        /// No query word is interpreted as a prefix. This option is not recommended.
        case prefixNone = "prefixNone"
    }
    /// Selects how the query words are interpreted:
    /// - `prefixAll`: all query words are interpreted as prefixes
    /// - `prefixLast`: only the last word is interpreted as a prefix (default behavior)
    /// - `prefixNone`: no query word is interpreted as a prefix. This option is not recommended.
    public var queryType: QueryType? {
        get {
            if let value = self["queryType"] {
                return QueryType(rawValue: value)
            } else {
                return nil
            }
        }
        set {
            self["queryType"] = newValue?.rawValue
        }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// Values applicable to the `typoTolerance` parameter.
    public enum TypoTolerance: String {
        /// Activate typo tolerance entirely.
        case `true` = "true"
        /// De-activate typo tolerance entirely.
        case `false` = "false"
        /// Keep only results with the lowest number of typo. For example if one result match without typos, then
        /// all results with typos will be hidden.
        case min = "min"
        /// If there is a match without typo, then all results with 2 typos or more will be removed. This
        /// option is useful if you want to avoid as much as possible false positive.
        case strict = "strict"
    }
    /// This setting has four different options:
    /// - `true`: activate the typo-tolerance.
    /// - `false`: disable the typo-tolerance.
    /// - `min`: keep only results with the lowest number of typo. For example if one result match without typos, then
    ///   all results with typos will be hidden.
    /// - `strict`: if there is a match without typo, then all results with 2 typos or more will be removed. This
    /// option is useful if you want to avoid as much as possible false positive.
    public var typoTolerance: TypoTolerance? {
        get {
            if let value = self["typoTolerance"] {
                return TypoTolerance(rawValue: value)
            } else {
                return nil
            }
        }
        set {
            self["typoTolerance"] = newValue?.rawValue
        }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`

    /// The minimum number of characters in a query word to accept one typo in this word.
    public var minWordSizefor1Typo: UInt? {
        get { return Query.parseUInt(self["minWordSizefor1Typo"]) }
        set { self["minWordSizefor1Typo"] = Query.buildUInt(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// The minimum number of characters in a query word to accept two typos in this word.
    public var minWordSizefor2Typos: UInt? {
        get { return Query.parseUInt(self["minWordSizefor2Typos"]) }
        set { self["minWordSizefor2Typos"] = Query.buildUInt(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`

    /// If set to false, disable typo-tolerance on numeric tokens (=numbers) in the query word. For example the query
    /// "304" will match with "30450", but not with "40450" that would have been the case with typo-tolerance enabled.
    /// Can be very useful on serial numbers and zip codes searches.
    public var allowTyposOnNumericTokens: Bool? {
        get { return Query.parseBool(self["allowTyposOnNumericTokens"]) }
        set { self["allowTyposOnNumericTokens"] = Query.buildBool(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// If set to true, simple plural forms won’t be considered as typos (for example car/cars will be considered as
    /// equal).
    public var ignorePlurals: Bool? {
        get { return Query.parseBool(self["ignorePlurals"]) }
        set { self["ignorePlurals"] = Query.buildBool(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// List of attributes you want to use for textual search (must be a subset of the `searchableAttributes` index setting).
    /// Attributes are separated with a comma (for example "name,address" ), you can also use a JSON string array
    /// encoding (for example encodeURIComponent('["name","address"]') ). By default, all attributes specified in
    /// `searchableAttributes` settings are used to search.
    @objc public var restrictSearchableAttributes: [String]? {
        get { return Query.parseStringArray(self["restrictSearchableAttributes"]) }
        set { self["restrictSearchableAttributes"] = Query.buildJSONArray(newValue) }
    }
    
    /// Enable the advanced query syntax.
    public var advancedSyntax: Bool? {
        get { return Query.parseBool(self["advancedSyntax"]) }
        set { self["advancedSyntax"] = Query.buildBool(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// If set to false, this query will not be taken into account for the Analytics.
    public var analytics: Bool? {
        get { return Query.parseBool(self["analytics"]) }
        set { self["analytics"] = Query.buildBool(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// If set, tag your query with the specified identifiers. Tags can then be used in the Analytics to analyze a
    /// subset of searches only.
    @objc public var analyticsTags: [String]? {
        get { return Query.parseStringArray(self["analyticsTags"]) }
        set { self["analyticsTags"] = Query.buildJSONArray(newValue) }
    }
    
    /// If set to false, this query will not use synonyms defined in configuration.
    public var synonyms: Bool? {
        get { return Query.parseBool(self["synonyms"]) }
        set { self["synonyms"] = Query.buildBool(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// If set to false, words matched via synonyms expansion will not be replaced by the matched synonym in the
    /// highlighted result.
    public var replaceSynonymsInHighlight: Bool? {
        get { return Query.parseBool(self["replaceSynonymsInHighlight"]) }
        set { self["replaceSynonymsInHighlight"] = Query.buildBool(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// Specify a list of words that should be considered as optional when found in the query. This list will be
    /// appended to the one defined in your index settings.
    @objc public var optionalWords: [String]? {
        get { return Query.parseStringArray(self["optionalWords"]) }
        set { self["optionalWords"] = Query.buildJSONArray(newValue) }
    }

    /// Configure the precision of the proximity ranking criterion. By default, the minimum (and best) proximity value
    /// distance between 2 matching words is 1. Setting it to 2 (or 3) would allow 1 (or 2) words to be found between
    /// the matching words without degrading the proximity ranking value.
    ///
    /// Considering the query “javascript framework”, if you set minProximity=2 the records “JavaScript framework” and
    /// “JavaScript charting framework” will get the same proximity score, even if the second one contains a word
    /// between the 2 matching words.
    public var minProximity: UInt? {
        get { return Query.parseUInt(self["minProximity"]) }
        set { self["minProximity"] = Query.buildUInt(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`

    /// Applicable values for the `removeWordsIfNoResults` parameter.
    public enum RemoveWordsIfNoResults: String {
        /// No specific processing is done when a query does not return any result.
        ///
        /// + Warning: Beware of confusion with `Optional.none` when using type inference!
        ///
        case none = "none"
        /// When a query does not return any result, the last word will be added as optionalWords (the
        /// process is repeated with the n-1 word, n-2 word, … until there is results). This option is particularly
        /// useful on e-commerce websites.
        case lastWords = "lastWords"
        /// When a query does not return any result, the first word will be added as optionalWords (the
        /// process is repeated with the second word, third word, … until there is results). This option is useful on
        /// address search.
        case firstWords = "firstWords"
        /// When a query does not return any result, a second trial will be made with all words as
        /// optional (which is equivalent to transforming the AND operand between query terms in a OR operand)
        case allOptional = "allOptional"
    }
    /// Configure the way query words are removed when the query doesn’t retrieve any results. This option can be used
    /// to avoid having an empty result page. There are four different options:
    /// - `lastWords`: when a query does not return any result, the last word will be added as optionalWords (the
    ///   process is repeated with the n-1 word, n-2 word, … until there is results). This option is particularly
    ///   useful on e-commerce websites
    /// - `firstWords`: when a query does not return any result, the first word will be added as optionalWords (the
    ///   process is repeated with the second word, third word, … until there is results). This option is useful on
    ///   address search
    /// - `allOptional`: When a query does not return any result, a second trial will be made with all words as
    ///   optional (which is equivalent to transforming the AND operand between query terms in a OR operand)
    /// - `none`: No specific processing is done when a query does not return any result.
    public var removeWordsIfNoResults: RemoveWordsIfNoResults? {
        get {
            if let value = self["removeWordsIfNoResults"] {
                return RemoveWordsIfNoResults(rawValue: value)
            } else {
                return nil
            }
        }
        set {
            self["removeWordsIfNoResults"] = newValue?.rawValue
        }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// List of attributes on which you want to disable typo tolerance (must be a subset of the `searchableAttributes`
    /// index setting).
    @objc public var disableTypoToleranceOnAttributes: [String]? {
        get { return Query.parseStringArray(self["disableTypoToleranceOnAttributes"]) }
        set { self["disableTypoToleranceOnAttributes"] = Query.buildJSONArray(newValue) }
    }
    
    /// Applicable values for the `removeStopWords` parameter.
    public enum RemoveStopWords: Equatable {
        /// Enable/disable stop words on all supported languages.
        case all(Bool)
        /// Enable stop words on a specific set of languages, identified by their ISO code.
        case selected([String])
        
        // NOTE: Associated values disable automatic conformance to `Equatable`, so we have to implement it ourselves.
        static public func ==(lhs: RemoveStopWords, rhs: RemoveStopWords) -> Bool {
            switch (lhs, rhs) {
            case (let .all(lhsValue), let .all(rhsValue)): return lhsValue == rhsValue
            case (let .selected(lhsValue), let .selected(rhsValue)): return lhsValue == rhsValue
            default: return false
            }
        }
    }

    /// Remove stop words from query before executing it.
    /// It can be a boolean: enable or disable all 41 supported languages or a comma separated string with the list of
    /// languages you have in your record (using language iso code). In most use-cases, we don’t recommend enabling
    /// this option.
    ///
    /// Stop words removal is applied on query words that are not interpreted as a prefix. The behavior depends of the
    /// `queryType` parameter:
    ///
    /// - `queryType=prefixLast` means the last query word is a prefix and it won’t be considered for stop words removal
    /// - `queryType=prefixNone` means no query word are prefix, stop words removal will be applied on all query words
    /// - `queryType=prefixAll` means all query terms are prefix, stop words won’t be removed
    ///
    /// This parameter is useful when you have a query in natural language like “what is a record?”. In this case,
    /// before executing the query, we will remove “what”, “is” and “a” in order to just search for “record”. This
    /// removal will remove false positive because of stop words, especially when combined with optional words.
    /// For most use cases, it is better to do not use this feature as people search by keywords on search engines.
    public var removeStopWords: RemoveStopWords? {
        get {
            let stringValue = self["removeStopWords"]
            if let boolValue = Query.parseBool(stringValue) {
                return .all(boolValue)
            } else if let arrayValue = Query.parseStringArray(stringValue) {
                return .selected(arrayValue)
            } else {
                return nil
            }
        }
        set {
            if let newValue = newValue {
                switch newValue {
                case let .all(boolValue): self["removeStopWords"] = Query.buildBool(boolValue)
                case let .selected(arrayValue): self["removeStopWords"] = Query.buildStringArray(arrayValue)
                }
            } else {
                self["removeStopWords"] = nil
            }
        }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// Applicable values for the `exactOnSingleWordQuery` parameter.
    public enum ExactOnSingleWordQuery: String {
        /// No exact on single word query.
        ///
        /// + Warning: Beware of confusion with `Optional.none` when using type inference!
        ///
        case none = "none"
        /// Exact set to 1 if the query word is found in the record. The query word needs to have at least 3 chars and
        /// not be part of our stop words dictionary.
        case word = "word"
        /// (Default) Exact set to 1 if there is an attribute containing a string equals to the query.
        case attribute = "attribute"
    }
    /// This parameter control how the exact ranking criterion is computed when the query contains one word.
    public var exactOnSingleWordQuery: ExactOnSingleWordQuery? {
        get {
            if let value = self["exactOnSingleWordQuery"] {
                return ExactOnSingleWordQuery(rawValue: value)
            } else {
                return nil
            }
        }
        set {
            self["exactOnSingleWordQuery"] = newValue?.rawValue
        }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// Applicable values for the `alternativesAsExact` parameter.
    public enum AlternativesAsExact: String {
        /// Alternative word added by the ignore plurals feature.
        case ignorePlurals = "ignorePlurals"
        /// Single word synonym (For example “NY” = “NYC”).
        case singleWordSynonym = "singleWordSynonym"
        /// Synonym over multiple words (For example “NY” = “New York”).
        case multiWordsSynonym = "multiWordsSynonym"
    }
    /// Specify the list of approximation that should be considered as an exact match in the ranking formula.
    ///
    /// - `ignorePlurals`: alternative word added by the ignore plurals feature
    /// - `singleWordSynonym`: single word synonym (For example “NY” = “NYC”)
    /// - `multiWordsSynonym`: synonym over multiple words (For example “NY” = “New York”)
    ///
    /// The default value is `ignorePlurals,singleWordSynonym`.
    ///
    public var alternativesAsExact: [AlternativesAsExact]? {
        get {
            guard let rawValues = Query.parseStringArray(self["alternativesAsExact"]) else {
                return nil
            }
            var values = [AlternativesAsExact]()
            for rawValue in rawValues {
                if let value = AlternativesAsExact(rawValue: rawValue) {
                    values.append(value)
                }
            }
            return values
        }
        set {
            var rawValues: [String]?
            if newValue != nil {
                rawValues = []
                for value in newValue! {
                    rawValues?.append(value.rawValue)
                }
            }
            self["alternativesAsExact"] = Query.buildStringArray(rawValues)
        }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    // MARK: Pagination parameters
    
    /// Pagination parameter used to select the page to retrieve. Page is zero-based and defaults to 0. Thus, to
    /// retrieve the 10th page you need to set `page=9`
    public var page: UInt? {
        get { return Query.parseUInt(self["page"]) }
        set { self["page"] = Query.buildUInt(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// Pagination parameter used to select the number of hits per page. Defaults to 20.
    public var hitsPerPage: UInt? {
        get { return Query.parseUInt(self["hitsPerPage"]) }
        set { self["hitsPerPage"] = Query.buildUInt(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    // MARK: Parameters to control results content
    
    /// List of object attributes you want to retrieve (let you minimize the answer size). You can also use `*` to
    /// retrieve all values when an `attributesToRetrieve` setting is specified for your index.
    /// By default all attributes are retrieved.
    @objc public var attributesToRetrieve: [String]? {
        get { return Query.parseStringArray(self["attributesToRetrieve"]) }
        set { self["attributesToRetrieve"] = Query.buildJSONArray(newValue) }
    }
    
    /// List of attributes you want to highlight according to the query. If an attribute has no match for the query,
    /// the raw value is returned. By default all indexed text attributes are highlighted. You can use `*` if you want
    /// to highlight all textual attributes. Numerical attributes are not highlighted. A `matchLevel` is returned for
    /// each highlighted attribute and can contain:
    /// - `full`: if all the query terms were found in the attribute
    /// - `partial`: if only some of the query terms were found
    /// - `none`: if none of the query terms were found
    @objc public var attributesToHighlight: [String]? {
        get { return Query.parseStringArray(self["attributesToHighlight"]) }
        set { self["attributesToHighlight"] = Query.buildJSONArray(newValue) }
    }
    
    /// List of attributes to snippet alongside the number of words to return (syntax is `attributeName:nbWords`).
    /// By default no snippet is computed.
    @objc public var attributesToSnippet: [String]? {
        get { return Query.parseStringArray(self["attributesToSnippet"]) }
        set { self["attributesToSnippet"] = Query.buildJSONArray(newValue) }
    }
    
    /// If set to true, the result hits will contain ranking information in `_rankingInfo` attribute.
    public var getRankingInfo: Bool? {
        get { return Query.parseBool(self["getRankingInfo"]) }
        set { self["getRankingInfo"] = Query.buildBool(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// Specify the string that is inserted before the highlighted parts in the query result (defaults to `<em>`).
    @objc public var highlightPreTag: String? {
        get { return self["highlightPreTag"] }
        set { self["highlightPreTag"] = newValue }
    }
    
    /// Specify the string that is inserted after the highlighted parts in the query result (defaults to `</em>`)
    @objc public var highlightPostTag: String? {
        get { return self["highlightPostTag"] }
        set { self["highlightPostTag"] = newValue }
    }
    
    /// String used as an ellipsis indicator when a snippet is truncated (defaults to empty).
    @objc public var snippetEllipsisText : String? {
        get { return self["snippetEllipsisText"] }
        set { self["snippetEllipsisText"] = newValue }
    }
    
    // MARK: Numeric search parameters

    /// Filter on numeric attributes.
    @objc public var numericFilters: [Any]? {
        get { return Query.parseJSONArray(self["numericFilters"]) }
        set { self["numericFilters"] = Query.buildJSONArray(newValue) }
    }
    
    // MARK: Category search parameters

    /// Filter the query by a set of tags.
    @objc public var tagFilters: [Any]? {
        get { return Query.parseJSONArray(self["tagFilters"]) }
        set { self["tagFilters"] = Query.buildJSONArray(newValue) }
    }
    
    // MARK: Distinct parameter

    /// Enable the distinct feature (disabled by default) if the attributeForDistinct index setting is set. This
    /// feature is similar to the SQL “distinct” keyword: when enabled in a query with the `distinct=1` parameter,
    /// all hits containing a duplicate value for the `attributeForDistinct` attribute are removed from results.
    /// For example, if the chosen attribute is `_showname` and several hits have the same value for `_showname`, then
    /// only the best one is kept and others are removed.
    public var distinct: UInt? {
        get { return Query.parseUInt(self["distinct"]) }
        set { self["distinct"] = Query.buildUInt(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    // MARK: Faceting parameters
    
    /// List of object attributes that you want to use for faceting. Only attributes that have been added in
    /// `attributesForFaceting` index setting can be used in this parameter. You can also use `*` to perform faceting
    /// on all attributes specified in `attributesForFaceting`. If the number of results is important, the count can
    /// be approximate, the attribute `exhaustiveFacetsCount` in the response is true when the count is exact.
    @objc public var facets: [String]? {
        get { return Query.parseStringArray(self["facets"]) }
        set { self["facets"] = Query.buildJSONArray(newValue) }
    }
    
    /// Filter the query by a list of facets.
    @objc public var facetFilters: [Any]? {
        get { return Query.parseJSONArray(self["facetFilters"]) }
        set { self["facetFilters"] = Query.buildJSONArray(newValue) }
    }
    
    /// Limit the number of facet values returned for each facet. For example: `maxValuesPerFacet=10` will retrieve
    /// max 10 values per facet.
    public var maxValuesPerFacet: UInt? {
        get { return Query.parseUInt(self["maxValuesPerFacet"]) }
        set { self["maxValuesPerFacet"] = Query.buildUInt(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`

    // MARK: Unified filter parameter (SQL like)

    /// Filter the query with numeric, facet or/and tag filters.
    /// The syntax is a SQL like syntax, you can use the OR and AND keywords. The syntax for the underlying numeric,
    /// facet and tag filters is the same than in the other filters:
    ///
    ///     available=1 AND (category:Book OR NOT category:Ebook) AND _publicationdate: 1441745506 TO 1441755506
    ///     AND inStock > 0 AND author:"John Doe"
    ///
    /// The list of keywords is:
    ///
    /// - `OR`: create a disjunctive filter between two filters.
    /// - `AND`: create a conjunctive filter between two filters.
    /// - `TO`: used to specify a range for a numeric filter.
    /// - `NOT`: used to negate a filter. The syntax with the `-` isn't allowed.
    ///
    @objc public var filters: String? {
        get { return self["filters"] }
        set { self["filters"] = newValue }
    }

    // MARK: Geo-search parameters
    
    /// Search for entries around a given latitude/longitude. You can specify the maximum distance in meters with the
    /// `aroundRadius` parameter but we recommend to let it unset and let our automatic radius computation adapt it
    /// depending of the density of the are. At indexing, you should specify the geo-location of an object with the
    /// `_geoloc` attribute (in the form `"_geoloc":{"lat":48.853409, "lng":2.348800}` or
    /// `"_geoloc":[{"lat":48.853409, "lng":2.348800},{"lat":48.547456, "lng":2.972075}]` if you have several
    /// geo-locations in your record).
    @objc public var aroundLatLng: LatLng? {
        get {
            if let fields = self["aroundLatLng"]?.components(separatedBy: ",") {
                if fields.count == 2 {
                    if let lat = Double(fields[0]), let lng = Double(fields[1]) {
                        return LatLng(lat: lat, lng: lng)
                    }
                }
            }
            return nil
        }
        set {
            self["aroundLatLng"] = newValue == nil ? nil : "\(newValue!.lat),\(newValue!.lng)"
        }
    }

    /// Same than aroundLatLng but using IP geolocation instead of manually specified latitude/longitude.
    public var aroundLatLngViaIP: Bool? {
        get { return Query.parseBool(self["aroundLatLngViaIP"]) }
        set { self["aroundLatLngViaIP"] = Query.buildBool(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// Applicable values for the `aroundRadius` parameter.
    public enum AroundRadius: Equatable {
        /// Specify an explicit value (in meters).
        case explicit(UInt)
        
        /// Compute the geo distance without filtering in a geo area.
        /// This option will be faster than specifying a big integer.
        case all

        // NOTE: Associated values disable automatic conformance to `Equatable`, so we have to implement it ourselves.
        static public func ==(lhs: AroundRadius, rhs: AroundRadius) -> Bool {
            switch (lhs, rhs) {
            case (let .explicit(lhsValue), let .explicit(rhsValue)): return lhsValue == rhsValue
            case (.all, .all): return true
            default: return false
            }
        }
    }
    
    /// Control the radius associated with a `aroundLatLng` or `aroundLatLngViaIP` query.
    /// If not set, the radius is computed automatically using the density of the area. You can retrieve the computed
    /// radius in the `automaticRadius` attribute of the answer. You can also specify a minimum value for the automatic
    /// radius by using the `minimumAroundRadius` query parameter. You can specify `.all` if you want to
    /// compute the geo distance without filtering in a geo area (this option will be faster than specifying a big
    /// integer).
    ///
    public var aroundRadius: AroundRadius? {
        get {
            if let stringValue = self["aroundRadius"] {
                if stringValue == "all" {
                    return .all
                } else if let value = Query.parseUInt(stringValue) {
                    return .explicit(value)
                }
            }
            return nil
        }
        set {
            if let newValue = newValue {
                switch newValue {
                case let .explicit(value): self["aroundRadius"] = Query.buildUInt(value)
                case .all: self["aroundRadius"] = "all"
                }
            } else {
                self["aroundRadius"] = nil
            }
        }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`

    /// Control the precision of a `aroundLatLng` query. In meter. For example if you set `aroundPrecision=100`, two
    /// objects that are in the range 0-99m will be considered as identical in the ranking for the .variable geo
    /// ranking parameter (same for 100-199, 200-299, … ranges).
    public var aroundPrecision: UInt? {
        get { return Query.parseUInt(self["aroundPrecision"]) }
        set { self["aroundPrecision"] = Query.buildUInt(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`

    /// Define the minimum radius used for `aroundLatLng` or `aroundLatLngViaIP` when `aroundRadius` is not set. The
    /// radius is computed automatically using the density of the area. You can retrieve the computed radius in the
    /// `automaticRadius` attribute of the answer.
    public var minimumAroundRadius: UInt? {
        get { return Query.parseUInt(self["minimumAroundRadius"]) }
        set { self["minimumAroundRadius"] = Query.buildUInt(newValue) }
    }
    // NOTE: Objective-C bridge moved away to `_objc_Query`
    
    /// Search for entries inside a given area defined by the two extreme points of a rectangle.
    /// You can use several bounding boxes (OR) by passing more than 1 value.
    @objc public var insideBoundingBox: [GeoRect]? {
        get {
            if let fields = self["insideBoundingBox"]?.components(separatedBy: ",") {
                if fields.count % 4 == 0 {
                    var result = [GeoRect]()
                    for i in 0..<(fields.count / 4) {
                        if let lat1 = Double(fields[4 * i + 0]), let lng1 = Double(fields[4 * i + 1]), let lat2 = Double(fields[4 * i + 2]), let lng2 = Double(fields[4 * i + 3]) {
                            result.append(GeoRect(p1: LatLng(lat: lat1, lng: lng1), p2: LatLng(lat: lat2, lng: lng2)))
                        }
                    }
                    return result
                }
            }
            return nil
        }
        set {
            if newValue == nil {
                self["insideBoundingBox"] = nil
            } else {
                var components = [String]()
                for box in newValue! {
                    components.append(String(box.p1.lat))
                    components.append(String(box.p1.lng))
                    components.append(String(box.p2.lat))
                    components.append(String(box.p2.lng))
                }
                self["insideBoundingBox"] = components.joined(separator: ",")
            }
        }
    }

    /// Search entries inside a given area defined by a set of points (defined by a minimum of 3 points).
    /// You can pass several time the insidePolygon parameter to your query, the behavior will be a OR between all those polygons.
    @objc public var insidePolygon: [LatLng]? {
        // FIXME: Union cannot work with this implementation, as at most one occurrence per parameter is supported.
        get {
            if let fields = self["insidePolygon"]?.components(separatedBy: ",") {
                if fields.count % 2 == 0 && fields.count / 2 >= 3 {
                    var result = [LatLng]()
                    for i in 0..<(fields.count / 2) {
                        if let lat = Double(fields[2 * i + 0]), let lng = Double(fields[2 * i + 1]) {
                            result.append(LatLng(lat: lat, lng: lng))
                        }
                    }
                    return result
                }
            }
            return nil
        }
        set {
            if newValue == nil {
                self["insidePolygon"] = nil
            } else {
                assert(newValue!.count >= 3)
                var components = [String]()
                for point in newValue! {
                    components.append(String(point.lat))
                    components.append(String(point.lng))
                }
                self["insidePolygon"] = components.joined(separator: ",")
            }
        }
    }

    // MARK: - Miscellaneous

    @objc override public var description: String {
        get { return "Query{\(parameters)}" }
    }
    
    // MARK: - Initialization

    /// Construct an empty query.
    @objc public override init() {
    }
    
    /// Construct a query with the specified full text query.
    @objc public convenience init(query: String?) {
        self.init()
        self.query = query
    }
    
    /// Construct a query with the specified low-level parameters.
    @objc public init(parameters: [String: String]) {
        self.parameters = parameters
    }
    
    /// Clone an existing query.
    @objc public init(copy: Query) {
        parameters = copy.parameters
    }
    
    /// Support for `NSCopying`.
    ///
    /// + Note: Primarily intended for Objective-C use. Swift coders should use `init(copy:)`.
    ///
    @objc public func copy(with zone: NSZone?) -> Any {
        // NOTE: As per the docs, the zone argument is ignored.
        return Query(copy: self)
    }

    // MARK: Serialization & parsing

    /// Return the final query string used in URL.
    @objc public func build() -> String {
        var components = [String]()
        // Sort parameters by name to get predictable output.
        let sortedParameters = parameters.sorted { $0.0 < $1.0 }
        for (key, value) in sortedParameters {
            let escapedKey = key.urlEncodedQueryParam()
            let escapedValue = value.urlEncodedQueryParam()
            components.append(escapedKey + "=" + escapedValue)
        }
        return components.joined(separator: "&")
    }

    /// Parse a query from a URL query string.
    @objc(parseBaseQuery:) // moved away in Objective-C; "real" implementation is below
    public static func parse(_ queryString: String) -> Query {
        let query = Query()
        parse(queryString, into: query)
        return query
    }
    
    internal static func parse(_ queryString: String, into query: Query) {
        let components = queryString.components(separatedBy: "&")
        for component in components {
            let fields = component.components(separatedBy: "=")
            if fields.count < 1 || fields.count > 2 {
                continue
            }
            if let name = fields[0].removingPercentEncoding {
                let value: String? = fields.count >= 2 ? fields[1].removingPercentEncoding : nil
                if value == nil {
                    query.parameters.removeValue(forKey: name)
                } else {
                    query.parameters[name] = value!
                }
            }
        }
    }
    
    // MARK: Equatable
    
    override public func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Query else {
            return false
        }
        return self.parameters == rhs.parameters
    }
    
    // MARK: - Helper methods to build & parse URL
    
    /// Build a plain, comma-separated array of strings.
    ///
    class func buildStringArray(_ array: [String]?) -> String? {
        if array != nil {
            return array!.joined(separator: ",")
        }
        return nil
    }
    
    class func parseStringArray(_ string: String?) -> [String]? {
        if string != nil {
            // First try to parse the JSON notation:
            do {
                if let array = try JSONSerialization.jsonObject(with: string!.data(using: String.Encoding.utf8)!, options: JSONSerialization.ReadingOptions(rawValue: 0)) as? [String] {
                    return array
                }
            } catch {
            }
            // Fallback on plain string parsing.
            return string!.components(separatedBy: ",")
        }
        return nil
    }
    
    class func buildJSONArray(_ array: [Any]?) -> String? {
        if array != nil {
            do {
                let data = try JSONSerialization.data(withJSONObject: array!, options: JSONSerialization.WritingOptions(rawValue: 0))
                if let string = String(data: data, encoding: String.Encoding.utf8) {
                    return string
                }
            } catch {
            }
        }
        return nil
    }
    
    class func parseJSONArray(_ string: String?) -> [Any]? {
        if string != nil {
            do {
                if let array = try JSONSerialization.jsonObject(with: string!.data(using: String.Encoding.utf8)!, options: JSONSerialization.ReadingOptions(rawValue: 0)) as? [Any] {
                    return array
                }
            } catch {
            }
        }
        return nil
    }
    
    class func buildUInt(_ int: UInt?) -> String? {
        return int == nil ? nil : String(int!)
    }
    
    class func parseUInt(_ string: String?) -> UInt? {
        if string != nil {
            if let intValue = UInt(string!) {
                return intValue
            }
        }
        return nil
    }
    
    class func buildBool(_ bool: Bool?) -> String? {
        return bool == nil ? nil : String(bool!)
    }
    
    class func parseBool(_ string: String?) -> Bool? {
        if string != nil {
            switch (string!.lowercased()) {
                case "true": return true
                case "false": return false
                default:
                    if let intValue = Int(string!) {
                        return intValue != 0
                    }
            }
        }
        return nil
    }
    
    class func toNumber(_ bool: Bool?) -> NSNumber? {
        return bool == nil ? nil : NSNumber(value: bool!)
    }

    class func toNumber(_ int: UInt?) -> NSNumber? {
        return int == nil ? nil : NSNumber(value: int!)
    }
}

// MARK: - Objective-C bridges

// `Query` class derivation for better Objective-C bridgeability.
//
// NOTE: Should not be used from Swift.
//
// WARNING: Should not be documented.

@objc(Query)
public class _objc_Query: Query {
    /// MARK: `NSCopying` support

    @objc public override func copy(with zone: NSZone?) -> Any {
        // NOTE: As per the docs, the zone argument is ignored.
        return _objc_Query(copy: self)
    }
    
    // MARK: Properties
    
    @objc(queryType)
    public var _queryType: String? {
        get { return queryType?.rawValue }
        set { queryType = newValue == nil ? nil : QueryType(rawValue: newValue!) }
    }

    @objc(typoTolerance)
    public var _typoTolerance: String? {
        get { return typoTolerance?.rawValue }
        set { typoTolerance = newValue == nil ? nil : TypoTolerance(rawValue: newValue!) }
    }

    @objc(minWordSizefor1Typo)
    public var _minWordSizefor1Typo: NSNumber? {
        get { return Query.toNumber(self.minWordSizefor1Typo) }
        set { self.minWordSizefor1Typo = newValue?.uintValue }
    }
    
    @objc(minWordSizefor2Typos)
    public var _minWordSizefor2Typos: NSNumber? {
        get { return Query.toNumber(self.minWordSizefor2Typos) }
        set { self.minWordSizefor2Typos = newValue?.uintValue }
    }
    
    @objc(allowTyposOnNumericTokens)
    public var _allowTyposOnNumericTokens: NSNumber? {
        get { return Query.toNumber(self.allowTyposOnNumericTokens) }
        set { self.allowTyposOnNumericTokens = newValue?.boolValue }
    }

    @objc(ignorePlurals)
    public var _ignorePlurals: NSNumber? {
        get { return Query.toNumber(self.ignorePlurals) }
        set { self.ignorePlurals = newValue?.boolValue }
    }

    @objc(advancedSyntax)
    public var _advancedSyntax: NSNumber? {
        get { return Query.toNumber(self.advancedSyntax) }
        set { self.advancedSyntax = newValue?.boolValue }
    }

    @objc(analytics)
    public var _analytics: NSNumber? {
        get { return Query.toNumber(self.analytics) }
        set { self.analytics = newValue?.boolValue }
    }

    @objc(synonyms)
    public var _synonyms: NSNumber? {
        get { return Query.toNumber(self.synonyms) }
        set { self.synonyms = newValue?.boolValue }
    }

    @objc(replaceSynonymsInHighlight)
    public var _replaceSynonymsInHighlight: NSNumber? {
        get { return Query.toNumber(self.replaceSynonymsInHighlight) }
        set { self.replaceSynonymsInHighlight = newValue?.boolValue }
    }

    @objc(minProximity)
    public var _minProximity: NSNumber? {
        get { return Query.toNumber(self.minProximity) }
        set { self.minProximity = newValue?.uintValue }
    }

    @objc(removeWordsIfNoResults)
    public var _removeWordsIfNoResults: String? {
        get { return removeWordsIfNoResults?.rawValue }
        set { removeWordsIfNoResults = newValue == nil ? nil : RemoveWordsIfNoResults(rawValue: newValue!) }
    }

    @objc(removeStopWords)
    public var _removeStopWords: Any? {
        get {
            if let value = removeStopWords {
                switch value {
                case let .all(boolValue): return NSNumber(value: boolValue)
                case let .selected(arrayValue): return arrayValue
                }
            } else {
                return nil
            }
        }
        set {
            if let boolValue = newValue as? Bool {
                removeStopWords = .all(boolValue)
            } else if let numberValue = newValue as? NSNumber {
                removeStopWords = .all(numberValue.boolValue)
            } else if let arrayValue = newValue as? [String] {
                removeStopWords = .selected(arrayValue)
            } else {
                removeStopWords = nil
            }
        }
    }

    @objc(exactOnSingleWordQuery)
    public var _exactOnSingleWordQuery: String? {
        get { return exactOnSingleWordQuery?.rawValue }
        set { exactOnSingleWordQuery = newValue == nil ? nil : ExactOnSingleWordQuery(rawValue: newValue!) }
    }

    @objc(alternativesAsExact)
    public var _alternativesAsExact: [String]? {
        get {
            if let alternativesAsExact = alternativesAsExact {
                return alternativesAsExact.map({ $0.rawValue })
            } else {
                return nil
            }
        }
        set(stringValues) {
            if let stringValues = stringValues {
                var newValues = [AlternativesAsExact]()
                for stringValue in stringValues {
                    if let newValue = AlternativesAsExact(rawValue: stringValue) {
                        newValues.append(newValue)
                    }
                }
                alternativesAsExact = newValues
            } else {
                alternativesAsExact = nil
            }
        }
    }

    @objc(page)
    public var _page: NSNumber? {
        get { return Query.toNumber(self.page) }
        set { self.page = newValue?.uintValue }
    }

    @objc(hitsPerPage)
    public var _hitsPerPage: NSNumber? {
        get { return Query.toNumber(self.hitsPerPage) }
        set { self.hitsPerPage = newValue?.uintValue }
    }

    @objc(getRankingInfo)
    public var _getRankingInfo: NSNumber? {
        get { return Query.toNumber(self.getRankingInfo) }
        set { self.getRankingInfo = newValue?.boolValue }
    }

    @objc(distinct)
    public var _distinct: NSNumber? {
        get { return Query.toNumber(self.distinct) }
        set { self.distinct = newValue?.uintValue }
    }

    @objc(maxValuesPerFacet)
    public var _maxValuesPerFacet: NSNumber? {
        get { return Query.toNumber(self.maxValuesPerFacet) }
        set { self.maxValuesPerFacet = newValue?.uintValue }
    }

    @objc(aroundLatLngViaIP)
    public var _aroundLatLngViaIP: NSNumber? {
        get { return Query.toNumber(self.aroundLatLngViaIP) }
        set { self.aroundLatLngViaIP = newValue?.boolValue }
    }

    /// Special value for `aroundRadius` to compute the geo distance without filtering.
    @objc public static let aroundRadiusAll: NSNumber = NSNumber(value: UInt.max)

    @objc(aroundRadius)
    public var _aroundRadius: NSNumber? {
        get {
            if let aroundRadius = aroundRadius {
                switch aroundRadius {
                case let .explicit(value): return NSNumber(value: value)
                case .all: return _objc_Query.aroundRadiusAll
                }
            }
            return nil
        }
        set {
            if let newValue = newValue {
                if newValue == _objc_Query.aroundRadiusAll {
                    self.aroundRadius = .all
                } else {
                    self.aroundRadius = .explicit(newValue.uintValue)
                }
            } else {
                self.aroundRadius = nil
            }
        }
    }

    @objc(aroundPrecision)
    public var _aroundPrecision: NSNumber? {
        get { return Query.toNumber(self.aroundPrecision) }
        set { self.aroundPrecision = newValue?.uintValue }
    }

    @objc(minimumAroundRadius)
    public var _minimumAroundRadius: NSNumber? {
        get { return Query.toNumber(self.minimumAroundRadius) }
        set { self.minimumAroundRadius = newValue?.uintValue }
    }

    // MARK: Utils

    @objc(parse:) public static func _parse(_ queryString: String) -> _objc_Query {
        let query = _objc_Query()
        parse(queryString, into: query)
        return query
    }
}
