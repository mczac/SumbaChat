//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import NextcloudKit

class DirectoryTableViewController: UITableViewController, UISearchResultsUpdating {

    /// Shared when pushing into subfolders so the type filter stays applied.
    enum FileTypeFilter: Int {
        case all
        case video
        case audio
        case documents

        var title: String {
            switch self {
            case .all:
                return NSLocalizedString("All", comment: "File type filter: show all files")
            case .video:
                return NSLocalizedString("Video", comment: "File type filter: videos only")
            case .audio:
                return NSLocalizedString("Audio", comment: "File type filter: audio only")
            case .documents:
                return NSLocalizedString("Documents", comment: "File type filter: documents only")
            }
        }

        var systemImageName: String {
            switch self {
            case .all:
                return "square.grid.2x2"
            case .video:
                return "video"
            case .audio:
                return "waveform"
            case .documents:
                return "doc"
            }
        }
    }

    private struct FileListSection {
        let title: String?
        let items: [NKFile]
    }

    private let path: String
    private let token: String
    private let threadId: Int

    private var userHomePath = ""
    /// Full folder listing from the server (unfiltered).
    private var allItemsInDirectory: [NKFile] = []
    /// Sorted + filtered sections shown in the table.
    private var sections: [FileListSection] = []
    private var fileTypeFilter: FileTypeFilter
    private var nameSearchText: String = ""
    private var sortingButton: UIBarButtonItem?
    private var filterButton: UIBarButtonItem?
    private var searchController: UISearchController!
    private let directoryBackgroundView = PlaceholderView()
    private let sharingFileView = UIActivityIndicatorView()

    init(path: String, inRoom token: String, andThread threadId: Int, fileTypeFilter: FileTypeFilter = .all) {
        self.path = path
        self.token = token
        self.threadId = threadId
        self.fileTypeFilter = fileTypeFilter

        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        userHomePath = NCAPIController.sharedInstance().filesPath(forAccount: activeAccount)

        configureSearchController()
        configureNavigationBar()

        if #available(iOS 26.0, *) {
            sharingFileView.color = .label
        } else {
            sharingFileView.color = NCAppBranding.themeTextColor()
        }

        self.tableView.tableFooterView = UIView(frame: .zero)

        // Directory placeholder view
        directoryBackgroundView.setImage(UIImage(named: "folder-placeholder"))
        directoryBackgroundView.placeholderTextView.text = NSLocalizedString("No files in here", comment: "")
        directoryBackgroundView.placeholderView.isHidden = true
        directoryBackgroundView.loadingView.startAnimating()
        self.tableView.backgroundView = directoryBackgroundView

