//  SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: GPL-2.0-or-later

import FileProvider
import NextcloudKit

extension Item {
    // Note: When handling trashing, the server handles filename conflicts for us
    static func trash(
        _ modifiedItem: Item,
        account: Account,
        dbManager: FilesDatabaseManager,
        domain: NSFileProviderDomain?,
        log: any FileProviderLogging
    ) async -> (Item, Error?) {
        let logger = FileProviderLogger(category: "Item", log: log)

        let deleteError = await modifiedItem.delete(trashing: true, domain: domain, dbManager: dbManager)

        guard deleteError == nil else {
            logger.error("Error attempting to move item into trash.", [.name: modifiedItem.filename, .error: deleteError])
            return (modifiedItem, deleteError)
        }

        let ocId = modifiedItem.itemIdentifier.rawValue
        guard let dirtyMetadata = dbManager.itemMetadata(ocId: ocId) else {
            logger.error(
                """
                Could not correctly process trashing results, dirty metadata not found.
                \(modifiedItem.filename) \(ocId)
                """
            )
            return (modifiedItem, NSFileProviderError(.cannotSynchronize))
        }
        let dirtyChildren = dbManager.childItems(directoryMetadata: dirtyMetadata)
        let dirtyItem = await Item(
            metadata: dirtyMetadata,
            parentItemIdentifier: .trashContainer,
            account: account,
            remoteInterface: modifiedItem.remoteInterface,
            dbManager: dbManager,
            remoteSupportsTrash: modifiedItem.remoteInterface.supportsTrash(account: account),
            log: log
        )

        // The server may have renamed the trashed file so we need to scan the entire trash
        let (_, files, _, error) = await modifiedItem.remoteInterface.trashedItems(
            account: account,
            options: .init(),
            taskHandler: { task in
                if let domain {
                    NSFileProviderManager(for: domain)?.register(
                        task,
                        forItemWithIdentifier: modifiedItem.itemIdentifier,
                        completionHandler: { _ in }
                    )
                }
            }
        )

        guard error == .success else {
            logger.error(
                """
                Received bad error from post-trashing remote scan:
                    \(error.errorDescription) \(files)
                """
            )
            return (dirtyItem, error.fileProviderError)
        }

        guard let targetItemNKTrash = files.first(
            // It seems the server likes to return a fileId as the ocId for trash files, so let's
            // check for the fileId too
            where: { $0.ocId == modifiedItem.metadata.ocId ||
                $0.fileId == modifiedItem.metadata.fileId
            }
        )
        else {
            logger.error(
                """
                Did not find trashed item:
                    \(modifiedItem.filename)
                    \(modifiedItem.itemIdentifier.rawValue)
                in trash. Asking for a rescan. Found trashed files were:
                    \(files.map {
                        ($0.ocId, $0.fileId, $0.fileName, $0.trashbinFileName)
                    })
                """
            )
            if #available(macOS 11.3, *) {
                return (dirtyItem, NSFileProviderError(.unsyncedEdits))
            } else {
                return (dirtyItem, NSFileProviderError(.syncAnchorExpired))
            }
        }

        var postDeleteMetadata = targetItemNKTrash.toItemMetadata(account: account)
        postDeleteMetadata.ocId = modifiedItem.itemIdentifier.rawValue
        dbManager.addItemMetadata(postDeleteMetadata)

        let postDeleteItem = await Item(
            metadata: postDeleteMetadata,
            parentItemIdentifier: .trashContainer,
            account: account,
            remoteInterface: modifiedItem.remoteInterface,
            dbManager: dbManager,
            remoteSupportsTrash: modifiedItem.remoteInterface.supportsTrash(account: account),
            log: log
        )

        // Now we can directly update info on the child items
        var (_, childFiles, _, childError) = await modifiedItem.remoteInterface.enumerate(
            remotePath: postDeleteMetadata.serverUrl + "/" + postDeleteMetadata.fileName,
            depth: EnumerateDepth.targetAndAllChildren, // Just do it in one go
            showHiddenFiles: true,
            includeHiddenFiles: [],
            requestBody: nil,
            account: account,
            options: .init(),
            taskHandler: { task in
                if let domain {
                    NSFileProviderManager(for: domain)?.register(
                        task,
                        forItemWithIdentifier: modifiedItem.itemIdentifier,
                        completionHandler: { _ in }
                    )
                }
            }
        )

        guard error == .success else {
            logger.error(
                """
                Received bad error or files from post-trashing child items remote scan:
                \(error.errorDescription) \(files)
                """
            )
            return (postDeleteItem, childError.fileProviderError)
        }

        // Update state of child files
        childFiles.removeFirst() // This is the target path, already scanned
        for file in childFiles {
            var metadata = file.toItemMetadata()
            guard let original = dirtyChildren
                .filter({ $0.ocId == metadata.ocId || $0.fileId == metadata.fileId })
                .first
            else {
                logger.info(
                    """
                    Skipping post-trash child item metadata: \(metadata.fileName)
                        Could not find matching existing item in database, cannot do ocId correction
                    """
                )
                continue
            }
            metadata.ocId = original.ocId // Give original id back
            dbManager.addItemMetadata(metadata)
            logger.info("Note: that was a post-trash child item metadata")
        }

