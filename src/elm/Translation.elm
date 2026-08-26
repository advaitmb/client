module Translation exposing (TranslationId(..), timeDistInWords, tr)

import Time
import Time.Distance as TimeDistance
import Time.Distance.I18n as I18n


type TranslationId
    = NoTr String
    | Cancel
      -- Template and Import modal
    | NewDocument
    | ShowDocumentList
    | SortByName
    | SortByLastModified
    | SortByDateCreated
    | TemplatesAndExamples
    | New
    | HomeBlank
    | HomeImportJSON
    | HomeJSONFrom
    | ImportSectionTitle
    | HomeImportLegacy
    | HomeLegacyFrom
    | ImportTextFiles
    | ImportTextFilesDesc
    | ImportOpmlFiles
    | ImportOpmlFilesDesc
    | TimelineTemplate
    | TimelineTemplateDesc
    | AcademicPaperTemplate
    | AcademicPaperTemplateDesc
    | ProjectBrainstormingTemplate
    | ProjectBrainstormingTemplateDesc
    | HerosJourneyTemplate
    | HerosJourneyTemplateDesc
      --
    | RecentDocuments
    | LastUpdated
    | LastOpened
    | OpenOtherDocuments
    | DeleteDocument
    | RemoveFromList
    | NeverSaved
    | Loading
    | UnsavedChanges
    | SavedInternally
    | ChangesSaved
    | ChangesSynced
    | DatabaseError
    | LastSaved
    | LastSynced
    | LastEdit
    | ConfirmBannerStrong
    | ConfirmBannerBody
    | Help
    | WhatsNew
    | AccountTooltip
      -- Keyboard Shortcut Help
    | KeyboardShortcuts
    | ViewModeShortcuts
    | CardEditCreateDelete
    | NavigationMovingCards
    | CopyPaste
    | SearchingMerging
    | HelpInfoDocs
    | EditModeShortcuts
    | CardSaveCreate
    | EditCard
    | AddCardBelow
    | AddCardAbove
    | AddCardToRight
    | AddCardBelowSplit
    | AddCardAboveSplit
    | AddCardToRightSplit
    | DeleteCard
    | GoUpDownLeftRight
    | GoToBeginningOfGroup
    | GoToEndOfGroup
    | GoToBeginningOfColumn
    | GoToEndOfColumn
    | MoveCurrentCard
    | PageUp
    | PageDown
    | HomeKey
    | EndKey
    | AnyOfAbove
    | DragCard
    | Search
    | ClearSearch
    | MergeCardUp
    | MergeCardDown
    | WorksAcrossDocuments
    | CopyCurrent
    | PasteBelow
    | PasteAsChild
    | InsertSelected
    | DragSelected
    | WordCounts
    | SwitchDocuments
    | ThisHelpScreen
    | Or
    | EditCardFullscreen
    | EditCards
    | KeyboardHelp
    | RestoreThisVersion
    | EnterKey
    | ShiftKey
    | EnterAction
    | AltKey
    | EditFullscreenAction
    | Navigate
    | EditCardTitle
    | ArrowsAction
    | AddNewCards
    | AddChildAction
    | InsertChildTitle
    | AddBelowAction
    | InsertBelowTitle
    | AddAboveAction
    | SplitAtCursor
    | SplitChildAction
    | SplitBelowAction
    | SplitUpwardAction
    | MergeCards
    | MergeDownAction
    | MergeUpAction
    | InsertAboveTitle
    | ArrowKeys
    | MoveAndDelete
    | MoveAction
    | Backspace
    | DeleteAction
    | DeleteCardTitle
    | FormattingGuide
    | ForBold
    | BoldSelection
    | ForItalic
    | ItalicizeSelection
    | ForInsertLink
    | InsertLink
    | SaveChanges
    | SaveChangesAndExit
    | ExitEditMode
    | ToSaveChanges
    | SaveChangesTitle
    | EscKey
    | OtherShortcuts
    | DisplayWordCounts
    | EditMode
    | SaveOrCancelChanges
    | Formatting
    | FormattingTitle
    | SetTitleLevel
    | FormattingList
    | FormattingLink
    | ParenNumber
    | SetHeadingLevel
    | HelpVideos
    | FAQAndDocs
      --
    | AreYouSureCancel
    | ToCancelChanges
    | PressToSearch
    | QuickDocumentSwitcher
    | OpenQuickSwitcher
    | ContactSupport
    | Logout
    | ContributeTranslations
    | Here
    | HeadingFont
    | ContentFont
    | EditingFont
    | MigrateTooltip
    | VersionHistory
    | DocumentSettings
    | WordCount
    | WordCountSession Int
    | WordCountTotal Int
    | WordCountCard Int
    | WordCountSubtree Int
    | WordCountGroup Int
    | WordCountColumn Int
    | CharacterCountCard Int
    | CharacterCountSubtree Int
    | CharacterCountGroup Int
    | CharacterCountColumn Int
    | CharacterCountTotal Int
    | WordCountTotalCards Int
    | DocumentTheme
    | ThemeDefault
    | ThemeDarkMode
    | ThemeClassic
    | ThemeGray
    | ThemeGreen
    | ThemeTurquoise
      -- Exporting
    | ExportOrPrint
    | ExportSettingEverything
    | ExportSettingEverythingDesc
    | ExportSettingCurrentSubtree
    | ExportSettingCurrentSubtreeDesc
    | ExportSettingLeavesOnly
    | ExportSettingLeavesOnlyDesc
    | ExportSettingCurrentColumn
    | ExportSettingCurrentColumnDesc
    | ExportSettingWord
    | ExportSettingPlainText
    | ExportSettingJSON
    | ExportSettingOPML
    | CloseExportView
    | DownloadWordFile
    | DownloadTextFile
    | DownloadJSONFile
    | DownloadOPMLFile
    | PrintThis
      -- Upgrade & Subscription
    | Upgrade
    | DaysLeft Int
    | TrialExpired
    | WordOfMouthCTA1
    | WordOfMouthCTA2
    | ManageSubscription


