//  SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

extension Array<SendableItemMetadata> {
    ///
    /// Concurrently compact chunks of an array of ``SendableItemMetadata`` to an array of ``Item``.
    ///
    func toFileProviderItems(account: Account, remoteInterface: RemoteInterface, dbManager: FilesDatabaseManager, log: any FileProviderLogging) async throws -> [Item] {
        let logger = FileProviderLogger(category: "toFileProviderItems", log: log)
        let remoteSupportsTrash = await remoteInterface.supportsTrash(account: account)

        let result: [Item] = try await self.concurrentChunkedCompactMap { (itemMetadata: SendableItemMetadata) -> Item? in
            guard !itemMetadata.e2eEncrypted else {
                logger.info("Skipping encrypted metadata in enumeration.", [.ocId: itemMetadata.ocId, .name: itemMetadata.fileName])
                return nil
            }

            guard !isLockFileName(itemMetadata.fileName) else {
                logger.info("Skipping remote lock file item metadata in enumeration.", [.ocId: itemMetadata.ocId, .name: itemMetadata.fileName])
                return nil
            }

            guard let parentItemIdentifier = dbManager.parentItemIdentifierFromMetadata(
                itemMetadata
            ) else {
                logger.error("Could not get valid parentItemIdentifier for item by ocId.", [.ocId: itemMetadata.ocId, .name: itemMetadata.fileName])
                let targetUrl = itemMetadata.serverUrl
                throw FilesDatabaseManager.parentMetadataNotFoundError(itemUrl: targetUrl)
            }

            let item = Item(
                metadata: itemMetadata,
                parentItemIdentifier: parentItemIdentifier,
                account: account,
                remoteInterface: remoteInterface,
                dbManager: dbManager,
                remoteSupportsTrash: remoteSupportsTrash,
                log: log
            )

            logger.debug("Will enumerate item.", [.ocId: itemMetadata.ocId, .name: itemMetadata.fileName])

            return item
        }

        return result
    }
}
