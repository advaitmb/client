module SharedUI exposing (ctrlOrCmdText, unsavedChangesAlert)


ctrlOrCmdText : Bool -> String
ctrlOrCmdText isMac =
    if isMac then
        "⌘"

    else
        "Ctrl"


{-| Shown when something would throw away an edit that only exists in the
model: navigating away (Main.handleUrlChange) and logging out
(Page.App.LogoutRequested) both refuse while the document is dirty.
-}
unsavedChangesAlert : Bool -> String
unsavedChangesAlert isMac =
    "You have unsaved changes!\n" ++ ctrlOrCmdText isMac ++ "+enter to save."
