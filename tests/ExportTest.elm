module ExportTest exposing (leavesAndColumnKeepTheirFormat, oneMimeTypePerFormat)

{-| Tests at the ADR-0001 seam 9: what an export writes, and what it is saved
as.

`Page.Doc.Export.toString` is a pure function of (document name, selection,
format, active card, whole tree). Two of its four selections -- "leaves" and
"current column" -- special-cased JSON and then let every other format fall
through to a plain-text join, so choosing OPML for them wrote Markdown into a
file named `.opml` (E13). The same export was handed to the browser with the
MIME string "application/xml, text/xml, text/x-opml", which is a list, not a
type.

-}

import Expect
import Page.Doc.Export as Export exposing (ExportFormat(..), ExportSelection(..))
import Test exposing (Test, describe, test)
import Types exposing (Children(..), Tree)


{-| A tree with two columns: the root's two children, one of which has children
of its own. The leaves are therefore "Aardvark", "Beetle" and "Cricket" -- and
the column of "Beetle" holds cards that do have children, which is what makes
the column selection more than a second name for the leaves.

    (root)
      |- Aardvark
      |- Beetle
           |- Beetle's first
           |- Cricket

-}
tree : Tree
tree =
    Tree "0"
        ""
        (Children
            [ Tree "1" "Aardvark" (Children [])
            , Tree "2"
                "Beetle"
                (Children
                    [ Tree "3" "Beetle's first" (Children [])
                    , Tree "4" "Cricket" (Children [])
                    ]
                )
            ]
        )


exported : ExportSelection -> ExportFormat -> String
exported selection format =
    Export.toString "My Document" ( selection, format ) beetle tree


{-| The active card, for the selections that are relative to one.
-}
beetle : Tree
beetle =
    Tree "2"
        "Beetle"
        (Children
            [ Tree "3" "Beetle's first" (Children [])
            , Tree "4" "Cricket" (Children [])
            ]
        )


{-| The three things every OPML document the app writes has, per the OPML 2.0
spec: the XML declaration, the versioned root element, and a body that closes
it.
-}
expectOpmlDocument : String -> Expect.Expectation
expectOpmlDocument out =
    Expect.all
        [ \s -> String.startsWith "<?xml version=\"1.0\" encoding=\"utf-8\"?>" s |> Expect.equal True |> Expect.onFail ("no XML declaration:\n" ++ s)
        , \s -> String.contains "<opml version=\"2.0\">" s |> Expect.equal True |> Expect.onFail ("no opml element:\n" ++ s)
        , \s -> String.contains "<head><title>My Document</title></head>" s |> Expect.equal True |> Expect.onFail ("no head:\n" ++ s)
        , \s -> String.endsWith "</body></opml>" s |> Expect.equal True |> Expect.onFail ("body left open:\n" ++ s)
        ]
        out


{-| Each card of the selection, as its own outline element.
-}
expectOutlines : List String -> String -> Expect.Expectation
expectOutlines contents out =
    contents
        |> List.filter (\c -> not (String.contains ("<outline text=\"" ++ c ++ "\">") out))
        |> Expect.equalLists []


leavesAndColumnKeepTheirFormat : Test
leavesAndColumnKeepTheirFormat =
    describe "Exporting a selection of cards"
        [ describe "as OPML"
            [ test "writes an OPML document for the leaves" <|
                \_ ->
                    exported ExportLeaves OPML |> expectOpmlDocument
            , test "writes one outline per leaf" <|
                \_ ->
                    exported ExportLeaves OPML
                        |> expectOutlines [ "Aardvark", "Beetle&apos;s first", "Cricket" ]
            , test "writes an OPML document for the current column" <|
                \_ ->
                    exported ExportCurrentColumn OPML |> expectOpmlDocument
            , test "writes one outline per card in the column" <|
                \_ ->
                    exported ExportCurrentColumn OPML
                        |> expectOutlines [ "Aardvark", "Beetle" ]
            , test "writes an OPML document for the whole tree, as it always did" <|
                \_ ->
                    exported ExportEverything OPML |> expectOpmlDocument
            ]
        , describe "as plain text"
            [ test "joins the leaves' contents" <|
                \_ ->
                    exported ExportLeaves PlainText
                        |> Expect.equal "Aardvark\n\nBeetle's first\n\nCricket"
            , test "joins the column's contents" <|
                \_ ->
                    exported ExportCurrentColumn PlainText
                        |> Expect.equal "Aardvark\n\nBeetle"
            ]
        , describe "as JSON"
            [ test "lists the leaves" <|
                \_ ->
                    exported ExportLeaves JSON
                        |> String.contains "\"content\": \"Cricket\""
                        |> Expect.equal True
            , test "lists the column" <|
                \_ ->
                    exported ExportCurrentColumn JSON
                        |> String.contains "\"content\": \"Beetle\""
                        |> Expect.equal True
            , test "gives the column's cards no children: a column is flat" <|
                \_ ->
                    exported ExportCurrentColumn JSON
                        |> String.contains "Beetle's first"
                        |> Expect.equal False
            ]
        ]


oneMimeTypePerFormat : Test
oneMimeTypePerFormat =
    describe "The MIME type a downloaded export is saved as"
        [ test "is a single type, not a list of candidates" <|
            \_ ->
                [ PlainText, JSON, OPML, DOCX ]
                    |> List.map Export.toMimeType
                    |> List.filter (\m -> String.contains "," m || String.contains " " m)
                    |> Expect.equalLists []
        , test "is a type/subtype pair for every format" <|
            \_ ->
                [ PlainText, JSON, OPML, DOCX ]
                    |> List.map Export.toMimeType
                    |> List.filter (\m -> List.length (String.split "/" m) /= 2)
                    |> Expect.equalLists []
        ]
