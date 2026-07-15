//
// SPDX-FileCopyrightText: 2026 SumbaChat contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objc protocol SumbaLoginViewControllerDelegate: AnyObject {
    func sumbaLoginViewControllerDidFinish(_ viewController: SumbaLoginViewController)
}

@objcMembers final class SumbaLoginViewController: UIViewController, UITextFieldDelegate {

    weak var delegate: SumbaLoginViewControllerDelegate?

    private let serverURL: String
    private var loginTask: URLSessionDataTask?
    private lazy var loginSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()
    private weak var activeTextField: UITextField?

    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = false
        return view
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var usernameTextField = makeTextField(
        placeholder: NSLocalizedString("Username", comment: ""),
        systemImage: "person.fill",
        contentType: .username
    )

    private lazy var passwordTextField: UITextField = {
        let field = makeTextField(
            placeholder: NSLocalizedString("Password", comment: ""),
            systemImage: "lock.fill",
            contentType: .password
        )
        field.isSecureTextEntry = true
        field.returnKeyType = .go

        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "eye"), for: .normal)
        button.tintColor = .secondaryLabel
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        button.accessibilityLabel = NSLocalizedString("Show password", comment: "")
        button.addTarget(self, action: #selector(togglePasswordVisibility), for: .touchUpInside)
        field.rightView = button
        field.rightViewMode = .always
        return field
    }()

    private lazy var loginButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = NSLocalizedString("Sign in", comment: "")
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = NCAppBranding.brandColor()
        configuration.baseForegroundColor = NCAppBranding.brandTextColor()
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .headline)
            return attributes
        }

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(signIn), for: .touchUpInside)
        return button
    }()

    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.textAlignment = .center
        label.isHidden = true
        label.accessibilityTraits = .staticText
        return label
    }()

    init(serverURL: String) {
        self.serverURL = serverURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        registerForKeyboardNotifications()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        usernameTextField.becomeFirstResponder()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        loginTask?.cancel()
        loginSession.invalidateAndCancel()
    }

    private func configureView() {
        title = NSLocalizedString("Sign in", comment: "")
        view.backgroundColor = .systemBackground
        NCAppBranding.styleViewController(self)

        if NCDatabaseManager.sharedInstance().numberOfAccounts() > 0 {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                systemItem: .cancel,
                primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
            )
        }

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.text = "SumbaChat"

        let subtitleLabel = UILabel()
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = NSLocalizedString("Enter your username and password to continue.", comment: "")

        let serverLabel = UILabel()
        serverLabel.font = .preferredFont(forTextStyle: .footnote)
        serverLabel.textColor = .tertiaryLabel
        serverLabel.textAlignment = .center
        serverLabel.text = serverURL

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            serverLabel,
            usernameTextField,
            passwordTextField,
            errorLabel,
            loginButton
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(8, after: titleLabel)
        stack.setCustomSpacing(4, after: subtitleLabel)
        stack.setCustomSpacing(32, after: serverLabel)
        stack.setCustomSpacing(12, after: usernameTextField)
        stack.setCustomSpacing(24, after: passwordTextField)

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),

            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -32),

            usernameTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            passwordTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            loginButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    private func makeTextField(placeholder: String,
                               systemImage: String,
                               contentType: UITextContentType) -> UITextField {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.delegate = self
        field.placeholder = placeholder
        field.textContentType = contentType
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .next
        field.borderStyle = .none
        field.backgroundColor = .secondarySystemBackground
        field.layer.cornerRadius = 12
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor.separator.cgColor

        let icon = UIImageView(image: UIImage(systemName: systemImage))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit

        let container = UIView(frame: CGRect(x: 0, y: 0, width: 48, height: 56))
        icon.frame = CGRect(x: 16, y: 18, width: 20, height: 20)
        container.addSubview(icon)
        field.leftView = container
        field.leftViewMode = .always
        return field
    }

    private func registerForKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let frameInView = view.convert(keyboardFrame, from: nil)
        let overlap = max(0, view.bounds.maxY - frameInView.minY)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap

        if let activeTextField {
            scrollView.scrollRectToVisible(activeTextField.convert(activeTextField.bounds, to: scrollView).insetBy(dx: 0, dy: -24), animated: true)
        }
    }

    @objc private func keyboardWillHide() {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func togglePasswordVisibility(_ sender: UIButton) {
        passwordTextField.isSecureTextEntry.toggle()
        let imageName = passwordTextField.isSecureTextEntry ? "eye" : "eye.slash"
        sender.setImage(UIImage(systemName: imageName), for: .normal)
        sender.accessibilityLabel = passwordTextField.isSecureTextEntry
            ? NSLocalizedString("Show password", comment: "")
            : NSLocalizedString("Hide password", comment: "")
    }

    @objc private func signIn() {
        guard loginTask == nil else {
            return
        }

        errorLabel.isHidden = true

        guard let username = usernameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty else {
            showValidationError(NSLocalizedString("Enter your username.", comment: ""), field: usernameTextField)
            return
        }

        guard let password = passwordTextField.text, !password.isEmpty else {
            showValidationError(NSLocalizedString("Enter your password.", comment: ""), field: passwordTextField)
            return
        }

        dismissKeyboard()
        setLoading(true)
        requestAppPassword(username: username, password: password)
    }

    private func requestAppPassword(username: String, password: String) {
        guard let url = URL(string: "\(serverURL)/ocs/v2.php/core/getapppassword?format=json") else {
            completeWithError(NSLocalizedString("The server address is invalid.", comment: ""))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(NCAppBranding.userAgentForLogin(), forHTTPHeaderField: "User-Agent")

        let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

        loginTask = loginSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleLoginResponse(data: data, response: response, error: error, username: username)
            }
        }
        loginTask?.resume()
    }

    private func handleLoginResponse(data: Data?,
                                     response: URLResponse?,
                                     error: Error?,
                                     username: String) {
        loginTask = nil

        if let error {
            completeWithError(error.localizedDescription)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            completeWithError(NSLocalizedString("The server did not return a valid response.", comment: ""))
            return
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            completeWithError(NSLocalizedString("Incorrect username or password.", comment: ""))
            return
        }

        guard (200...299).contains(httpResponse.statusCode),
              let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ocs = root["ocs"] as? [String: Any],
              let responseData = ocs["data"] as? [String: Any],
              let appPassword = responseData["apppassword"] as? String,
              !appPassword.isEmpty else {
            let message = serverErrorMessage(from: data)
                ?? NSLocalizedString("Sign in failed. Check your details and try again.", comment: "")
            completeWithError(message)
            return
        }

        passwordTextField.text = nil
        NCSettingsController.sharedInstance().addNewAccount(forUser: username, withToken: appPassword, inServer: serverURL)
        setLoading(false)
        delegate?.sumbaLoginViewControllerDidFinish(self)
    }

    private func serverErrorMessage(from data: Data?) -> String? {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ocs = root["ocs"] as? [String: Any],
              let meta = ocs["meta"] as? [String: Any],
              let message = meta["message"] as? String,
              !message.isEmpty else {
            return nil
        }
        return message
    }

    private func showValidationError(_ message: String, field: UITextField) {
        errorLabel.text = message
        errorLabel.isHidden = false
        field.becomeFirstResponder()
    }

    private func completeWithError(_ message: String) {
        setLoading(false)
        errorLabel.text = message
        errorLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func setLoading(_ loading: Bool) {
        usernameTextField.isEnabled = !loading
        passwordTextField.isEnabled = !loading
        loginButton.isEnabled = !loading

        if loading {
            loginButton.configuration?.showsActivityIndicator = true
            loginButton.configuration?.title = NSLocalizedString("Signing in…", comment: "")
        } else {
            loginButton.configuration?.showsActivityIndicator = false
            loginButton.configuration?.title = NSLocalizedString("Sign in", comment: "")
        }
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        activeTextField = textField
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if activeTextField === textField {
            activeTextField = nil
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === usernameTextField {
            passwordTextField.becomeFirstResponder()
        } else {
            signIn()
        }
        return true
    }
}
