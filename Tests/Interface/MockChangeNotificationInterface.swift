//  SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import NextcloudFileProviderKit

final public class MockChangeNotificationInterface: ChangeNotificationInterface {
    let changeHandler: (@Sendable () -> Void)?

    public init(changeHandler: (@Sendable () -> Void)? = nil) {
        self.changeHandler = changeHandler
    }

    public func notifyChange() {
        changeHandler?()
    }
}
