//  SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import RealmSwift

///
/// Realm data model for migrating the shared legacy schema.
///
class LegacyRealmItemMetadata: Object {
    @Persisted(primaryKey: true) var ocId: String
    @Persisted var account = ""
    @Persisted var checksums = ""
    @Persisted var chunkUploadId: String?
    @Persisted var classFile = ""
    @Persisted var commentsUnread: Bool = false
    @Persisted var contentType = ""
    @Persisted var creationDate = Date()
    @Persisted var dataFingerprint = ""
    @Persisted var date = Date()
    @Persisted var directory: Bool = false
    @Persisted var downloadURL = ""
    @Persisted var e2eEncrypted: Bool = false
    @Persisted var etag = ""
    @Persisted var favorite: Bool = false
    @Persisted var fileId = ""
    @Persisted var fileName = "" // What the file's real file name is
    @Persisted var fileNameView = "" // What the user sees (usually same as fileName)
    @Persisted var hasPreview: Bool = false
    @Persisted var hidden = false
    @Persisted var iconName = ""
    @Persisted var iconUrl = ""
    @Persisted var livePhotoFile: String?
    @Persisted var mountType = ""
    @Persisted var name = "" // for unifiedSearch is the provider.id
    @Persisted var note = ""
    @Persisted var ownerId = ""
    @Persisted var ownerDisplayName = ""
    @Persisted var lock: Bool = false
    @Persisted var lockOwner: String?
    @Persisted var lockOwnerEditor: String?
    @Persisted var lockOwnerType: Int?
    @Persisted var lockOwnerDisplayName: String?
    @Persisted var lockTime: Date? // Time the file was locked
    @Persisted var lockTimeOut: Date? // Time the file's lock will expire
    @Persisted var path = ""
    @Persisted var permissions = ""
    @Persisted var quotaUsedBytes: Int64 = 0
    @Persisted var quotaAvailableBytes: Int64 = 0
    @Persisted var resourceType = ""
    @Persisted var richWorkspace: String?
    @Persisted var serverUrl = "" // For parent folder! Build remote url by adding fileName
    @Persisted var session: String?
    @Persisted var sessionError: String?
    @Persisted var sessionTaskIdentifier: Int?
    @Persisted var storedShareType = List<Int>()
    var shareType: [Int] {
        get { storedShareType.map { $0 } }
        set {
            storedShareType = List<Int>()
            storedShareType.append(objectsIn: newValue)
        }
    }

    @Persisted var sharePermissionsCollaborationServices: Int = 0
    // TODO: Find a way to compare these two below in remote state check
    @Persisted var storedSharePermissionsCloudMesh = List<String>()
    var sharePermissionsCloudMesh: [String] {
        get { storedSharePermissionsCloudMesh.map { $0 } }
        set {
            storedSharePermissionsCloudMesh = List<String>()
            storedSharePermissionsCloudMesh.append(objectsIn: newValue)
        }
    }

    @Persisted var size: Int64 = 0
    @Persisted var status: Int = 0
    @Persisted var storedTags = List<String>()
    var tags: [String] {
        get { storedTags.map { $0 } }
        set {
            storedTags = List<String>()
            storedTags.append(objectsIn: newValue)
        }
    }

    @Persisted var downloaded = false
    @Persisted var uploaded = false
    @Persisted var trashbinFileName = ""
    @Persisted var trashbinOriginalLocation = ""
    @Persisted var trashbinDeletionTime = Date()
    @Persisted var uploadDate = Date()
    @Persisted var urlBase = ""
    @Persisted var user = "" // The user who owns the file (Nextcloud username)
    @Persisted var userId = "" // The user who owns the file (backend user id)

