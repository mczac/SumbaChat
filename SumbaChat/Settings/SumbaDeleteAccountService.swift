//
// SPDX-FileCopyrightText: 2026 Peter Zakharov
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum SumbaDeleteAccountResult {
    /// Server accepted account retire (`202 Accepted`).
    /// - Parameters:
    ///   - anonymizedDisplayName: Final label from server, e.g. `Former Team Member (1721491200)`.
    ///   - alreadyRetired: Idempotent re-call; account was already retired.
    case deleted(anonymizedDisplayName: String?, alreadyRetired: Bool)
    case failed(message: String)
}

enum SumbaDeletePasswordVerifyResult {
    case success
    case incorrectPassword
    case rateLimited
    case failed(message: String)
}

/// Account retire via Talk Upload Policy (requires `sumbachat-client.accountRetire.enabled`).
///
/// `DELETE /ocs/v2.php/apps/talk_upload_policy/api/v1/account`
///
/// Headers: `OCS-APIRequest`, `Accept: application/json`, `Authorization: Basic` (username:password).
/// Success: `202 Accepted` with `anonymizedDisplayName`, `retiredAt`, `alreadyRetired`.
/// The server invalidates the session — the client clears local credentials after success.
enum SumbaDeleteAccountService {

    private static let retireAPIPath = "/ocs/v2.php/apps/talk_upload_policy/api/v1/account"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    static func verifyPassword(
        account: TalkAccount,
        password: String,
        completion: @escaping (SumbaDeletePasswordVerifyResult) -> Void
    ) {
        let accountId = account.accountId
        NCLog.log("Delete account: verifying password for \(accountId)")

        let base = account.server.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/ocs/v2.php/cloud/user") else {
            NCLog.log("Delete account: verify failed — invalid server URL for \(accountId)")
            DispatchQueue.main.async {
                completion(.failed(message: NSLocalizedString("Invalid server URL.", comment: "")))
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyCommonHeaders(to: &request, loginName: account.user, password: password)

        session.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error {
                    NCLog.log("Delete account: verify network error for \(accountId) — \(error.localizedDescription)")
                    completion(.failed(message: error.localizedDescription))
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                switch code {
                case 200...299:
                    NCLog.log("Delete account: password verified for \(accountId) (HTTP \(code))")
                    completion(.success)
                case 429:
                    NCLog.log("Delete account: verify rate-limited for \(accountId) (HTTP 429)")
                    completion(.rateLimited)
                case 401, 403:
                    NCLog.log("Delete account: incorrect password for \(accountId) (HTTP \(code))")
                    completion(.incorrectPassword)
                default:
                    NCLog.log("Delete account: verify failed for \(accountId) (HTTP \(code))")
                    completion(.incorrectPassword)
                }
            }
        }.resume()
    }

    static func deleteAccount(
        account: TalkAccount,
        password: String,
        completion: @escaping (SumbaDeleteAccountResult) -> Void
    ) {
        let accountId = account.accountId

        guard SumbaChatClientConfig.accountRetireSupported else {
            NCLog.log("Delete account: blocked — accountRetire.enabled != true for \(accountId)")
            DispatchQueue.main.async {
                completion(.failed(message: NSLocalizedString(
                    "Account deletion is not available on this server.",
                    comment: "Delete account when talk_upload_policy retire is disabled"
                )))
            }
            return
        }

        NCLog.log("Delete account: calling talk_upload_policy/account for \(accountId)")

        performRetire(account: account, password: password, completion: completion)
    }

    private static func performRetire(
        account: TalkAccount,
        password: String,
        completion: @escaping (SumbaDeleteAccountResult) -> Void
    ) {
        let accountId = account.accountId
        let base = account.server.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)\(retireAPIPath)") else {
            NCLog.log("Delete account: retire URL invalid for \(accountId)")
            DispatchQueue.main.async {
                completion(.failed(message: NSLocalizedString("Invalid server URL.", comment: "")))
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applyCommonHeaders(to: &request, loginName: account.user, password: password)

        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    NCLog.log("Delete account: retire network error for \(accountId) — \(error.localizedDescription)")
                    completion(.failed(message: error.localizedDescription))
                    return
                }

                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let message = ocsMessage(from: data)
                let payload = ocsRetirePayload(from: data)