        NCAppBranding.styleViewController(self)

        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 0)

        self.tableView.register(UINib(nibName: DirectoryTableViewCell.nibName, bundle: nil), forCellReuseIdentifier: DirectoryTableViewCell.identifier)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        getItemsInDirectory()
    }

    @objc private func cancelButtonPressed() {
        self.dismiss(animated: true)
    }

    @objc private func shareButtonPressed() {
        showConfirmationDialogForSharingItem(withPath: path,
                                             andName: (path as NSString).lastPathComponent,
                                             isDirectory: true)
    }

    private func addMenuToSortingButton() {
        let settings = NCSettingsController.sharedInstance()
        let preferredSorting = settings.getPreferredFileSorting()
        let ascending = settings.isPreferredFileSortingAscending()

        let nameAscending = UIAction(
            title: NSLocalizedString("Name A–Z", comment: "File browser sort: name ascending"),
            image: UIImage(systemName: "character.square")
        ) { [weak self] _ in
            settings.setPreferredFileSorting(.alphabeticalSorting)
            settings.setPreferredFileSortingAscending(true)
            self?.applyFilterAndSort()
        }

        let nameDescending = UIAction(
            title: NSLocalizedString("Name Z–A", comment: "File browser sort: name descending"),
            image: UIImage(systemName: "character.square")
        ) { [weak self] _ in
            settings.setPreferredFileSorting(.alphabeticalSorting)
            settings.setPreferredFileSortingAscending(false)
            self?.applyFilterAndSort()
        }

        let dateNewest = UIAction(
            title: NSLocalizedString("Date (newest first)", comment: "File browser sort: date descending"),
            image: UIImage(systemName: "clock")
        ) { [weak self] _ in
            settings.setPreferredFileSorting(.modificationDateSorting)
            settings.setPreferredFileSortingAscending(false)
            self?.applyFilterAndSort()
        }

        let dateOldest = UIAction(
            title: NSLocalizedString("Date (oldest first)", comment: "File browser sort: date ascending"),
            image: UIImage(systemName: "clock")
        ) { [weak self] _ in
            settings.setPreferredFileSorting(.modificationDateSorting)
            settings.setPreferredFileSortingAscending(true)
            self?.applyFilterAndSort()
        }

        nameAscending.state = (preferredSorting == .alphabeticalSorting && ascending) ? .on : .off
        nameDescending.state = (preferredSorting == .alphabeticalSorting && !ascending) ? .on : .off
        dateNewest.state = (preferredSorting == .modificationDateSorting && !ascending) ? .on : .off
        dateOldest.state = (preferredSorting == .modificationDateSorting && ascending) ? .on : .off

        sortingButton?.menu = UIMenu(children: [nameAscending, nameDescending, dateNewest, dateOldest])
    }

    private func addMenuToFilterButton() {
        let filters: [FileTypeFilter] = [.all, .video, .audio, .documents]
        let actions = filters.map { filter -> UIAction in
            let action = UIAction(title: filter.title, image: UIImage(systemName: filter.systemImageName)) { [weak self] _ in
                guard let self, self.fileTypeFilter != filter else { return }
                self.fileTypeFilter = filter
                self.applyFilterAndSort()
                self.updateFilterButtonAppearance()
            }
            action.state = fileTypeFilter == filter ? .on : .off
            return action
        }
        filterButton?.menu = UIMenu(title: NSLocalizedString("Filter", comment: "File browser type filter menu"),
                                    children: actions)
    }

    private func updateFilterButtonAppearance() {
        let imageName = fileTypeFilter == .all
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
        filterButton?.image = UIImage(systemName: imageName)
        filterButton?.accessibilityLabel = NSLocalizedString("Filter files", comment: "")
        addMenuToFilterButton()
    }

    // MARK: - Files

    private func getItemsInDirectory() {
        NCAPIController.sharedInstance().readFolder(forAccount: NCDatabaseManager.sharedInstance().activeAccount(), atPath: path, withDepth: "1") { [weak self] items, error in
            guard let self, let items, error == nil else { return }

            let currentDirectory = self.path.isEmpty ? "/" : (self.path as NSString).lastPathComponent
            var itemsInDirectory: [NKFile] = []

            for item in items {
                var itemPath = item.path.replacingOccurrences(of: self.userHomePath, with: "")

                // When nextcloud is installed in a subdirectory, it's not enough to replace the userHomePath,
                // because the subdirectory would get a part of the itemPath (see https://github.com/nextcloud/talk-ios/issues/996)
                let itemPathParts = item.path.components(separatedBy: self.userHomePath)
                if itemPathParts.count > 1 {
                    itemPath = itemPathParts[1]
                }

                if (itemPath as NSString).lastPathComponent == currentDirectory, !item.e2eEncrypted {
                    itemsInDirectory.append(item)
                }
            }

            self.allItemsInDirectory = itemsInDirectory
            self.applyFilterAndSort()

            self.directoryBackgroundView.loadingView.stopAnimating()
            self.directoryBackgroundView.loadingView.isHidden = true
            self.updatePlaceholderVisibility()
        }
    }

    private func applyFilterAndSort() {
        let query = nameSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hideFoldersForTypeFilter = fileTypeFilter != .all

        var filtered = allItemsInDirectory.filter { item in
            if !query.isEmpty,
               item.fileName.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                return false
            }

            // Type filters hide folders (attachment pick). Name search keeps matching folders for navigation.
            if item.directory {
                if hideFoldersForTypeFilter {
                    return !query.isEmpty
                }
                return true
            }

            switch fileTypeFilter {
            case .all:
                return true
            case .video:
                return NCUtils.isVideo(fileType: item.contentType)
            case .audio:
                return NCUtils.isAudio(fileType: item.contentType)
            case .documents:
                return NCUtils.isDocument(fileType: item.contentType)
            }
        }

        let settings = NCSettingsController.sharedInstance()
        let sortByName = settings.getPreferredFileSorting() == .alphabeticalSorting
        let ascending = settings.isPreferredFileSortingAscending()

        if sortByName {
            filtered.sort { lhs, rhs in
                let result = lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName)
                return ascending ? (result == .orderedAscending) : (result == .orderedDescending)
            }
            sections = filtered.isEmpty ? [] : [FileListSection(title: nil, items: filtered)]
        } else {
            filtered.sort { lhs, rhs in
                let lhsDate = lhs.date as Date
                let rhsDate = rhs.date as Date
                if lhsDate == rhsDate {
                    let result = lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName)
                    return result == .orderedAscending
                }
                return ascending ? (lhsDate < rhsDate) : (lhsDate > rhsDate)
            }
            sections = Self.daySections(from: filtered)
        }

        addMenuToSortingButton()
        addMenuToFilterButton()
        updatePlaceholderVisibility()
        tableView.reloadData()
    }

    /// Group already-sorted items into calendar-day sections (sticky via UITableView headers).
    private static func daySections(from items: [NKFile]) -> [FileListSection] {
        guard !items.isEmpty else { return [] }

        let calendar = Calendar.current
        var result: [FileListSection] = []
        var currentDay: Date?
        var currentItems: [NKFile] = []

        for item in items {
            let day = calendar.startOfDay(for: item.date as Date)
            if currentDay == nil {
                currentDay = day
            }
            if day != currentDay {
                if let currentDay, !currentItems.isEmpty {
                    result.append(FileListSection(title: NCUtils.fileListDaySectionTitle(from: currentDay), items: currentItems))
                }
                currentDay = day
                currentItems = [item]
            } else {
                currentItems.append(item)
            }
        }

        if let currentDay, !currentItems.isEmpty {
            result.append(FileListSection(title: NCUtils.fileListDaySectionTitle(from: currentDay), items: currentItems))
        }

        return result
    }

    private func item(at indexPath: IndexPath) -> NKFile? {
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].items.indices.contains(indexPath.row) else {
            return nil
        }
        return sections[indexPath.section].items[indexPath.row]
    }

    private func updatePlaceholderVisibility() {
        let hasRows = sections.contains { !$0.items.isEmpty }
        directoryBackgroundView.placeholderView.isHidden = hasRows
        let hasNameQuery = !nameSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if fileTypeFilter == .all && !hasNameQuery {
            directoryBackgroundView.placeholderTextView.text = NSLocalizedString("No files in here", comment: "")
        } else {
            directoryBackgroundView.placeholderTextView.text = NSLocalizedString("No matching files", comment: "")
        }
    }

    private func shareFile(withPath path: String) {
        setSharingFileUI()

        var talkMetaData: [String: Any] = [:]
        if threadId > 0 {
            talkMetaData["threadId"] = threadId
        }

        NCAPIController.sharedInstance().shareFileOrFolder(forAccount: NCDatabaseManager.sharedInstance().activeAccount(), atPath: path, toRoom: token, withTalkMetaData: talkMetaData, withReferenceId: nil) { [weak self] error in
            guard let self else { return }

            if let error {
                self.removeSharingFileUI()
                self.showErrorSharingItem()
                print("Error sharing file or folder: \(error)")
            } else {
                self.dismiss(animated: true)
            }
        }
    }

    // MARK: - Utils

    private func configureSearchController() {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("Search by name", comment: "SumbaFiles browser search placeholder")
        searchController.searchBar.autocapitalizationType = .none
        self.searchController = searchController
        self.navigationItem.searchController = searchController
        self.navigationItem.preferredSearchBarPlacement = .stacked
        self.definesPresentationContext = true
    }

    private func configureNavigationBar() {
        let sortingButton = UIBarButtonItem(image: UIImage(systemName: "arrow.up.arrow.down"), style: .plain, target: self, action: nil)
        self.sortingButton = sortingButton
        addMenuToSortingButton()

        let filterButton = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"), style: .plain, target: self, action: nil)
        self.filterButton = filterButton
        updateFilterButtonAppearance()

        // Keep search attached across sharing-spinner resets of the right bar items.
        self.navigationItem.searchController = searchController

        // Home folder
        if path.isEmpty {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonPressed))
            self.navigationItem.rightBarButtonItems = [sortingButton, filterButton]

            let navigationLogo = UIImage(systemName: "house")
            let navigationImageView = UIImageView(image: navigationLogo)
            navigationImageView.image = navigationImageView.image?.withRenderingMode(.alwaysTemplate)
            if #available(iOS 26.0, *) {
                navigationImageView.tintColor = .label
            } else {
                navigationImageView.tintColor = NCAppBranding.themeTextColor()
            }
            self.navigationItem.titleView = navigationImageView

            self.navigationItem.backBarButtonItem = UIBarButtonItem(image: navigationLogo, style: .plain, target: nil, action: nil)
            // Other directories
        } else {
            let shareButton = UIBarButtonItem(image: UIImage(named: "sharing"), style: .plain, target: self, action: #selector(shareButtonPressed))
            self.navigationItem.rightBarButtonItems = [sortingButton, filterButton, shareButton]

            self.navigationItem.title = (path as NSString).lastPathComponent
        }
    }

    // MARK: - UISearchResultsUpdating

    func updateSearchResults(for searchController: UISearchController) {
        nameSearchText = searchController.searchBar.text ?? ""
        applyFilterAndSort()
    }

    private func setSharingFileUI() {
        sharingFileView.startAnimating()
        self.navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: sharingFileView)]
        self.navigationController?.navigationBar.isUserInteractionEnabled = false
        self.tableView.isUserInteractionEnabled = false
    }

    private func removeSharingFileUI() {
        sharingFileView.stopAnimating()
        configureNavigationBar()
        self.navigationController?.navigationBar.isUserInteractionEnabled = true
        self.tableView.isUserInteractionEnabled = true
    }

    private func showConfirmationDialogForSharingItem(withPath path: String, andName name: String, isDirectory: Bool) {
        let title = isDirectory
            ? NSLocalizedString("Share Folder", comment: "Confirm sharing a folder into the conversation")
            : NSLocalizedString("Share File", comment: "Confirm sharing a file into the conversation")
        let message = String(
            format: NSLocalizedString("Do you want to share '%@' in the conversation?", comment: ""),
            NCUtils.middleTruncatedFileName(name)
        )
        let confirmDialog = UIAlertController(title: title, message: message, preferredStyle: .alert)
        confirmDialog.addAction(UIAlertAction(title: NSLocalizedString("Share", comment: ""), style: .default) { [weak self] _ in
            self?.shareFile(withPath: path)
        })
        confirmDialog.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        self.present(confirmDialog, animated: true)
    }

    private func showErrorSharingItem() {
        let confirmDialog = UIAlertController(title: NSLocalizedString("Could not share file", comment: ""),
                                              message: NSLocalizedString("An error occurred while sharing the file", comment: ""),
                                              preferredStyle: .alert)
        confirmDialog.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        self.present(confirmDialog, animated: true)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard sections.indices.contains(section) else { return 0 }
        return sections[section].items.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard sections.indices.contains(section) else { return nil }
        return sections[section].title
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return DirectoryTableViewCell.cellHeight
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DirectoryTableViewCell.identifier) as? DirectoryTableViewCell ??
                   DirectoryTableViewCell(style: .default, reuseIdentifier: DirectoryTableViewCell.identifier)

        guard let item = item(at: indexPath) else {
            return cell
        }

        // Name (middle-truncated in the cell) + size · relative date
        cell.fileNameLabel.text = item.fileName
        if item.directory {
            cell.fileInfoLabel.text = NCUtils.relativeTimeFromDate(date: item.date as Date)
        } else {
            cell.fileInfoLabel.text = NCUtils.fileListSubtitle(size: item.size, date: item.date as Date)
        }

        // Icon or preview
        if item.directory {
            cell.fileImageView.image = UIImage(named: "folder")
        } else if item.hasPreview {
            cell.fileImageView.setPreview(forFileId: item.fileId, withWidth: 40, withHeight: 40, usingAccount: NCDatabaseManager.sharedInstance().activeAccount())
        } else {
            cell.fileImageView.image = UIImage(named: NCUtils.previewImage(forMimeType: item.contentType))
        }

        // Disclosure indicator
        cell.accessoryType = item.directory ? .disclosureIndicator : .none

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = item(at: indexPath) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        let selectedItemPath = "\(path)/\(item.fileName)"

        if item.directory {
            let directoryVC = DirectoryTableViewController(path: selectedItemPath,
                                                           inRoom: token,
                                                           andThread: threadId,
                                                           fileTypeFilter: fileTypeFilter)
            self.navigationController?.pushViewController(directoryVC, animated: true)
        } else {
            showConfirmationDialogForSharingItem(withPath: selectedItemPath, andName: item.fileName, isDirectory: false)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}
