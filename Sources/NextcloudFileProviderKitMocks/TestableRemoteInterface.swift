//  SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: GPL-2.0-or-later

import Alamofire
import Foundation
import NextcloudCapabilitiesKit
@testable import NextcloudFileProviderKit
import NextcloudKit

public struct TestableRemoteInterface: RemoteInterface {
    public init() {}

    public func setDelegate(_: any NextcloudKitDelegate) {}

    public func createFolder(
        remotePath _: String,
        account _: Account,
        options _: NKRequestOptions,
        taskHandler _: @escaping (URLSessionTask) -> Void
    ) async -> (account: String, ocId: String?, date: NSDate?, error: NKError) {
        ("", nil, nil, .invalidResponseError)
    }

    public func upload(
        remotePath _: String,
        localPath _: String,
        creationDate _: Date?,
        modificationDate _: Date?,
        account _: Account,
        options _: NKRequestOptions,
        requestHandler _: @escaping (UploadRequest) -> Void,
        taskHandler _: @escaping (URLSessionTask) -> Void,
        progressHandler _: @escaping (Progress) -> Void
    ) async -> (
        account: String,
        ocId: String?,
        etag: String?,
        date: NSDate?,
        size: Int64,
        response: HTTPURLResponse?,
        remoteError: NKError
    ) { ("", nil, nil, nil, 0, nil, .invalidResponseError) }

    public func chunkedUpload(
        localPath _: String,
        remotePath _: String,
        remoteChunkStoreFolderName _: String,
        chunkSize _: Int,
        remainingChunks _: [RemoteFileChunk],
        creationDate _: Date?,
        modificationDate _: Date?,
        account _: Account,
        options _: NKRequestOptions,
        currentNumChunksUpdateHandler _: @escaping (Int) -> Void,
        chunkCounter _: @escaping (Int) -> Void,
        log _: any FileProviderLogging,
        chunkUploadStartHandler _: @escaping ([RemoteFileChunk]) -> Void,
        requestHandler _: @escaping (UploadRequest) -> Void,
        taskHandler _: @escaping (URLSessionTask) -> Void,
        progressHandler _: @escaping (Progress) -> Void,
        chunkUploadCompleteHandler _: @escaping (RemoteFileChunk) -> Void
    ) async -> (
        account: String,
        fileChunks: [RemoteFileChunk]?,
        file: NKFile?,
        nkError: NKError
    ) {
        ("", nil, nil, .invalidResponseError)
    }

    public func move(
        remotePathSource _: String,
        remotePathDestination _: String,
        overwrite _: Bool,
        account _: Account,
        options _: NKRequestOptions,
        taskHandler _: @escaping (URLSessionTask) -> Void
    ) async -> (account: String, data: Data?, error: NKError) { ("", nil, .invalidResponseError) }

    public func download(
        remotePath _: String,
        localPath _: String,
        account _: Account,
        options _: NKRequestOptions,
        requestHandler _: @escaping (DownloadRequest) -> Void,
        taskHandler _: @escaping (URLSessionTask) -> Void,
        progressHandler _: @escaping (Progress) -> Void
    ) async -> (
        account: String,
        etag: String?,
        date: NSDate?,
        length: Int64,
        headers: [AnyHashable: Any]?,
        afError: AFError?,
        nkError: NKError
    ) {
        ("", nil, nil, 0, nil, nil, .invalidResponseError)
    }

    public func enumerate(
        remotePath _: String,
        depth _: EnumerateDepth,
        showHiddenFiles _: Bool,
        includeHiddenFiles _: [String],
        requestBody _: Data?,
        account _: Account,
        options _: NKRequestOptions,
        taskHandler _: @escaping (URLSessionTask) -> Void
    ) async -> (account: String, files: [NKFile], data: AFDataResponse<Data>?, error: NKError) {
        ("", [], nil, .invalidResponseError)
    }

    public func delete(
        remotePath _: String,
        account _: Account,
        options _: NKRequestOptions,
        taskHandler _: @escaping (URLSessionTask) -> Void
    ) async -> (account: String, response: HTTPURLResponse?, error: NKError) {
        ("", nil, .invalidResponseError)
    }

    public func lockUnlockFile(serverUrlFileName _: String, type _: NKLockType?, shouldLock _: Bool, account _: Account, options _: NKRequestOptions, taskHandler _: @escaping (URLSessionTask) -> Void) async throws -> NKLock? {
        throw NKError.invalidResponseError
    }

    public func trashedItems(
        account _: Account, options _: NKRequestOptions, taskHandler _: @escaping (URLSessionTask) -> Void
    ) async -> (account: String, trashedItems: [NKTrash], data: Data?, error: NKError) {
        ("", [], nil, .invalidResponseError)
    }

    public func restoreFromTrash(
        filename _: String,
        account _: Account,
        options _: NKRequestOptions,
        taskHandler _: @escaping (URLSessionTask) -> Void
    ) async -> (account: String, data: Data?, error: NKError) { ("", nil, .invalidResponseError) }

    public func downloadThumbnail(
        url _: URL,
        account _: Account,
        options _: NKRequestOptions,
        taskHandler _: @escaping (URLSessionTask) -> Void
    ) async -> (account: String, data: Data?, error: NKError) { ("", nil, .invalidResponseError) }

    public func fetchUserProfile(
        account _: Account, options _: NKRequestOptions, taskHandler _: @escaping (URLSessionTask) -> Void
    ) async -> (account: String, userProfile: NKUserProfile?, data: Data?, error: NKError) {
        ("", nil, nil, .invalidResponseError)
    }

    public func tryAuthenticationAttempt(
        account _: Account, options _: NKRequestOptions, taskHandler _: @escaping (URLSessionTask) -> Void
    ) async -> AuthenticationAttemptResultState { .connectionError }

    public typealias FetchResult = (account: String, capabilities: Capabilities?, data: Data?, error: NKError)

    public var fetchCapabilitiesHandler:
        ((Account, NKRequestOptions, @escaping (URLSessionTask) -> Void) async -> FetchResult)?

    public func fetchCapabilities(
        account: Account,
        options: NKRequestOptions = .init(),
        taskHandler: @escaping (_ task: URLSessionTask) -> Void = { _ in }
    ) async -> FetchResult {
        let ncKitAccount = account.ncKitAccount
        await RetrievedCapabilitiesActor.shared.setOngoingFetch(
            forAccount: ncKitAccount, ongoing: true
        )
        var response: FetchResult
        if let handler = fetchCapabilitiesHandler {
            response = await handler(account, options, taskHandler)
            if let caps = response.capabilities {
                await RetrievedCapabilitiesActor.shared.setCapabilities(
                    forAccount: ncKitAccount, capabilities: caps, retrievedAt: Date()
                )
            }
        } else {
            print("Error: fetchCapabilitiesHandler not set in TestableRemoteInterface")
            response = (account.ncKitAccount, nil, nil, .invalidResponseError)
        }
        await RetrievedCapabilitiesActor.shared.setOngoingFetch(
            forAccount: account.ncKitAccount, ongoing: false
        )
        return response
    }
}
