module WordcountTest exposing (documentWordcountMatchesTheModal, sessionStart)

{-| Tests at the ADR-0001 seam 10: what the word-count modal's "Session" row
counts.

The modal is rendered by `src/ui/wordcount-modal.ts` from the JSON
`Doc.UI.encodeStats` builds, and its session row is
`documentWords - startingWordcount`. Nothing ever recorded a starting count --
`Page.App` passed the literal `0` -- so "Session" was a second copy of "Total"
(E11).

A session starts when a document's content arrives, so the count is recorded
by `Page.Doc` and read back with `getStartingWordcount`. `Page.Doc.update`
itself is untestable (it answers in `Cmd`s no test can inspect), but the
document state these functions carry is plain data.

-}

import Doc.TreeStructure as TreeStructure
import Doc.UI as UI
import Expect
import GlobalData
import Json.Decode as Dec
import Page.Doc
import Test exposing (Test, describe, test)
import Types exposing (Children(..), Tree)


{-| A document as it comes back from storage: eight words across two cards.
-}
loadedTree : Tree
loadedTree =
    Tree "0"
        ""
        (Children
            [ Tree "1" "Four words in here" (Children [])
            , Tree "2" "and four words here" (Children [])
            ]
        )


{-| The same document after four more words are written into a third card.
-}
grownTree : Tree
grownTree =
    Tree "0"
        ""
        (Children
            [ Tree "1" "Four words in here" (Children [])
            , Tree "2" "and four words here" (Children [])
            , Tree "3" "written this session too" (Children [])
            ]
        )


workingTree : Tree -> TreeStructure.Model
workingTree tree =
    TreeStructure.setTree tree TreeStructure.defaultModel


{-| A document opened from storage, whose content has arrived.
-}
opened : Tree -> Page.Doc.Model
opened tree =
    Page.Doc.init False GlobalData.public
        |> Page.Doc.setWorkingTree (workingTree tree)


{-| One row of the modal, read back out of the JSON the element is given --
which is how `Page.App` renders it: the stats of this document model.
-}
modalRow : String -> Page.Doc.Model -> Int
modalRow row docModel =
    UI.encodeStats
        { activeCardId = "1"
        , workingTree = Page.Doc.getWorkingTree docModel
        , startingWordcount = Page.Doc.getStartingWordcount docModel
        }
        |> Dec.decodeValue (Dec.field row Dec.int)
        |> Result.withDefault -1


sessionStart : Test
sessionStart =
    describe "The word count a writing session starts from"
        [ test "is the document's own count, once its content has arrived" <|
            \_ ->
                opened loadedTree
                    |> Page.Doc.getStartingWordcount
                    |> Expect.equal 8
        , test "leaves the session row at nothing for a document just opened" <|
            \_ ->
                opened loadedTree
                    |> modalRow "sessionWords"
                    |> Expect.equal 0
        , test "does not move when more is written" <|
            \_ ->
                opened loadedTree
                    |> Page.Doc.setWorkingTree (workingTree grownTree)
                    |> Page.Doc.getStartingWordcount
                    |> Expect.equal 8
        , test "counts only what was written since, in the session row" <|
            \_ ->
                opened loadedTree
                    |> Page.Doc.setWorkingTree (workingTree grownTree)
                    |> modalRow "sessionWords"
                    |> Expect.equal 4
        , test "still reports the whole document as the total" <|
            \_ ->
                opened loadedTree
                    |> Page.Doc.setWorkingTree (workingTree grownTree)
                    |> modalRow "documentWords"
                    |> Expect.equal 12
        , test "is nothing for a document being created: every word is this session's" <|
            \_ ->
                Page.Doc.init True GlobalData.public
                    |> Page.Doc.setWorkingTree (workingTree loadedTree)
                    |> Page.Doc.getStartingWordcount
                    |> Expect.equal 0
        , test "is the public document's count too" <|
            \_ ->
                Page.Doc.init False GlobalData.public
                    |> Page.Doc.publicTreeLoaded loadedTree
                    |> Page.Doc.getStartingWordcount
                    |> Expect.equal 8
        ]


documentWordcountMatchesTheModal : Test
documentWordcountMatchesTheModal =
    describe "The count a session starts from"
        [ test "is the same number the modal shows as the total" <|
            \_ ->
                UI.documentWordcount (workingTree grownTree)
                    |> Expect.equal (modalRow "documentWords" (opened grownTree))
        , test "counts nothing in an empty document" <|
            \_ ->
                UI.documentWordcount TreeStructure.defaultModel
                    |> Expect.equal 0
        ]
