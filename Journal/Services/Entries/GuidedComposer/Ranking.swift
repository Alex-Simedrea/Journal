import Foundation

enum GuidedComposerNormalization {
    nonisolated static func text(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GuidedComposerRanking {
    static func textScore(query: String, candidates: [String]) -> Int? {
        let query = GuidedComposerNormalization.text(query)
        guard !query.isEmpty else { return 0 }

        let scores = candidates.compactMap { candidate -> Int? in
            let candidate = GuidedComposerNormalization.text(candidate)
            guard !candidate.isEmpty else { return nil }
            if candidate == query { return 10_000 }
            if candidate.hasPrefix(query) { return 8_000 - candidate.count }
            if candidate.split(separator: " ").contains(where: {
                $0.hasPrefix(query)
            }) {
                return 7_000 - candidate.count
            }
            if candidate.contains(query) { return 6_000 - candidate.count }
            let limit = max(1, min(3, query.count / 3))
            guard abs(query.count - candidate.count) <= limit else {
                return nil
            }
            let distance = editDistance(query, candidate)
            guard distance <= limit else { return nil }
            return 4_000 - distance * 250 - candidate.count
        }
        return scores.max()
    }

    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(
                    min(
                        current[rightIndex] + 1,
                        previous[rightIndex + 1] + 1,
                        previous[rightIndex]
                            + (leftCharacter == rightCharacter ? 0 : 1)
                    )
                )
            }
            previous = current
        }
        return previous[right.count]
    }
}

enum GuidedComposerLocationMatcher {
    static func sameLocation(
        _ lhs: ComposerLocationCandidate,
        _ rhs: ComposerLocationCandidate
    ) -> Bool {
        if let lhsPlaceID = lhs.savedPlaceID,
           let rhsPlaceID = rhs.savedPlaceID {
            return lhsPlaceID == rhsPlaceID
        }
        if lhs.id == rhs.id {
            return true
        }
        return sameLocation(lhs.location, rhs.location)
    }

    static func distanceMeters(
        _ lhs: Location,
        _ rhs: Location
    ) -> Double {
        let earthRadius = 6_371_000.0
        let latitude1 = lhs.latitude * .pi / 180
        let latitude2 = rhs.latitude * .pi / 180
        let latitudeDelta = (rhs.latitude - lhs.latitude) * .pi / 180
        let longitudeDelta = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    static func sameLocation(
        _ lhs: Location,
        _ rhs: Location
    ) -> Bool {
        let distance = distanceMeters(lhs, rhs)
        guard distance <= GuidedComposerPolicy.duplicateLocationRadiusMeters
        else {
            return false
        }
        let lhsTerms = identityTerms(for: lhs)
        let rhsTerms = identityTerms(for: rhs)
        if !lhsTerms.isEmpty, !rhsTerms.isEmpty {
            return !lhsTerms.isDisjoint(with: rhsTerms)
        }
        return distance <= GuidedComposerPolicy.coordinateIdentityRadiusMeters
    }

    static func withinDistance(
        _ lhs: Location,
        _ rhs: Location,
        thresholdMeters: Double
    ) -> Bool {
        distanceMeters(lhs, rhs) <= thresholdMeters
    }

    private static func identityTerms(for location: Location) -> Set<String> {
        Set(
            [
                location.displayName,
                location.compactAddress,
                location.formattedAddress,
            ].compactMap { $0 }.compactMap {
                let normalized = GuidedComposerNormalization.text($0)
                return normalized.isEmpty ? nil : normalized
            }
        )
    }
}

enum GuidedComposerLocationRanking {
    static func deduplicated(
        _ candidates: [ComposerLocationCandidate]
    ) -> [ComposerLocationCandidate] {
        var result: [ComposerLocationCandidate] = []
        for candidate in candidates {
            if let index = result.firstIndex(where: {
                isDuplicate($0, candidate)
            }) {
                result[index] = merged(result[index], candidate)
            } else {
                result.append(candidate)
            }
        }
        return result
    }

    static func contextScore(
        candidate: ComposerLocationCandidate,
        otherEndpoint: ComposerLocationCandidate?
    ) -> Int {
        var score = candidate.source == .savedPlace ? 400 : 0
        score += min(candidate.usageCount, 100) * 10
        if let lastVisitedAt = candidate.lastVisitedAt {
            let days = max(
                0,
                Date.now.timeIntervalSince(lastVisitedAt) / 86_400
            )
            score += max(0, 250 - Int(days))
        }
        if isHome(candidate), let otherEndpoint {
            let distance = GuidedComposerLocationMatcher.distanceMeters(
                candidate.location,
                otherEndpoint.location
            )
            score += max(0, 600 - Int(distance / 1_000))
        }
        return score
    }

