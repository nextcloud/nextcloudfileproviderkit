//  SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: GPL-2.0-or-later

import Alamofire
import FileProvider
import Foundation
import NextcloudCapabilitiesKit
import NextcloudKit

public enum EnumerateDepth: String {
    case target = "0"
    case targetAndDirectChildren = "1"
    case targetAndAllChildren = "infinity"
}

public enum AuthenticationAttemptResultState: Int {
    case authenticationError, connectionError, success
}

///
/// Abstraction of the Nextcloud server APIs to call from the file provider extension.
///
/// Usually, the shared `NextcloudKit` instance is conforming to this and provided as an argument.
/// NextcloudKit is not mockable as of writing, hence this protocol was defined to enable testing.
///
public protocol RemoteInterface {
    func setDelegate(_ delegate: NextcloudKitDelegate)

    func createFolder(
        remotePath: String,
        account: Account,
        options: NKRequestOptions,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void
    ) async -> (account: String, ocId: String?, date: NSDate?, error: NKError)

    func upload(
        remotePath: String,
        localPath: String,
        creationDate: Date?,
        modificationDate: Date?,
        account: Account,
        options: NKRequestOptions,
        requestHandler: @escaping (_ request: UploadRequest) -> Void,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void,
        progressHandler: @escaping (_ progress: Progress) -> Void
    ) async -> (
        account: String,
        ocId: String?,
        etag: String?,
        date: NSDate?,
        size: Int64,
        response: HTTPURLResponse?,
        remoteError: NKError
    )

    func chunkedUpload(
        localPath: String,
        remotePath: String,
        remoteChunkStoreFolderName: String,
        chunkSize: Int,
        remainingChunks: [RemoteFileChunk],
        creationDate: Date?,
        modificationDate: Date?,
        account: Account,
        options: NKRequestOptions,
        currentNumChunksUpdateHandler: @escaping (_ num: Int) -> Void,
        chunkCounter: @escaping (_ counter: Int) -> Void,
        log: any FileProviderLogging,
        chunkUploadStartHandler: @escaping (_ filesChunk: [RemoteFileChunk]) -> Void,
        requestHandler: @escaping (_ request: UploadRequest) -> Void,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void,
        progressHandler: @escaping (Progress) -> Void,
        chunkUploadCompleteHandler: @escaping (_ fileChunk: RemoteFileChunk) -> Void
    ) async -> (
        account: String,
        fileChunks: [RemoteFileChunk]?,
        file: NKFile?,
        nkError: NKError
    )

    func move(
        remotePathSource: String,
        remotePathDestination: String,
        overwrite: Bool,
        account: Account,
        options: NKRequestOptions,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void
    ) async -> (account: String, data: Data?, error: NKError)

    func download(
        remotePath: String,
        localPath: String,
        account: Account,
        options: NKRequestOptions,
        requestHandler: @escaping (_ request: DownloadRequest) -> Void,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void,
        progressHandler: @escaping (_ progress: Progress) -> Void
    ) async -> (
        account: String,
        etag: String?,
        date: Date?,
        length: Int64,
        headers: [AnyHashable: any Sendable]?,
        afError: AFError?,
        nkError: NKError
    )

    func enumerate(
        remotePath: String,
        depth: EnumerateDepth,
        showHiddenFiles: Bool,
        includeHiddenFiles: [String],
        requestBody: Data?,
        account: Account,
        options: NKRequestOptions,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void
    ) async -> (account: String, files: [NKFile], data: AFDataResponse<Data>?, error: NKError)

    func delete(
        remotePath: String,
        account: Account,
        options: NKRequestOptions,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void
    ) async -> (account: String, response: HTTPURLResponse?, error: NKError)

    func lockUnlockFile(serverUrlFileName: String, type: NKLockType?, shouldLock: Bool, account: Account, options: NKRequestOptions, taskHandler: @escaping (_ task: URLSessionTask) -> Void) async throws -> NKLock?

    func trashedItems(
        account: Account,
        options: NKRequestOptions,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void
    ) async -> (account: String, trashedItems: [NKTrash], data: Data?, error: NKError)

    func restoreFromTrash(
        filename: String,
        account: Account,
        options: NKRequestOptions,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void
    ) async -> (account: String, data: Data?, error: NKError)

    func downloadThumbnail(
        url: URL,
        account: Account,
        options: NKRequestOptions,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void
    ) async -> (account: String, data: Data?, error: NKError)

    func fetchCapabilities(
        account: Account,
        options: NKRequestOptions,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void
    ) async -> (account: String, capabilities: Capabilities?, data: Data?, error: NKError)

    func fetchUserProfile(
        account: Account,
        options: NKRequestOptions,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void
    ) async -> (account: String, userProfile: NKUserProfile?, data: Data?, error: NKError)

    func tryAuthenticationAttempt(
        account: Account,
        options: NKRequestOptions,
        taskHandler: @escaping (_ task: URLSessionTask) -> Void
    ) async -> AuthenticationAttemptResultState
}

public extension RemoteInterface {
    func currentCapabilities(
        account: Account,
        options: NKRequestOptions = .init(),
        taskHandler: @escaping (_ task: URLSessionTask) -> Void = { _ in }
    ) async -> (account: String, capabilities: Capabilities?, data: Data?, error: NKError) {
        let ncKitAccount = account.ncKitAccount
        await RetrievedCapabilitiesActor.shared.awaitFetchCompletion(forAccount: ncKitAccount)
        guard let lastRetrieval = await RetrievedCapabilitiesActor.shared.data[ncKitAccount],
              lastRetrieval.retrievedAt.timeIntervalSince(Date()) > -CapabilitiesFetchInterval
        else {
            return await fetchCapabilities(
                account: account, options: options, taskHandler: taskHandler
            )
        }
        return (account.ncKitAccount, lastRetrieval.capabilities, nil, .success)
    }

    func supportsTrash(
        account: Account,
        options _: NKRequestOptions = .init(),
        taskHandler _: @escaping (_ task: URLSessionTask) -> Void = { _ in }
    ) async -> Bool {
        var remoteSupportsTrash = false

        let (_, capabilities, _, _) = await currentCapabilities(
            account: account, options: .init(), taskHandler: { _ in }
        )

        if let filesCapabilities = capabilities?.files {
            remoteSupportsTrash = filesCapabilities.undelete
        }

        return remoteSupportsTrash
    }
}
