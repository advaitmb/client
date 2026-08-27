module Translation exposing (TranslationId(..), tr)

{-| The strings the Elm views still render.

Every constructor here has a caller. The interface layer (`src/ui/`) owns the
modals, the sidebar, the header and the save indicator, and each of those
carries its own English strings in TypeScript -- so the help, template,
word-count, theme, export-settings and account sections of this type went with
the views that used to read them.

-}


type TranslationId
    = NoTr String
    | DeleteDocument
    | Loading
    | ConfirmBannerStrong
    | ConfirmBannerBody
      -- Keyboard Shortcut Help
    | KeyboardShortcuts
    | DeleteCard
    | EditCards
    | EnterKey
    | ShiftKey
    | EnterAction
    | AltKey
    | EditFullscreenAction
    | Navigate
    | ArrowsAction
    | AddNewCards
    | AddChildAction
    | AddBelowAction
    | AddAboveAction
    | SplitAtCursor
    | SplitChildAction
    | SplitBelowAction
    | SplitUpwardAction
    | MergeCards
    | MergeDownAction
    | MergeUpAction
    | ArrowKeys
    | MoveAndDelete
    | MoveAction
    | Backspace
    | DeleteAction
    | FormattingGuide
    | ForBold
    | ForItalic
    | ForInsertLink
    | ToSaveChanges
    | EscKey
    | OtherShortcuts
    | DisplayWordCounts
    | EditMode
    | SaveOrCancelChanges
    | Formatting
    | FormattingTitle
    | FormattingList
    | FormattingLink
    | ParenNumber
    | SetHeadingLevel
      -- Edit-mode prompts and the search hint
    | AreYouSureCancel
    | ToCancelChanges
    | PressToSearch
    | QuickDocumentSwitcher
      -- Exporting
    | DownloadWordFile
    | DownloadTextFile
    | DownloadJSONFile
    | DownloadOPMLFile
    | PrintThis


tr : TranslationId -> String
tr trans =
    let
        translationSet =
            case trans of
                NoTr str ->
                    { en = str
                    }

                DeleteDocument ->
                    { en = "Delete Tree"
                    }

                Loading ->
                    { en = "Loading..."
                    }

                ConfirmBannerStrong ->
                    { en = "Please confirm your email."
                    }

                ConfirmBannerBody ->
                    { en = "We've sent instructions to "
                    }

                -- Keyboard Shortcut Help
                KeyboardShortcuts ->
                    { en = "Keyboard Shortcuts"
                    }

                DeleteCard ->
                    { en = "Delete card (and its children)"
                    }

                EditCards ->
                    { en = "Edit Cards"
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
                    { en = "Alt"
                    }

                EditFullscreenAction ->
                    { en = "to Edit in Fullscreen"
                    }

                Navigate ->
                    { en = "Navigate"
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

                AddBelowAction ->
                    { en = "to Add Below"
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

                FormattingGuide ->
                    { en = "More Formatting Options..."
                    }

                ForBold ->
                    { en = "for Bold"
                    }

                ForItalic ->
                    { en = "for Italic"
                    }

                ForInsertLink ->
                    { en = "to Insert Link"
                    }

                ToSaveChanges ->
                    { en = "to Save Changes"
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

                FormattingList ->
                    { en = "- List item\n  - Subitem"
                    }

                FormattingLink ->
                    { en = "[link](http://t.co)"
                    }

                ParenNumber ->
                    { en = "(1-6)"
                    }

                SetHeadingLevel ->
                    { en = "to Set Title Level"
                    }

                -- Edit-mode prompts and the search hint
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

                -- Exporting
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
    in
    -- Self-host: English only. The other 25 languages were ~5,400 lines of
    -- string literals compiled into elm.js and reachable from nothing.
    .en translationSet
