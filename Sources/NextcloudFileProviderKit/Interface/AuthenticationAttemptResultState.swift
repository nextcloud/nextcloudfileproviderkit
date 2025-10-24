//  SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
//  SPDX-License-Identifier: LGPL-3.0-or-later

public enum AuthenticationAttemptResultState: Int {
    case authenticationError
    case connectionError
    case success
}