                switch code {
                case 200, 201, 202:
                    NCLog.log("Delete account: retire succeeded for \(accountId) (HTTP \(code)) alreadyRetired=\(payload.alreadyRetired) name=\(payload.anonymizedDisplayName ?? "nil")")
                    completion(.deleted(
                        anonymizedDisplayName: payload.anonymizedDisplayName,
                        alreadyRetired: payload.alreadyRetired
                    ))
                case 401:
                    NCLog.log("Delete account: retire not logged in for \(accountId) (HTTP 401)")
                    completion(.failed(message: message ?? NSLocalizedString(
                        "You are not logged in. Sign in again and retry.",
                        comment: "Delete account retire HTTP 401"
                    )))
                case 403:
                    NCLog.log("Delete account: retire forbidden for \(accountId) (HTTP 403)")
                    completion(.failed(message: message ?? NSLocalizedString(
                        "Account deletion is not allowed (for example, retire is disabled or you are the sole administrator).",
                        comment: "Delete account retire HTTP 403"
                    )))
                case 404:
                    NCLog.log("Delete account: retire user not found for \(accountId) (HTTP 404)")
                    completion(.failed(message: message ?? NSLocalizedString(
                        "Account not found.",
                        comment: "Delete account retire HTTP 404"
                    )))
                case 429:
                    NCLog.log("Delete account: retire rate-limited for \(accountId) (HTTP 429)")
                    completion(.failed(message: SumbaServerConfiguration.tooManyAttemptsMessage))
                default:
                    NCLog.log("Delete account: retire failed for \(accountId) (HTTP \(code))")
                    completion(.failed(message: message ?? String(
                        format: NSLocalizedString("Couldn’t delete account (error %d).", comment: ""),
                        code
                    )))
                }
            }
        }.resume()
    }

    private static func applyCommonHeaders(to request: inout URLRequest, loginName: String, password: String) {
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(NCAppBranding.userAgent(), forHTTPHeaderField: "User-Agent")
        // Strict password confirmation requires Basic login:password on this request.
        request.setValue(basicAuthHeader(user: loginName, password: password), forHTTPHeaderField: "Authorization")
    }

    private static func basicAuthHeader(user: String, password: String) -> String {
        let credentials = "\(user):\(password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private static func ocsMessage(from data: Data?) -> String? {
        guard let dataDict = ocsData(from: data) else { return nil }
        if let message = dataDict["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }

    private struct RetirePayload {
        var anonymizedDisplayName: String?
        var alreadyRetired: Bool = false
        var retiredAt: Int?
    }

    private static func ocsRetirePayload(from data: Data?) -> RetirePayload {
        var payload = RetirePayload()
        guard let dataDict = ocsData(from: data) else { return payload }

        if let name = dataDict["anonymizedDisplayName"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload.anonymizedDisplayName = name
        }

        if let already = dataDict["alreadyRetired"] as? Bool {
            payload.alreadyRetired = already
        } else if let already = dataDict["alreadyRetired"] as? NSNumber {
            payload.alreadyRetired = already.boolValue
        }

        if let retiredAt = dataDict["retiredAt"] as? Int {
            payload.retiredAt = retiredAt
        } else if let retiredAt = dataDict["retiredAt"] as? NSNumber {
            payload.retiredAt = retiredAt.intValue
        }

        return payload
    }

    private static func ocsData(from data: Data?) -> [String: Any]? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ocs = json["ocs"] as? [String: Any] else {
            return nil
        }

        if let dataDict = ocs["data"] as? [String: Any] {
            return dataDict
        }
        if let meta = ocs["meta"] as? [String: Any] {
            return meta
        }
        return nil
    }
}