tr : TranslationId -> String
tr trans =
    let
        numberPlural n sing pl =
            if n == 1 then
                sing |> String.replace "%1" (String.fromInt n)

            else
                pl |> String.replace "%1" (String.fromInt n)

        translationSet =
            case trans of
                NoTr str ->
                    { en = str
                    }

                Cancel ->
                    { en = "Cancel"
                    }

                -- Template and Import modal
                NewDocument ->
                    { en = "New Document"
                    }

                ShowDocumentList ->
                    { en = "Show Document List"
                    }

                SortByName ->
                    { en = "Sort by Name"
                    }

                SortByLastModified ->
                    { en = "Sort by Last Modified"
                    }

                SortByDateCreated ->
                    { en = "Sort by Date Created"
                    }

                TemplatesAndExamples ->
                    { en = "Templates & Examples"
                    }

                New ->
                    { en = "New"
                    }

                HomeBlank ->
                    { en = "Blank Tree"
                    }

                HomeImportJSON ->
                    { en = "Import JSON tree"
                    }

                HomeJSONFrom ->
                    { en = "From Gingko Desktop or Online export file"
                    }

                ImportSectionTitle ->
                    { en = "Import"
                    }

                HomeImportLegacy ->
                    { en = "From Old Account"
                    }

                HomeLegacyFrom ->
                    { en = "Bulk transfer of trees from your legacy account"
                    }

                ImportTextFiles ->
                    { en = "Import Text Files"
                    }

                ImportTextFilesDesc ->
                    { en = "Import multiple markdown or regular text files."
                    }

                ImportOpmlFiles ->
                    { en = "Import Opml Files"
                    }

                ImportOpmlFilesDesc ->
                    { en = "Import from Workflowy or other outliners."
                    }

                TimelineTemplate ->
                    { en = "Timeline 2026"
                    }

                TimelineTemplateDesc ->
                    { en = "A tree-based calendar"
                    }

                AcademicPaperTemplate ->
                    { en = "Academic Paper"
                    }

                AcademicPaperTemplateDesc ->
                    { en = "Starting point for journal paper"
                    }

                ProjectBrainstormingTemplate ->
                    { en = "Project Brainstorming"
                    }

                ProjectBrainstormingTemplateDesc ->
                    { en = "Example on clarifying project goals"
                    }

                HerosJourneyTemplate ->
                    { en = "Hero's Journey"
                    }

                HerosJourneyTemplateDesc ->
                    { en = "A framework for fictional stories"
                    }

                --
                RecentDocuments ->
                    { en = "Recent Documents"
                    }

                LastUpdated ->
                    { en = "Last Updated"
                    }

                LastOpened ->
                    { en = "Last Opened"
                    }

                OpenOtherDocuments ->
                    { en = "Open Other Documents"
                    }

                DeleteDocument ->
                    { en = "Delete Tree"
                    }

                RemoveFromList ->
                    { en = "Remove From List"
                    }

                NeverSaved ->
                    { en = "New Document..."
                    }

                Loading ->
                    { en = "Loading..."
                    }

                UnsavedChanges ->
                    { en = "Unsaved Changes..."
                    }

                SavedInternally ->
                    { en = "Saved Offline"
                    }

                ChangesSaved ->
                    { en = "Saved"
                    }

                ChangesSynced ->
                    { en = "Synced"
                    }

                DatabaseError ->
                    { en = "Database Error..."
                    }

                LastSaved ->
                    { en = "Last saved"
                    }

                LastSynced ->
                    { en = "Last synced"
                    }

                LastEdit ->
                    { en = "Last edit"
                    }

                ConfirmBannerStrong ->
                    { en = "Please confirm your email."
                    }

                ConfirmBannerBody ->
                    { en = "We've sent instructions to "
                    }

                Help ->
                    { en = "Help"
                    }

                WhatsNew ->
                    { en = "What's New"
                    }

                AccountTooltip ->
                    { en = "Account"
                    }

                -- Keyboard Shortcut Help
                KeyboardShortcuts ->
                    { en = "Keyboard Shortcuts"
                    }

                ViewModeShortcuts ->
                    { en = "View Mode Shortcuts : "
                    }

                CardEditCreateDelete ->
                    { en = "Card Edit, Create, Delete"
                    }

                NavigationMovingCards ->
                    { en = "Navigation, Moving Cards"
                    }

                CopyPaste ->
                    { en = "Copy/Paste"
                    }

                SearchingMerging ->
                    { en = "Searching, Merging Cards"
                    }

                HelpInfoDocs ->
                    { en = "Help, Info, Documents"
                    }

                EditModeShortcuts ->
                    { en = "Edit Mode Shortcuts : "
                    }

                CardSaveCreate ->
                    { en = "Card Save, Create"
                    }

                EditCard ->
                    { en = "Edit card"
                    }

                AddCardBelow ->
                    { en = "Add card below"
                    }

                AddCardAbove ->
                    { en = "Add card above"
                    }

                AddCardToRight ->
                    { en = "Add card to the right (as child)"
                    }

                AddCardBelowSplit ->
                    { en = "Add card below (split at cursor)"
                    }

                AddCardAboveSplit ->
                    { en = "Add card above (split at cursor)"
                    }

                AddCardToRightSplit ->
                    { en = "Add card to the right (split at cursor)"
                    }

                DeleteCard ->
                    { en = "Delete card (and its children)"
                    }

                GoUpDownLeftRight ->
                    { en = "Go up/down/left/right"
                    }

                GoToBeginningOfGroup ->
                    { en = "Go to beginning of group"
                    }

                GoToEndOfGroup ->
                    { en = "Go to end of group"
                    }

                GoToBeginningOfColumn ->
                    { en = "Go to beginning of column"
                    }

                GoToEndOfColumn ->
                    { en = "Go to end of column"
                    }

                MoveCurrentCard ->
                    { en = "Move current card (and children)"
                    }

                PageUp ->
                    { en = "PageUp"
                    }

                PageDown ->
                    { en = "PageDown"
                    }

                HomeKey ->
                    { en = "Home"
                    }

                EndKey ->
                    { en = "End"
                    }

                AnyOfAbove ->
                    { en = "(any of above)"
                    }

                DragCard ->
                    { en = "Drag card by left edge"
                    }

                Search ->
                    { en = "Search"
                    }

                ClearSearch ->
                    { en = "Clear search, focus current card"
                    }

                MergeCardUp ->
                    { en = "Merge card up"
                    }

                MergeCardDown ->
                    { en = "Merge card down"
                    }

                WorksAcrossDocuments ->
                    { en = "(Works across documents)"
                    }

                CopyCurrent ->
                    { en = "Copy current subtree"
                    }

                PasteBelow ->
                    { en = "Paste subtree below current card"
                    }

                PasteAsChild ->
                    { en = "Paste subtree as child of current card"
                    }

                InsertSelected ->
                    { en = "Insert selected text as new card"
                    }

                DragSelected ->
                    { en = "Drag selected text into tree"
                    }

                WordCounts ->
                    { en = "Word counts"
                    }

                SwitchDocuments ->
                    { en = "Switch to different document"
                    }

                ThisHelpScreen ->
                    { en = "This help screen"
                    }

                Or ->
                    { en = " or "
                    }

                EditCardFullscreen ->
                    { en = "Edit card in fullscreen mode"
                    }

                EditCards ->
                    { en = "Edit Cards"
                    }

                KeyboardHelp ->
                    { en = "Keyboard Shortcuts Help"
                    }

                RestoreThisVersion ->
                    { en = "Restore this Version"
                    }

                EnterKey ->
                    { en = "Enter"
                    }

                ShiftKey ->
                    { en = "Shift"
                    }

                EnterAction ->
                    { en = "to Edit"
                    }

                AltKey ->
                    { en = "AltKey"
                    }

                EditFullscreenAction ->
                    { en = "to Edit in Fullscreen"
                    }

                Navigate ->
                    { en = "Navigate"
                    }

                EditCardTitle ->
                    { en = "Edit Card (Enter)"
                    }

                ArrowsAction ->
                    { en = "to Navigate"
                    }

                AddNewCards ->
                    { en = "Add New Cards"
                    }

                AddChildAction ->
                    { en = "to Add Child"
                    }

                InsertChildTitle ->
                    { en = "Insert Child (Ctrl+L)"
                    }

                AddBelowAction ->
                    { en = "to Add Below"
                    }

                InsertBelowTitle ->
                    { en = "Insert Below (Ctrl+J)"
                    }

                AddAboveAction ->
                    { en = "to Add Above"
                    }

                SplitAtCursor ->
                    { en = "Split At Cursor"
                    }

                SplitChildAction ->
                    { en = "to Split Card to the Right"
                    }

                SplitBelowAction ->
                    { en = "to Split Card Down"
                    }

                SplitUpwardAction ->
                    { en = "to Split Card Upward"
                    }

                MergeCards ->
                    { en = "Merge Cards"
                    }

                MergeDownAction ->
                    { en = "to Merge into Next"
                    }

                MergeUpAction ->
                    { en = "to Merge into Previous"
                    }

                InsertAboveTitle ->
                    { en = "Insert Above (Ctrl+K)"
                    }

                ArrowKeys ->
                    { en = "(arrows)"
                    }

                MoveAndDelete ->
                    { en = "Move & Delete Cards"
                    }

                MoveAction ->
                    { en = "to Move"
                    }

                Backspace ->
                    { en = "Backspace"
                    }

                DeleteAction ->
                    { en = "to Delete"
                    }

                DeleteCardTitle ->
                    { en = "Delete Card (Ctrl+Backspace)"
                    }

                FormattingGuide ->
                    { en = "More Formatting Options..."
                    }

                ForBold ->
                    { en = "for Bold"
                    }

                BoldSelection ->
                    { en = "Bold selection"
                    }

                ForItalic ->
                    { en = "for Italic"
                    }

                ForInsertLink ->
                    { en = "to Insert Link"
                    }

                ItalicizeSelection ->
                    { en = "Italicize selection"
                    }

                InsertLink ->
                    { en = "Insert Link"
                    }

                SaveChanges ->
                    { en = "Save changes"
                    }

                SaveChangesAndExit ->
                    { en = "Save changes and exit card"
                    }

                ExitEditMode ->
                    { en = "Exit edit mode"
                    }

                ToSaveChanges ->
                    { en = "to Save Changes"
                    }

                SaveChangesTitle ->
                    { en = "Save Changes (Ctrl+Enter)"
                    }

                EscKey ->
                    { en = "Esc"
                    }

                OtherShortcuts ->
                    { en = "Other Shortcuts"
                    }

                DisplayWordCounts ->
                    { en = "Display word counts"
                    }

                EditMode ->
                    { en = "(Edit Mode)"
                    }

                SaveOrCancelChanges ->
                    { en = "Save/Cancel Changes"
                    }

                Formatting ->
                    { en = "Formatting"
                    }

                FormattingTitle ->
                    { en = "# Title\n## Subtitle"
                    }

                SetTitleLevel ->
                    { en = "Set title level (# to #####)"
                    }

                FormattingList ->
                    { en = "- List item\n  - Subitem"
                    }

                FormattingLink ->
                    { en = "[link](http://t.co)"
                    }

                ParenNumber ->
                    { en = "ParenNumber"
                    }

                SetHeadingLevel ->
                    { en = "SetHeadingLevel"
                    }

                HelpVideos ->
                    { en = "Help Videos"
                    }

                FAQAndDocs ->
                    { en = "FAQ & Documentation"
                    }

                --
                AreYouSureCancel ->
                    { en = "Are you sure you want to undo your changes?"
                    }

                ToCancelChanges ->
                    { en = "to Cancel Changes"
                    }

                PressToSearch ->
                    { en = "Press '/' to search"
                    }

                QuickDocumentSwitcher ->
                    { en = "Quick Document Switcher"
                    }

                OpenQuickSwitcher ->
                    { en = "Open Quick Switcher"
                    }

                ContactSupport ->
                    { en = "Contact Support"
                    }

                Logout ->
                    { en = "Logout"
                    }

                ContributeTranslations ->
                    { en = "Contribute translations"
                    }

                Here ->
                    { en = "here"
                    }

                HeadingFont ->
                    { en = "Heading Font"
                    }

                ContentFont ->
                    { en = "Content Font"
                    }

                EditingFont ->
                    { en = "Editing/Monospace Font"
                    }

                MigrateTooltip ->
                    { en = "Upgrade document to new format"
                    }

                VersionHistory ->
                    { en = "Version History"
                    }

                DocumentSettings ->
                    { en = "Document Settings"
                    }

                WordCount ->
                    { en = "Word count..."
                    }

                WordCountSession n ->
                    { en = numberPlural n "Session : %1 word" "Session : %1 words"
                    }

                WordCountTotal n ->
                    { en = numberPlural n "Total : %1 word" "Total : %1 words"
                    }

                WordCountCard n ->
                    { en = numberPlural n "Card : %1 word" "Card : %1 words"
                    }

                WordCountSubtree n ->
                    { en = numberPlural n "Subtree : %1 word" "Subtree : %1 words"
                    }

                WordCountGroup n ->
                    { en = numberPlural n "Group : %1 word" "Group : %1 words"
                    }

                WordCountColumn n ->
                    { en = numberPlural n "Column : %1 word" "Column : %1 words"
                    }

                CharacterCountCard n ->
                    { en = numberPlural n "Card : %1 character" "Card : %1 characters"
                    }

                CharacterCountSubtree n ->
                    { en = numberPlural n "Subtree : %1 character" "Subtree : %1 characters"
                    }

                CharacterCountGroup n ->
                    { en = numberPlural n "Group : %1 character" "Group : %1 characters"
                    }

                CharacterCountColumn n ->
                    { en = numberPlural n "Column : %1 character" "Column : %1 characters"
                    }

                CharacterCountTotal n ->
                    { en = numberPlural n "Total : %1 character" "Total : %1 characters"
                    }

                WordCountTotalCards n ->
                    { en = numberPlural n "Total Cards in Tree : %1" "Total Cards in Tree : %1"
                    }

                DocumentTheme ->
                    { en = "Document Theme"
                    }

                ThemeDefault ->
                    { en = "Default"
                    }

                ThemeDarkMode ->
                    { en = "Dark Mode"
                    }

                ThemeClassic ->
                    { en = "Classic Gingkoapp"
                    }

                ThemeGray ->
                    { en = "Gray"
                    }

                ThemeGreen ->
                    { en = "Green"
                    }

                ThemeTurquoise ->
                    { en = "Turquoise"
                    }

                -- Exporting
                ExportOrPrint ->
                    { en = "Export or Print"
                    }

                ExportSettingEverything ->
                    { en = "Everything"
                    }

                ExportSettingEverythingDesc ->
                    { en = "All cards in the tree (in depth-first order)"
                    }

                ExportSettingCurrentSubtree ->
                    { en = "Current Subtree"
                    }

                ExportSettingCurrentSubtreeDesc ->
                    { en = "Current card and all its children"
                    }

                ExportSettingLeavesOnly ->
                    { en = "Leaves-only"
                    }

                ExportSettingLeavesOnlyDesc ->
                    { en = "Only cards without children"
                    }

                ExportSettingCurrentColumn ->
                    { en = "Current Column"
                    }

                ExportSettingCurrentColumnDesc ->
                    { en = "Only cards in the current (vertical) column"
                    }

                ExportSettingWord ->
                    { en = "Word"
                    }

                ExportSettingPlainText ->
                    { en = "Plain Text"
                    }

                ExportSettingJSON ->
                    { en = "JSON"
                    }

                ExportSettingOPML ->
                    { en = "OPML"
                    }

                CloseExportView ->
                    { en = "Close Export View"
                    }

                DownloadWordFile ->
                    { en = "Download Word File"
                    }

                DownloadTextFile ->
                    { en = "Download Markdown text file"
                    }

                DownloadJSONFile ->
                    { en = "Download JSON file"
                    }

                DownloadOPMLFile ->
                    { en = "Download OPML file"
                    }

                PrintThis ->
                    { en = "Print this"
                    }

                -- Upgrade & Subscription
                Upgrade ->
                    { en = "Upgrade"
                    }

                DaysLeft n ->
                    { en = numberPlural n "%1 day left in trial" "%1 days left in trial"
                    }

                TrialExpired ->
                    { en = "Trial Expired"
                    }

                WordOfMouthCTA1 ->
                    { en = "Love Gingko Writer?"
                    }

                WordOfMouthCTA2 ->
                    { en = "Leave a Testimonial"
                    }

                ManageSubscription ->
                    { en = "Manage Subscription"
                    }
    in
    -- Self-host: English only. The other 25 languages were ~5,400 lines of
    -- string literals compiled into elm.js and reachable from nothing.
    .en translationSet


timeDistInWords : Time.Posix -> Time.Posix -> String
timeDistInWords t1 t2 =
    TimeDistance.inWordsWithConfig { withAffix = True } I18n.en t1 t2