    convenience init(value: any ItemMetadata) {
        self.init()
        ocId = value.ocId
        account = value.account
        checksums = value.checksums
        chunkUploadId = value.chunkUploadId
        classFile = value.classFile
        commentsUnread = value.commentsUnread
        contentType = value.contentType
        creationDate = value.creationDate
        dataFingerprint = value.dataFingerprint
        date = value.date
        directory = value.directory
        downloadURL = value.downloadURL
        e2eEncrypted = value.e2eEncrypted
        etag = value.etag
        favorite = value.favorite
        fileId = value.fileId
        fileName = value.fileName
        fileNameView = value.fileNameView
        hasPreview = value.hasPreview
        hidden = value.hidden
        iconName = value.iconName
        iconUrl = value.iconUrl
        livePhotoFile = value.livePhotoFile
        mountType = value.mountType
        name = value.name
        note = value.note
        ownerId = value.ownerId
        ownerDisplayName = value.ownerDisplayName
        lock = value.lock
        lockOwner = value.lockOwner
        lockOwnerEditor = value.lockOwnerEditor
        lockOwnerType = value.lockOwnerType
        lockOwnerDisplayName = value.lockOwnerDisplayName
        lockTime = value.lockTime
        lockTimeOut = value.lockTimeOut
        path = value.path
        permissions = value.permissions
        quotaUsedBytes = value.quotaUsedBytes
        quotaAvailableBytes = value.quotaAvailableBytes
        resourceType = value.resourceType
        richWorkspace = value.richWorkspace
        serverUrl = value.serverUrl
        session = value.session
        sessionError = value.sessionError
        sessionTaskIdentifier = value.sessionTaskIdentifier
        sharePermissionsCollaborationServices = value.sharePermissionsCollaborationServices
        sharePermissionsCloudMesh = value.sharePermissionsCloudMesh
        size = value.size
        status = value.status
        shareType = value.shareType
        tags = value.tags
        downloaded = value.downloaded
        uploaded = value.uploaded
        trashbinFileName = value.trashbinFileName
        trashbinOriginalLocation = value.trashbinOriginalLocation
        trashbinDeletionTime = value.trashbinDeletionTime
        uploadDate = value.uploadDate
        urlBase = value.urlBase
        user = value.user
        userId = value.userId
    }

    func toRealmItemMetadata() -> RealmItemMetadata {
        let metadata = RealmItemMetadata()

        metadata.ocId = self.ocId
        metadata.account = self.account
        metadata.checksums = self.checksums
        metadata.chunkUploadId = self.chunkUploadId
        metadata.classFile = self.classFile
        metadata.commentsUnread = self.commentsUnread
        metadata.contentType = self.contentType
        metadata.creationDate = self.creationDate
        metadata.dataFingerprint = self.dataFingerprint
        metadata.date = self.date
        metadata.syncTime = Date()
        metadata.deleted = false
        metadata.directory = self.directory
        metadata.downloadURL = self.downloadURL
        metadata.e2eEncrypted = self.e2eEncrypted
        metadata.etag = self.etag
        metadata.favorite = self.favorite
        metadata.fileId = self.fileId
        metadata.fileName = self.fileName
        metadata.fileNameView = self.fileNameView
        metadata.hasPreview = self.hasPreview
        metadata.hidden = self.hidden
        metadata.iconName = self.iconName
        metadata.iconUrl = self.iconUrl
        metadata.isLockFileOfLocalOrigin = false
        metadata.livePhotoFile = self.livePhotoFile
        metadata.mountType = self.mountType
        metadata.name = self.name
        metadata.note = self.note
        metadata.ownerId = self.ownerId
        metadata.ownerDisplayName = self.ownerDisplayName
        metadata.lock = self.lock
        metadata.lockOwner = self.lockOwner
        metadata.lockOwnerEditor = self.lockOwnerEditor
        metadata.lockOwnerType = self.lockOwnerType
        metadata.lockOwnerDisplayName = self.lockOwnerDisplayName
        metadata.lockTime = self.lockTime
        metadata.lockTimeOut = self.lockTimeOut
        metadata.lockToken = nil
        metadata.path = self.path
        metadata.permissions = self.permissions
        metadata.quotaUsedBytes = self.quotaUsedBytes
        metadata.quotaAvailableBytes = self.quotaAvailableBytes
        metadata.resourceType = self.resourceType
        metadata.richWorkspace = self.richWorkspace
        metadata.serverUrl = self.serverUrl
        metadata.session = self.session
        metadata.sessionError = self.sessionError
        metadata.sessionTaskIdentifier = self.sessionTaskIdentifier
        metadata.sharePermissionsCollaborationServices = self.sharePermissionsCollaborationServices
        metadata.sharePermissionsCloudMesh = self.sharePermissionsCloudMesh
        metadata.size = self.size
        metadata.status = self.status
        metadata.shareType = self.shareType
        metadata.tags = self.tags
        metadata.downloaded = self.downloaded
        metadata.uploaded = self.uploaded
        metadata.keepDownloaded = false
        metadata.visitedDirectory = false
        metadata.trashbinFileName = self.trashbinFileName
        metadata.trashbinOriginalLocation = self.trashbinOriginalLocation
        metadata.trashbinDeletionTime = self.trashbinDeletionTime
        metadata.uploadDate = self.uploadDate
        metadata.urlBase = self.urlBase
        metadata.user = self.user
        metadata.userId = self.userId

        return metadata
    }
}