    static func suggestionScore(
        query: String,
        candidate: ComposerLocationCandidate,
        otherEndpoint: ComposerLocationCandidate?,
        currentLocation: Location?
    ) -> Int? {
        let normalizedQuery = GuidedComposerNormalization.text(query)
        if normalizedQuery.isEmpty {
            guard candidate.source == .savedPlace else { return nil }
            guard let currentLocation else {
                return 10_000 + contextScore(
                    candidate: candidate,
                    otherEndpoint: otherEndpoint
                )
            }
            let distance = GuidedComposerLocationMatcher.distanceMeters(
                candidate.location,
                currentLocation
            )
            return 20_000
                - min(15_000, Int(distance / 10))
                + min(candidate.usageCount, 100)
        }

        guard let textScore = GuidedComposerRanking.textScore(
            query: query,
            candidates: candidate.allSearchTerms
        ) else {
            return nil
        }
        return textScore
            + contextScore(
                candidate: candidate,
                otherEndpoint: otherEndpoint
            )
            + proximityScore(
                candidate: candidate,
                currentLocation: currentLocation
            )
    }

    static func proximityScore(
        candidate: ComposerLocationCandidate,
        currentLocation: Location?
    ) -> Int {
        guard let currentLocation else { return 0 }
        let distance = GuidedComposerLocationMatcher.distanceMeters(
            candidate.location,
            currentLocation
        )
        let logarithmicDistance = log10(max(distance, 1))
        return max(0, 600 - Int(logarithmicDistance * 100))
    }

    static func isHome(_ candidate: ComposerLocationCandidate) -> Bool {
        GuidedComposerNormalization.text(candidate.displayName)
            .split { character in
                !character.isLetter && !character.isNumber
            }
            .contains("home")
    }

    static func rankedHomeCandidates(
        _ candidates: [ComposerLocationCandidate],
        near endpoint: ComposerLocationCandidate,
        maximumAdditionalDistanceMeters: Double =
            GuidedComposerPolicy.maximumHomeDistanceMeters
    ) -> [ComposerLocationCandidate] {
        let ranked = candidates.filter { candidate in
            isHome(candidate)
                && !GuidedComposerLocationMatcher.sameLocation(
                    candidate,
                    endpoint
                )
        }.sorted { left, right in
            let leftDistance = GuidedComposerLocationMatcher.distanceMeters(
                left.location,
                endpoint.location
            )
            let rightDistance = GuidedComposerLocationMatcher.distanceMeters(
                right.location,
                endpoint.location
            )
            if leftDistance == rightDistance {
                return left.id < right.id
            }
            return leftDistance < rightDistance
        }
        guard let closest = ranked.first else { return [] }
        guard GuidedComposerLocationMatcher.distanceMeters(
            closest.location,
            endpoint.location
        ) <= maximumAdditionalDistanceMeters else {
            return []
        }
        return [closest] + ranked.dropFirst().filter { candidate in
            GuidedComposerLocationMatcher.distanceMeters(
                candidate.location,
                endpoint.location
            ) <= maximumAdditionalDistanceMeters
        }
    }

    private static func isDuplicate(
        _ lhs: ComposerLocationCandidate,
        _ rhs: ComposerLocationCandidate
    ) -> Bool {
        guard GuidedComposerLocationMatcher.withinDistance(
            lhs.location,
            rhs.location,
            thresholdMeters:
                GuidedComposerPolicy.duplicateLocationRadiusMeters
        ) else {
            return false
        }
        let leftNames = Set(
            ([lhs.displayName] + lhs.aliases + [
                lhs.location.compactAddress,
                lhs.location.formattedAddress,
            ].compactMap { $0 }).map(GuidedComposerNormalization.text)
                .filter { !$0.isEmpty }
        )
        let rightNames = Set(
            ([rhs.displayName] + rhs.aliases + [
                rhs.location.compactAddress,
                rhs.location.formattedAddress,
            ].compactMap { $0 }).map(GuidedComposerNormalization.text)
                .filter { !$0.isEmpty }
        )
        return !leftNames.isDisjoint(with: rightNames)
    }

    private static func merged(
        _ lhs: ComposerLocationCandidate,
        _ rhs: ComposerLocationCandidate
    ) -> ComposerLocationCandidate {
        let preferred: ComposerLocationCandidate
        let supplemental: ComposerLocationCandidate
        if rhs.source == .savedPlace, lhs.source != .savedPlace {
            preferred = rhs
            supplemental = lhs
        } else {
            preferred = lhs
            supplemental = rhs
        }
        return ComposerLocationCandidate(
            id: preferred.id,
            savedPlaceID: preferred.savedPlaceID,
            displayName: preferred.displayName,
            aliases: Array(
                Set(preferred.aliases + supplemental.aliases)
            ).sorted(),
            location: preferred.location,
            systemImage: preferred.systemImage,
            accuracyRadiusMeters: max(
                preferred.accuracyRadiusMeters,
                supplemental.accuracyRadiusMeters
            ),
            usageCount: max(preferred.usageCount, supplemental.usageCount),
            lastVisitedAt: [
                preferred.lastVisitedAt,
                supplemental.lastVisitedAt,
            ].compactMap { $0 }.max(),
            source: preferred.source,
            searchTerms: Array(
                Set(
                    preferred.searchTerms
                        + supplemental.searchTerms
                        + supplemental.allSearchTerms
                )
            ).sorted()
        )
    }
}
