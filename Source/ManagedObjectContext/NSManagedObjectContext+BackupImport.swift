//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import Foundation

extension NSManagedObjectContext {
    
    /// Prepare a backed up database for being imported, deleting self client, push token etc.
    func prepareToImportBackup() {
        StorageStack.shared.isImportedFromBackup = false
        require(self.zm_isSyncContext, "Needs to be run on Sync Context to avoid race conditions")
        setPersistentStoreMetadata(nil as Data?, key: ZMPersistedClientIdKey)
        setPersistentStoreMetadata(nil as Data?, key: PersistentMetadataKey.pushToken.rawValue)
        setPersistentStoreMetadata(nil as Data?, key: PersistentMetadataKey.pushKitToken.rawValue)
        setPersistentStoreMetadata(nil as Data?, key: PersistentMetadataKey.lastUpdateEventID.rawValue)
        saveOrRollback()
    }
    
}