        return (postDeleteItem, nil)
    }

    // Note: When restoring from the trash, the server handles filename conflicts for us
    static func restoreFromTrash(
        _ modifiedItem: Item,
        account: Account,
        remoteInterface: RemoteInterface,
        dbManager: FilesDatabaseManager,
        domain _: NSFileProviderDomain?,
        log: any FileProviderLogging
    ) async -> (Item, Error?) {
        let logger = FileProviderLogger(category: "Item", log: log)

        func finaliseRestore(target: NKFile) async -> (Item, Error?) {
            let restoredItemMetadata = target.toItemMetadata()
            guard let parentItemIdentifier = await dbManager.parentItemIdentifierWithRemoteFallback(
                fromMetadata: restoredItemMetadata,
                remoteInterface: remoteInterface,
                account: account
            ) else {
                logger.error("Could not find parent item identifier for \(originalLocation)")
                return (modifiedItem, NSFileProviderError(.cannotSynchronize))
            }

            if restoredItemMetadata.directory {
                _ = dbManager.renameDirectoryAndPropagateToChildren(
                    ocId: restoredItemMetadata.ocId,
                    newServerUrl: restoredItemMetadata.serverUrl,
                    newFileName: restoredItemMetadata.fileName
                )
            }
            dbManager.addItemMetadata(restoredItemMetadata)

            return await (Item(
                metadata: restoredItemMetadata,
                parentItemIdentifier: parentItemIdentifier,
                account: account,
                remoteInterface: modifiedItem.remoteInterface,
                dbManager: dbManager,
                remoteSupportsTrash: modifiedItem.remoteInterface.supportsTrash(account: account),
                log: log
            ), nil)
        }

        let (_, _, restoreError) = await modifiedItem.remoteInterface.restoreFromTrash(
            filename: modifiedItem.metadata.fileName,
            account: account,
            options: .init(),
            taskHandler: { _ in }
        )
        guard restoreError == .success else {
            logger.error(
                """
                Could not restore item \(modifiedItem.filename) from trash
                    Received error: \(restoreError.errorDescription)
                """
            )
            return (modifiedItem, restoreError.fileProviderError)
        }
        guard modifiedItem.metadata.trashbinOriginalLocation != "" else {
            logger.error(
                """
                Could not scan restored item \(modifiedItem.filename).
                The trashed file's original location is invalid.
                """
            )
            if #available(macOS 11.3, *) {
                return (modifiedItem, NSFileProviderError(.unsyncedEdits))
            }
            return (modifiedItem, NSFileProviderError(.cannotSynchronize))
        }
        let originalLocation =
            account.davFilesUrl + "/" + modifiedItem.metadata.trashbinOriginalLocation

        let (_, files, _, enumerateError) = await modifiedItem.remoteInterface.enumerate(
            remotePath: originalLocation,
            depth: .target,
            showHiddenFiles: true,
            includeHiddenFiles: [],
            requestBody: nil,
            account: account,
            options: .init(),
            taskHandler: { _ in }
        )
        guard enumerateError == .success, !files.isEmpty, let target = files.first else {
            logger.error(
                """
                Could not scan restored state of file \(originalLocation)
                Received error: \(enumerateError.errorDescription)
                Files: \(files.count)
                """
            )
            if #available(macOS 11.3, *) {
                return (modifiedItem, NSFileProviderError(.unsyncedEdits))
            }
            return (modifiedItem, enumerateError.fileProviderError)
        }

        guard target.ocId == modifiedItem.itemIdentifier.rawValue else {
            logger.info(
                """
                Restored item \(originalLocation)
                does not match \(modifiedItem.filename)
                (it is likely that when restoring from the trash, there was another identical item).
                """
            )

            guard let finalSlashIndex = originalLocation.lastIndex(of: "/") else {
                return (modifiedItem, NSFileProviderError(.cannotSynchronize))
            }
            var parentDirectoryRemotePath = originalLocation
            parentDirectoryRemotePath.removeSubrange(finalSlashIndex ..< originalLocation.endIndex)

            logger.info(
                """
                Scanning parent folder at \(parentDirectoryRemotePath) for current
                state of item restored from trash.
                """
            )

            let (_, files, _, folderScanError) = await modifiedItem.remoteInterface.enumerate(
                remotePath: parentDirectoryRemotePath,
                depth: .targetAndDirectChildren,
                showHiddenFiles: true,
                includeHiddenFiles: [],
                requestBody: nil,
                account: account,
                options: .init(),
                taskHandler: { _ in }
            )

            guard folderScanError == .success else {
                logger.error(
                    """
                    Scanning parent folder at \(parentDirectoryRemotePath)
                    returned error: \(folderScanError.errorDescription)
                    """
                )
                return (modifiedItem, NSFileProviderError(.cannotSynchronize))
            }

            guard let actualTarget = files.first(
                where: { $0.ocId == modifiedItem.itemIdentifier.rawValue }
            ) else {
                logger.error(
                    """
                    Scanning parent folder at \(parentDirectoryRemotePath)
                    finished successfully but the target item restored from trash not found.
                    """
                )
                return (modifiedItem, NSFileProviderError(.cannotSynchronize))
            }

            return await finaliseRestore(target: actualTarget)
        }

        return await finaliseRestore(target: target)
    }
}
