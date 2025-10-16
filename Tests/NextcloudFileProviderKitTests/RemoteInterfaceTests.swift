//  SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: GPL-2.0-or-later

import Alamofire
import Foundation
import NextcloudCapabilitiesKit
@testable import NextcloudFileProviderKit
import NextcloudFileProviderKitMocks
import NextcloudKit
import Testing
@testable import TestInterface

@Suite("RemoteInterface Extension Tests", .serialized)
struct RemoteInterfaceExtensionTests {
    let testAccount = Account(user: "a1", id: "1", serverUrl: "example.com", password: "pass")
    let otherAccount = Account(user: "a2", id: "2", serverUrl: "example.com", password: "word")

    func capabilitiesFromMockJSON(jsonString: String = mockCapabilities) -> (Capabilities, Data) {
        let data = jsonString.data(using: .utf8)!
        let caps = Capabilities(data: data)!
        return (caps, data)
    }

    @Test func currentCapabilitiesReturnsFreshCache() async {
        await RetrievedCapabilitiesActor.shared.reset()
        var remoteInterface = TestableRemoteInterface()
        remoteInterface.fetchCapabilitiesHandler = { _, _, _ in
            Issue.record("fetchCapabilities should NOT be called when cache is fresh.")
            return (testAccount.ncKitAccount, nil, nil, .invalidResponseError)
        }

        let (freshCaps, _) = capabilitiesFromMockJSON()
        let freshDate = Date() // Now

        // Setup: Put fresh data into the shared actor
        await RetrievedCapabilitiesActor.shared.setCapabilities(
            forAccount: testAccount.ncKitAccount,
            capabilities: freshCaps,
            retrievedAt: freshDate
        )

        let result = await remoteInterface.currentCapabilities(account: testAccount)

        #expect(result.error == .success)
        #expect(result.capabilities == freshCaps)
        #expect(result.data == nil, "Data should be nil as no fetch occurred")
        #expect(result.account == testAccount.ncKitAccount)
    }

    @Test func currentCapabilitiesFetchesOnNoCache() async throws {
        await RetrievedCapabilitiesActor.shared.reset()

        let (fetchedCaps, fetchedData) = capabilitiesFromMockJSON()
        var fetcherCalled = false
        var remoteInterface = TestableRemoteInterface()
        remoteInterface.fetchCapabilitiesHandler = { acc, _, _ in
            fetcherCalled = true
            #expect(acc.ncKitAccount == testAccount.ncKitAccount)
            return (acc.ncKitAccount, fetchedCaps, fetchedData, .success)
        }

        let result = await remoteInterface.currentCapabilities(account: testAccount)

        #expect(fetcherCalled, "fetchCapabilities should be called when cache is empty.")
        #expect(result.error == .success)
        #expect(result.capabilities == fetchedCaps)
        #expect(result.data == fetchedData)

        let actorCache = await RetrievedCapabilitiesActor.shared.data
        #expect(actorCache[testAccount.ncKitAccount]?.capabilities == fetchedCaps)
    }

    @Test func currentCapabilitiesFetchesOnStaleCache() async throws {
        await RetrievedCapabilitiesActor.shared.reset()

        let (staleCaps, _) = capabilitiesFromMockJSON(jsonString: """
        {
            "ocs": {
                "meta": {
                    "status": "ok",
                    "statuscode": 100,
                    "message": "OK"
                },
                "data": {
                    "capabilities": {
                        "files": {
                            "undelete": false
                        }
                    }
                }
            }
        }
        """) // Different caps
        let staleDate = Date(timeIntervalSinceNow: -(CapabilitiesFetchInterval + 300)) // Definitely stale

        // Setup: Put stale data into the actor
        await RetrievedCapabilitiesActor.shared.setCapabilities(
            forAccount: testAccount.ncKitAccount,
            capabilities: staleCaps,
            retrievedAt: staleDate
        )

        let (newCaps, newData) = capabilitiesFromMockJSON() // Fresh data to be fetched
        var fetcherCalled = false
        var remoteInterface = TestableRemoteInterface()
        remoteInterface.fetchCapabilitiesHandler = { acc, _, _ in
            fetcherCalled = true
            return (acc.ncKitAccount, newCaps, newData, .success)
        }

        let result = await remoteInterface.currentCapabilities(account: testAccount)

        #expect(fetcherCalled, "fetchCapabilities should be called for stale cache.")
        #expect(result.error == .success)
        #expect(result.capabilities == newCaps, "Should return newly fetched capabilities.")
        #expect(result.data == newData)

        let actorCache = await RetrievedCapabilitiesActor.shared.data
        #expect(actorCache[testAccount.ncKitAccount]?.capabilities == newCaps)
        #expect((actorCache[testAccount.ncKitAccount]?.retrievedAt ?? .distantPast) > staleDate)
    }

