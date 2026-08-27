module TranslationTest exposing (editModeTrayStrings)

{-| Tests at the ADR-0001 seam 9: the strings the shortcut tray renders.

`Doc.UI.viewShortcutsToggle` builds each tray row out of `TranslationId`s --
the key names, in `span.shortcut-key`, then the action they perform -- and
hands every one of them to `Translation.tr`. Three entries were placeholders
still holding their own constructor names, so the edit-mode tray's Formatting
row read "Alt (1-6)" as "AltKey ParenNumber SetHeadingLevel" on screen (E14).
The TS help modal had already been given real strings for the same three keys
(`src/ui/help-modal.ts`); this is the tray's side of that.

Nothing else pins these: the tray is a view, and a placeholder string renders
as happily as a real one.

-}

import Expect
import Test exposing (Test, describe, test)
import Translation exposing (TranslationId(..), tr)


editModeTrayStrings : Test
editModeTrayStrings =
    describe "The edit-mode shortcut tray's Formatting row"
        [ test "names the Alt key" <|
            \_ ->
                tr AltKey
                    |> Expect.equal "Alt"
        , test "names the digits that set a title level" <|
            \_ ->
                tr ParenNumber
                    |> Expect.equal "(1-6)"
        , test "says what Alt and a digit do, in the tray's voice" <|
            \_ ->
                tr SetHeadingLevel
                    |> Expect.equal "to Set Title Level"
        , test "renders no entry as its own constructor name" <|
            \_ ->
                [ ( AltKey, "AltKey" )
                , ( ParenNumber, "ParenNumber" )
                , ( SetHeadingLevel, "SetHeadingLevel" )
                ]
                    |> List.filter (\( id, constructorName ) -> tr id == constructorName)
                    |> List.map Tuple.second
                    |> Expect.equal []
        ]
