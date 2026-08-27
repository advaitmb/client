module Page.DocMessage exposing (..)

import Ant.Icons.Svg as AntIcons
import Html exposing (Html, br, button, div, h1, p, text)
import Html.Attributes exposing (id, type_)
import Html.Events exposing (onClick)



-- VIEW


{-| The screen for an account with no documents yet.

There used to be an `<img src="" onerror>` here, whose broken-image event fired
an `EmptyMessage` msg — a way of getting a callback out of Elm's view when this
screen appeared. Nothing was listening: it reached `Outgoing.EmptyMessageShown`,
whose `doc.js` handler was `() => {}`. Both are gone (S12). If this screen ever
does need to announce itself, `Page.App` knows it is in the `Empty` state and
can say so from `update`, where a command belongs — a view has no business
sending one, and a load error is a strange thing to hang it on.

-}
viewEmpty : { newClicked : msg } -> List (Html msg)
viewEmpty msgs =
    [ div [ id "document-header" ] []
    , div [ id "empty-message" ]
        [ h1 [] [ text "You don't have any documents" ]
        , p [] [ text "Click to create one:" ]
        , br [] []
        , button
            [ id "new-button"
            , type_ "button"
            , onClick msgs.newClicked
            ]
            [ AntIcons.fileAddOutlined [] ]
        ]
    ]


viewNotFound : List (Html msg)
viewNotFound =
    [ div [ id "document-header" ] []
    , div [ id "doc-error-message" ]
        [ h1 [] [ text "Hmm, we couldn't find this document" ]
        , p [] [ text "The file might have been moved, or deleted." ]
        , br [] []
        , p [] [ text "Check your list of documents in the sidebar." ]
        ]
    ]