    @Test func currentCapabilitiesAwaitsAndUsesCache() async throws {
        await RetrievedCapabilitiesActor.shared.reset()

        let (cachedCaps, cachedData) = capabilitiesFromMockJSON()
        var fetcherCalledCount = 0

        var remoteInterface = TestableRemoteInterface()
        remoteInterface.fetchCapabilitiesHandler = { acc, _, _ in
            fetcherCalledCount += 1
            // This fetcher should not be called if cache is fresh after await.
            return (acc.ncKitAccount, cachedCaps, cachedData, .success)
        }

        // 1. Simulate an external process starting a fetch for testAccount
        await RetrievedCapabilitiesActor.shared.setOngoingFetch(
            forAccount: testAccount.ncKitAccount, ongoing: true
        )

        var currentCapabilitiesReturned = false
        let currentCapabilitiesTask = Task {
            // 2. This call to currentCapabilities should await the ongoing fetch.
            let result = await remoteInterface.currentCapabilities(account: testAccount)
            currentCapabilitiesReturned = true
            // Assertions on the result will be done after the task.
            #expect(result.capabilities == cachedCaps)
            #expect(result.error == .success)
        }

        // 3. Give currentCapabilitiesTask a moment to hit the await.
        try await Task.sleep(for: .milliseconds(100))
        #expect(currentCapabilitiesReturned == false, "currentCapabilities should be awaiting.")

        // 4. Now, the "external" fetch completes and populates the cache.
        await RetrievedCapabilitiesActor.shared.setCapabilities(
            forAccount: testAccount.ncKitAccount,
            capabilities: cachedCaps,
            retrievedAt: Date() // Fresh date
        )
        await RetrievedCapabilitiesActor.shared.setOngoingFetch(
            forAccount: testAccount.ncKitAccount, ongoing: false
        )

        // 5. currentCapabilitiesTask should now complete.
        await currentCapabilitiesTask.value
        #expect(currentCapabilitiesReturned == true)

        // Check if fetchCapabilities was called.
        // If the logic is: await -> check cache -> fetch if needed.
        // And we made cache fresh before await unblocked, it should NOT call fetch.
        #expect(fetcherCalledCount == 0, "fetchCapabilities should not have been called if cache was fresh after await.")
    }

    @Test func supportsTrashTrue() async throws {
        await RetrievedCapabilitiesActor.shared.reset() // Reset shared actor

        // JSON where files.undelete is true (default mockCapabilitiesJSON)
        let (capsWithTrash, dataWithTrash) = capabilitiesFromMockJSON()
        #expect(capsWithTrash.files?.undelete == true)

        var remoteInterface = TestableRemoteInterface()
        remoteInterface.fetchCapabilitiesHandler = { acc, _, _ in
            (acc.ncKitAccount, capsWithTrash, dataWithTrash, .success)
        }
        await RetrievedCapabilitiesActor.shared.setCapabilities(
            forAccount: testAccount.ncKitAccount,
            capabilities: capsWithTrash, // any capability
            retrievedAt: Date(timeIntervalSinceNow: -(CapabilitiesFetchInterval + 100)) // Stale
        )

        let result = await remoteInterface.supportsTrash(account: testAccount)
        #expect(result == true)
    }

    @Test func supportsTrashFalse() async throws {
        await RetrievedCapabilitiesActor.shared.reset()
        let jsonNoUndelete = """
        {
            "ocs": {
                "meta": {
                    "status": "ok",
                    "statuscode": 100,
                    "message": "OK"
                },
                "data": {
                    "capabilities": {
                        "files": {
                            "undelete": false
                        }
                    }
                }
            }
        }
        """
        let (capsNoTrash, dataNoTrash) = capabilitiesFromMockJSON(jsonString: jsonNoUndelete)
        #expect(capsNoTrash.files?.undelete == false)

        var remoteInterface = TestableRemoteInterface()
        remoteInterface.fetchCapabilitiesHandler = { acc, _, _ in
            await RetrievedCapabilitiesActor.shared.setCapabilities(
                forAccount: acc.ncKitAccount, capabilities: capsNoTrash, retrievedAt: Date()
            )
            return (acc.ncKitAccount, capsNoTrash, dataNoTrash, .success)
        }
        await RetrievedCapabilitiesActor.shared.setCapabilities( // Stale entry
            forAccount: testAccount.ncKitAccount,
            capabilities: capsNoTrash,
            retrievedAt: Date(timeIntervalSinceNow: -(CapabilitiesFetchInterval + 100))
        )

        let result = await remoteInterface.supportsTrash(account: testAccount)
        #expect(result == false)
    }

    @Test func supportsTrashNilCapabilities() async throws {
        await RetrievedCapabilitiesActor.shared.reset()
        var remoteInterface = TestableRemoteInterface()
        remoteInterface.fetchCapabilitiesHandler = { acc, _, _ in
            (acc.ncKitAccount, nil, nil, .invalidResponseError)
        }
        await RetrievedCapabilitiesActor.shared.setCapabilities(
            forAccount: testAccount.ncKitAccount,
            capabilities: capabilitiesFromMockJSON().0,
            retrievedAt: Date(timeIntervalSinceNow: -(CapabilitiesFetchInterval + 100))
        )

        let result = await remoteInterface.supportsTrash(account: testAccount)
        #expect(!result)
    }

    @Test func supportsTrashNilFilesSection() async throws {
        await RetrievedCapabilitiesActor.shared.reset()
        let jsonNoFilesSection = """
        {
            "ocs": {
                "meta": {
                    "status": "ok",
                    "statuscode": 100,
                    "message": "OK"
                },
                "data": {
                    "capabilities": {
                        "core": {
                            "pollinterval": 60
                        }
                    }
                }
            }
        }
        """
        // This JSON will result in `Capabilities.files` being nil
        let (capsNoFiles, dataNoFiles) = capabilitiesFromMockJSON(jsonString: jsonNoFilesSection)
        #expect(capsNoFiles.files?.undelete != true) // Check our parsing logic

        var remoteInterface = TestableRemoteInterface()
        remoteInterface.fetchCapabilitiesHandler = { acc, _, _ in
            (acc.ncKitAccount, capsNoFiles, dataNoFiles, .success)
        }
        await RetrievedCapabilitiesActor.shared.setCapabilities( // Stale entry
            forAccount: testAccount.ncKitAccount,
            capabilities: capsNoFiles,
            retrievedAt: Date(timeIntervalSinceNow: -(CapabilitiesFetchInterval + 100))
        )

        let result = await remoteInterface.supportsTrash(account: testAccount)
        #expect(!result)
    }

    @Test func supportsTrashHandlesErrorFromCurrentCapabilities() async throws {
        await RetrievedCapabilitiesActor.shared.reset()
        var remoteInterface = TestableRemoteInterface()
        remoteInterface.fetchCapabilitiesHandler = { acc, _, _ in
            (acc.ncKitAccount, nil, nil, .invalidResponseError)
        }
        // Ensure fetch is triggered
        // (e.g., actor has no data or stale data for testAccount.ncKitAccount)

        let result = await remoteInterface.supportsTrash(account: testAccount)
        #expect(!result, "supportsTrash should return false if currentCapabilities errors.")
    }
}
