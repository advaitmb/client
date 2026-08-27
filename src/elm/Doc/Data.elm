module Doc.Data exposing (CardOp_tests_only(..), Card_tests_only, Delta_tests_only, Model, SaveError_tests_only(..), cardDataReceived, cardOpConvert, conflictList, conflictToTree, emptyCardBased, getHistoryList, hasConflicts, historyReceived, importTree, lastSavedTime, lastSyncedTime, localSave, model_tests_only, publicDataDecoder, pushOkHandler, resolve, resolveConflicts, restore, saveErrors_tests_only, toDelta_tests_only, toSave_tests_only, triggeredPush)

import Coders exposing (treeToValue, tupleDecoder)
import Dict exposing (Dict)
import Doc.Data.Conflict as Conf exposing (Conflict, Op(..), Selection(..), conflictWithSha, opString)
import Doc.TreeStructure exposing (apply, opToMsg)
import Http exposing (Error(..))
import Json.Decode as Dec
import Json.Encode as Enc
import List.Extra as ListExtra
import Maybe exposing (andThen)
import Outgoing exposing (Msg(..))
import RemoteData exposing (WebData)
import Result.Extra
import Time
import Types exposing (CardTreeOp(..), Children(..), ConflictSelection(..), Tree)
import UpdatedAt exposing (UpdatedAt)
import Utils exposing (hash)



-- MODEL


historyLimit =
    1


type Model
    = CardBased CardData StagedRows (List ( String, Time.Posix, WebData CardData )) (Maybe CardDataConflicts)


type alias Card t =
    { id : String
    , treeId : String
    , content : String
    , parentId : Maybe String
    , position : Float
    , deleted : Bool
    , synced : Bool
    , updatedAt : t
    }


type alias CardData =
    List (Card UpdatedAt)


{-| Rows handed to the port layer whose stamps the DB has not issued yet.

They are the model's only knowledge of the saves it has made since the last
Dexie liveQuery emission, and every save built from a card that already exists
reads them first: where the next card goes (`placeCard`), and what state an
update, a move, a deletion or a merge carries over (`stagedOrNewestRow`,
`visibleWithStaged`). Read the version log alone and the second save inside one
round trip writes back the state the first one had just changed -- reverting a
move, an edit or a re-parenting (CODE_REVIEW.md D8, ticket 29).

They are not themselves part of the version log: they carry no version stamp,
so they must not be pushed, and they cannot classify a card as synced or
unsynced.

-}
type alias StagedRows =
    List (Card ())


type alias CardDataConflicts =
    { ours : CardData
    , theirs : CardData
    , original : CardData
    }


emptyCardBased : Model
emptyCardBased =
    CardBased [] [] [] Nothing


hasConflicts : Model -> Bool
hasConflicts model =
    case model of
        CardBased _ _ _ (Just _) ->
            True

        _ ->
            False


conflictList : Model -> List Conflict
conflictList model =
    case model of
        CardBased _ _ _ _ ->
            []


restore : String -> Model -> String -> List Outgoing.Msg
restore treeId model historyId =
    case model of
        CardBased currentData _ history _ ->
            let
                dataAtRestorePoint_ =
                    history
                        |> List.filter (\( id, _, _ ) -> id == historyId)
                        |> List.head
                        |> Maybe.map (\( _, _, wd ) -> wd)
                        |> Maybe.andThen RemoteData.toMaybe
            in
            case dataAtRestorePoint_ of
                Just dataAtRestorePoint ->
                    let
                        changes =
                            getRestoredData currentData dataAtRestorePoint

                        -- Restoring the state the document is already in has
                        -- nothing to write, and an empty save is not free: the
                        -- port layer stamps the tree row unsynced for every
                        -- save it is handed.  `Page.App`'s Restore branch
                        -- already closes the history view on an empty message
                        -- list.
                        changesSomething =
                            not
                                (List.isEmpty changes.toAdd
                                    && List.isEmpty changes.toMarkSynced
                                    && List.isEmpty changes.toMarkDeleted
                                    && List.isEmpty changes.toRemove
                                )
                    in
                    if changesSomething then
                        [ SaveCardBased (toSave treeId changes) ]

                    else
                        []

                _ ->
                    []


{-| The save that turns the current card set into the one a snapshot holds.

Both sides are reduced to the newest row per card id first (ADR-0005 §1): the
version log keeps the rows a card has outgrown, and a restore is a statement
about the card the user sees, not about its history.

-}
getRestoredData : CardData -> CardData -> DBChangeLists
getRestoredData currentData restoredData =
    let
        byCardId cards =
            cards
                |> newestPerId
                |> List.map (\c -> ( c.id, c ))
                |> Dict.fromList

        ( toAdd, toMarkDeleted ) =
            mergeRestoreData (byCardId currentData) (byCardId restoredData)
    in
    { toAdd = toAdd
    , toMarkSynced = []
    , toMarkDeleted = toMarkDeleted
    , toRemove = []
    }


{-| The rows a restore has to write: the snapshot's version of every card whose
state differs from it, plus a deletion row for every living card the snapshot
does not have.

Only cards whose state actually changes get a row. What is compared is card
*state* -- every field a delta can carry -- and not the version stamp: two rows
can differ by stamp and say the same thing (the server bumps a card's stamp for
an op-less delta), and staging content the card already has just adds an
unsynced row with nothing to push.

-}
mergeRestoreData : Dict String (Card UpdatedAt) -> Dict String (Card UpdatedAt) -> ( List (Card ()), List (Card ()) )
mergeRestoreData currentDataByCardId restoredDataByCardId =
    let
        -- A snapshot holds only living cards, so a card missing from one was
        -- either added after it was taken -- delete it -- or already deleted
        -- when it was taken, in which case it is already in the state the
        -- snapshot describes.  Re-deleting those appended a fresh unsynced
        -- deletion row per ever-deleted card on every restore (CODE_REVIEW.md
        -- D9).
        onlyInCurrent =
            \_ currentCard ( toAddSoFar, toDeleteSoFar ) ->
                if currentCard.deleted then
                    ( toAddSoFar
                    , toDeleteSoFar
                    )

                else
                    ( toAddSoFar
                    , toDeleteSoFar ++ [ { currentCard | deleted = True } |> asUnsynced ]
                    )

        -- In the snapshot, but with no row at all in the version log: write it
        -- back as a new card.
        onlyInRestored =
            \_ restoredCard ( toAddSoFar, toDeleteSoFar ) ->
                ( toAddSoFar ++ [ restoredCard |> asUnsynced ]
                , toDeleteSoFar
                )

        inBoth =
            \_ currentCard restoredCard ( toAddSoFar, toDeleteSoFar ) ->
                if sameCardState currentCard restoredCard then
                    ( toAddSoFar
                    , toDeleteSoFar
                    )

                else
                    ( toAddSoFar ++ [ restoredCard |> asUnsynced ]
                    , toDeleteSoFar
                    )
    in
    Dict.merge
        onlyInCurrent
        inBoth
        onlyInRestored
        currentDataByCardId
        restoredDataByCardId
        ( [], [] )


{-| Whether two version rows say the same thing about their card: every field a
delta can carry, which is every field except the version stamp and whether the
row has been pushed.
-}
sameCardState : Card a -> Card b -> Bool
sameCardState left right =
    (left.content == right.content)
        && (left.parentId == right.parentId)
        && (left.position == right.position)
        && (left.deleted == right.deleted)


lastSavedTime : Model -> Maybe Int
lastSavedTime model =
    case model of
        CardBased data _ _ _ ->
            let
                shouldFilterEmpty =
                    List.length data /= 1
            in
            data
                |> (if shouldFilterEmpty then
                        List.filter (not << String.isEmpty << .content)

                    else
                        identity
                   )
                |> List.map .updatedAt
                |> UpdatedAt.sortNewestFirst identity
                |> List.head
                |> Maybe.map UpdatedAt.getTimestamp

lastSyncedTime : Model -> Maybe Int
lastSyncedTime model =
    case model of
        CardBased data _ _ _ ->
            data
                |> List.filter .synced
                |> List.map .updatedAt
                |> UpdatedAt.sortNewestFirst identity
                |> List.head
                |> Maybe.map UpdatedAt.getTimestamp

parseUpdatedAt : String -> Maybe Int
parseUpdatedAt str =
    String.split ":" str
        |> List.head
        |> Maybe.andThen String.toInt


cardDataReceived : Dec.Value -> ( Model, Tree, String ) -> Maybe { newData : Model, newTree : Tree, outMsg : List Outgoing.Msg }
cardDataReceived json ( oldModel, oldTree, treeId ) =
    case Dec.decodeValue decodeCards json of
        Ok cards ->
            let
                newModelWithoutConflicts =
                    case oldModel of
                        CardBased oldData oldStaged oldHistory oldConflicts_ ->
                            let
                                stillStaged =
                                    unwrittenStaged cards oldStaged
                            in
                            if cards /= oldData || stillStaged /= oldStaged then
                                CardBased cards stillStaged oldHistory oldConflicts_

                            else
                                oldModel

                newTree =
                    cards
                        |> toTree

                syncState =
                    getSyncState cards

                ( outMsg, conflicts_ ) =
                    case syncState of
                        Unsynced ->
                            ( pushDeltas treeId cards
                            , Nothing
                            )

                        CanFastForward ffids ->
                            ( [ SaveCardBased (toSave treeId { toAdd = [], toMarkSynced = [], toMarkDeleted = [], toRemove = ffids |> UpdatedAt.unique }) ]
                            , Nothing
                            )

                        Conflicted conflictData ->
                            let
                                mergedChanges =
                                    resolveDeleteConflicts cards conflictData

                                -- Delete-vs-edit conflicts resolve without
                                -- asking (edits win), and staging a change is
                                -- how `resolveDeleteConflicts` says it handled
                                -- one.  Only `toRemove` can be non-empty
                                -- today, but the gate asks the general
                                -- question so a future limb can't fall
                                -- through it silently.
                                mergeHandledIt =
                                    not
                                        (List.isEmpty mergedChanges.toAdd
                                            && List.isEmpty mergedChanges.toMarkSynced
                                            && List.isEmpty mergedChanges.toMarkDeleted
                                            && List.isEmpty mergedChanges.toRemove
                                        )
                            in
                            if mergeHandledIt then
                                ( [ SaveCardBased (toSave treeId mergedChanges) ]
                                , Nothing
                                )

                            else
                                ( [], Just { ours = conflictData.ours, theirs = conflictData.theirs, original = conflictData.original } )

                        _ ->
                            ( [], Nothing )

                newModel =
                    case newModelWithoutConflicts of
                        CardBased data staged history _ ->
                            CardBased data staged history conflicts_

            in
            if (newModel /= oldModel) || (newTree /= oldTree) then
                Just { newData = newModel, newTree = newTree, outMsg = outMsg }

            else
                Nothing

        Err err ->
            Nothing


triggeredPush : Model -> String -> List Outgoing.Msg
triggeredPush model treeId =
    case model of
        CardBased cards _ _ _ ->
            let
                syncState =
                    getSyncState cards
            in
            case syncState of
                Unsynced ->
                    pushDeltas treeId cards

                _ ->
                    []


{-| Apply the user's choice of conflicting version, by rewriting the version log
of the conflicted cards.

Resolving discards the whole local unsynced line, not just its newest row
(ADR-0005 §2). Offline editing appends one unsynced row per save, so leaving
the older rows behind would re-classify the card as `Unsynced` and push content
the user explicitly discarded (CODE_REVIEW.md D3).

Every choice also drops the original (the oldest synced row): that brings the
card's synced count back under `historyLimit`, which is what takes it out of the
`Conflicted` state.

-}
resolveConflicts : String -> ConflictSelection -> Model -> Maybe Outgoing.Msg
resolveConflicts treeId selectedVersion model =
    case model of
        CardBased allCards _ _ (Just versions) ->
            let
                conflictedIds =
                    (versions.original ++ versions.ours ++ versions.theirs)
                        |> List.map .id
                        |> ListExtra.unique

                -- Confined to the conflicted cards: unsynced rows of other
                -- cards are unrelated local work still waiting to be pushed.
                ourUnsyncedStamps =
                    allCards
                        |> List.filter (\c -> not c.synced && List.member c.id conflictedIds)
                        |> List.map .updatedAt

                originalStamps =
                    versions.original |> List.map .updatedAt

                -- `versions.ours` is the newest unsynced row of each
                -- conflicted card: the row picking Ours keeps.
                ourWinningStamps =
                    versions.ours |> List.map .updatedAt

                ( toAdd, toRemove ) =
                    case selectedVersion of
                        Types.Original ->
                            -- Their version is already on the server, so
                            -- reverting means pushing the original content
                            -- back up as a fresh unsynced row.
                            ( versions.original |> List.map asUnsynced
                            , originalStamps ++ ourUnsyncedStamps
                            )

                        Types.Theirs ->
                            ( []
                            , originalStamps ++ ourUnsyncedStamps
                            )

                        Types.Ours ->
                            ( []
                            , originalStamps
                                ++ (ourUnsyncedStamps
                                        |> List.filter
                                            (\stamp -> not (List.any (UpdatedAt.areEqual stamp) ourWinningStamps))
                                   )
                            )
            in
            SaveCardBased (toSave treeId { toAdd = toAdd, toMarkSynced = [], toMarkDeleted = [], toRemove = toRemove |> UpdatedAt.unique }) |> Just

        _ ->
            Nothing


conflictToTree : Model -> ConflictSelection -> Maybe Tree
conflictToTree data selection =
    case data of
        CardBased allCards _ _ (Just cd) ->
            let
                toDict : CardData -> Dict String (Card UpdatedAt)
                toDict d =
                    -- Newest row per id, so the tree does not depend on the
                    -- order the rows came out of Dexie (ADR-0005 §1).
                    d |> newestPerId |> List.map (\c -> ( c.id, c )) |> Dict.fromList

                combine : CardData -> CardData
                combine conf =
                    Dict.union (toDict conf) (toDict allCards)
                        |> Dict.toList
                        |> List.map Tuple.second
            in
            case selection of
                Types.Ours ->
                    combine cd.ours |> toTree |> Just

                Types.Theirs ->
                    combine cd.theirs |> toTree |> Just

                Types.Original ->
                    combine cd.original |> toTree |> Just

        _ ->
            Nothing


resolve : String -> Model -> Model
resolve cid model =
    case model of
        CardBased _ _ _ _ ->
            model

decodeCards : Dec.Decoder (List (Card UpdatedAt))
decodeCards =
    Dec.list decodeCard


decodeCard : Dec.Decoder (Card UpdatedAt)
decodeCard =
    Dec.map8 Card
        (Dec.field "id" Dec.string)
        (Dec.field "treeId" Dec.string)
        (Dec.field "content" Dec.string)
        (Dec.field "parentId" (Dec.maybe Dec.string))
        (Dec.field "position" Dec.float)
        (Dec.field "deleted" intToBool)
        (Dec.field "synced" Dec.bool)
        (Dec.field "updatedAt" UpdatedAt.decoder)


{-| The `SaveCardBased` payload: which document the save is for, and what it
changes.

`treeId` is here, and not left to the port layer's idea of the current
document, because a save is not always for the document on screen: an import
saves into a document nobody has opened yet, and its two port messages travel
in one `Cmd.batch`, whose order is unspecified (CODE_REVIEW.md D5). Every
sender says which document it means; `src/shared/save.js` refuses a save that
does not.

-}
toSave : String -> DBChangeLists -> Enc.Value
toSave treeId { toAdd, toMarkSynced, toMarkDeleted, toRemove } =
    Enc.object
        [ ( "treeId", Enc.string treeId )
        , ( "toAdd", Enc.list encodeNewCard toAdd )
        , ( "toMarkSynced", Enc.list encodeExistingCard toMarkSynced )
        , ( "toMarkDeleted", Enc.list encodeNewCard toMarkDeleted )
        , ( "toRemove", Enc.list UpdatedAt.encode toRemove )
        ]


saveErrors : List SaveError -> Enc.Value
saveErrors errs =
    let
        errorEnc err =
            case err of
                CardDoesNotExist { id, src } ->
                    Enc.string ("Card with id " ++ id ++ " does not exist.\n" ++ src)
    in
    Enc.object [ ( "errors", Enc.list errorEnc errs ) ]


asUnsynced : Card UpdatedAt -> Card ()
asUnsynced card =
    { id = card.id
    , treeId = card.treeId
    , content = card.content
    , parentId = card.parentId
    , position = card.position
    , deleted = card.deleted
    , synced = False
    , updatedAt = ()
    }


encodeNewCard : Card () -> Enc.Value
encodeNewCard card =
    Enc.object
        [ ( "id", Enc.string card.id )
        , ( "treeId", Enc.string card.treeId )
        , ( "content", Enc.string card.content )
        , ( "parentId", encodeMaybe card.parentId )
        , ( "position", Enc.float card.position )
        , ( "deleted", Enc.int (boolToInt card.deleted) )
        , ( "synced", Enc.bool card.synced )
        , ( "updatedAt", Enc.string "" )
        ]


encodeExistingCard : Card UpdatedAt -> Enc.Value
encodeExistingCard card =
    Enc.object
        [ ( "id", Enc.string card.id )
        , ( "treeId", Enc.string card.treeId )
        , ( "content", Enc.string card.content )
        , ( "parentId", encodeMaybe card.parentId )
        , ( "position", Enc.float card.position )
        , ( "deleted", Enc.int (boolToInt card.deleted) )
        , ( "synced", Enc.bool card.synced )
        , ( "updatedAt", UpdatedAt.encode card.updatedAt )
        ]


importTree : String -> Tree -> Enc.Value
importTree treeId tree =
    fromTree treeId 0 Nothing (Time.millisToPosix 0) 0 tree
        |> List.map asUnsynced
        |> (\cards ->
                { toAdd = cards, toMarkSynced = [], toMarkDeleted = [], toRemove = [] }
                    |> toSave treeId
           )



-- PUBLIC DATA


decodePublicCard : Dec.Decoder (Card UpdatedAt)
decodePublicCard =
    Dec.map8 Card
        (Dec.field "id" Dec.string)
        (Dec.field "treeId" Dec.string)
        (Dec.field "content" Dec.string)
        (Dec.field "parentId" (Dec.maybe Dec.string))
        (Dec.field "position" Dec.float)
        (Dec.succeed False)
        (Dec.succeed True)
        (Dec.field "updatedAt" UpdatedAt.decoder)


{-| KEEP. The public-documents feature is gone, but ~/gingko/verify/ uses this
as its entry point into the real toTree implementation -- it is how the
TypeScript exporter is proven byte-identical to the app.
-}
publicDataDecoder : Dec.Decoder ( String, Tree )
publicDataDecoder =
    Dec.map2 (\n c -> ( n, toTree c ))
        (Dec.at [ "tree", "name" ] Dec.string)
        (Dec.at [ "cards" ] (Dec.list decodePublicCard))



---


type alias DBChangeLists =
    { toAdd : List (Card ())
    , toMarkSynced : List (Card UpdatedAt)
    , toMarkDeleted : List (Card ())
    , toRemove : List UpdatedAt
    }


type SaveError
    = CardDoesNotExist { id : String, src : String }


{-| Stage the local changes an editing operation makes, and remember them.

The returned model carries the rows just handed to the port layer until the DB
echoes them back (`cardDataReceived`). `Doc.Data`'s view of the version log is
refreshed only by the Dexie liveQuery -- one round trip *after* the save that
changed it -- so two saves inside that window would both place their card
against the pre-save siblings and mint the same position (CODE_REVIEW.md D8).

-}
localSave : String -> CardTreeOp -> Model -> ( Model, Enc.Value )
localSave treeId op model =
    case model of
        CardBased data staged history conflicts_ ->
            case localChanges treeId op staged data of
                Ok changes ->
                    ( CardBased data (stageRows (changes.toAdd ++ changes.toMarkDeleted) staged) history conflicts_
                    , toSave treeId changes
                    )

                Err errs ->
                    ( model, saveErrors errs )


{-| The rows staged for the port layer but not echoed back yet, newest first: a
staged row supersedes the row it was built from and any row staged for the same
card before it.
-}
stageRows : List (Card ()) -> List (Card ()) -> List (Card ())
stageRows newRows staged =
    (newRows ++ staged) |> ListExtra.uniqueBy .id


{-| What one editing operation changes in the `cards` table.
-}
localChanges : String -> CardTreeOp -> List (Card ()) -> CardData -> Result (List SaveError) DBChangeLists
localChanges treeId op staged data =
    case op of
        CTUpd id newContent ->
            -- The newest state of the card, with new content: an update carries
            -- the parent and position the card has now.
            case stagedOrNewestRow id staged data of
                Nothing ->
                    Err [ CardDoesNotExist { id = id, src = "CTUpd toAdd_ Nothing" } ]

                Just card ->
                    Ok (changesAdding [ { card | content = newContent } ])

        CTIns id content parId_ idx ->
            let
                placement =
                    placeCard id parId_ idx staged data
            in
            Ok
                (changesAdding
                    ({ id = id, treeId = treeId, content = content, parentId = parId_, position = placement.position, deleted = False, synced = False, updatedAt = () }
                        :: placement.movedSiblings
                    )
                )

        CTRmv id ->
            let
                visibleCards =
                    visibleWithStaged staged data

                idsToMarkAsDeleted =
                    descendantsOf id visibleCards

                cardsToMarkAsDeleted =
                    visibleCards
                        |> List.filter (\card -> List.member card.id idsToMarkAsDeleted)
                        |> List.map (\card -> { card | deleted = True })
            in
            Ok { toAdd = [], toMarkSynced = [], toMarkDeleted = cardsToMarkAsDeleted, toRemove = [] }

        CTMov id parId_ idx ->
            let
                placement =
                    placeCard id parId_ idx staged data
            in
            Ok
                (changesAdding
                    (stagedOrNewestRow id staged data
                        |> Maybe.map
                            (\card ->
                                { card | position = placement.position, parentId = parId_ }
                                    :: placement.movedSiblings
                            )
                        |> Maybe.withDefault []
                    )
                )

        CTMrg currTreeId otherTreeId isMergeUp ->
            case ( stagedOrNewestRow currTreeId staged data, stagedOrNewestRow otherTreeId staged data ) of
                ( Just currCard, Just otherCard ) ->
                    Ok (mergeCards isMergeUp (visibleWithStaged staged data) currCard otherCard)

                ( Nothing, Just _ ) ->
                    Err [ CardDoesNotExist { id = currTreeId, src = "CTMrg currCard_ Nothing" } ]

                ( Just _, Nothing ) ->
                    Err [ CardDoesNotExist { id = otherTreeId, src = "CTMrg otherCard_ Nothing" } ]

                ( Nothing, Nothing ) ->
                    Err
                        [ CardDoesNotExist { id = currTreeId, src = "CTMrg currCard_ Nothing" }
                        , CardDoesNotExist { id = otherTreeId, src = "CTMrg otherCard_ Nothing" }
                        ]

        CTBlk tree parId_ idx ->
            let
                placement =
                    placeCard tree.id parId_ idx staged data

                toAdd =
                    fromTree treeId 0 parId_ (Time.millisToPosix 0) idx tree
                        |> List.map asUnsynced
                        |> List.map
                            (\card ->
                                if card.parentId == parId_ then
                                    { card | position = placement.position }

                                else
                                    card
                            )
            in
            Ok (changesAdding (toAdd ++ placement.movedSiblings))


changesAdding : List (Card ()) -> DBChangeLists
changesAdding rows =
    { toAdd = rows, toMarkSynced = [], toMarkDeleted = [], toRemove = [] }


{-| The newest state of one card, as a save must see it: the row already staged
for it if there is one, else its newest row in the version log.

A staged row is the newer of the two by construction -- it is a save the port
layer has not stamped yet -- so reading the log alone builds the new row from
the state the last save had just changed: move a card and edit it before the
echo and the update row carries the old parent and position, silently undoing
the move (ticket 29).

-}
stagedOrNewestRow : String -> StagedRows -> CardData -> Maybe (Card ())
stagedOrNewestRow cardId staged data =
    case staged |> ListExtra.find (\card -> card.id == cardId) of
        Just stagedRow ->
            Just stagedRow

        Nothing ->
            newestRowOf cardId data |> Maybe.map asUnsynced


{-| The staged rows a card-rows echo leaves standing.

Dexie has spoken, so the rows it echoed -- or superseded -- are spent. But the
echo is fired by *any* write to the open document's cards, and it carries that
document's whole card set, so the one thing it settles about a staged row is
negative: an id it has no row for at all cannot have been written yet, and the
staged row is still the model's only knowledge of that card. A websocket pull
landing between a save and its commit used to clear it.

For an id the echo *does* have rows for, whether ours is among them cannot be
told from state alone. A staged row carries no stamp, so a newest row that says
something else is either our write still in flight or our write already
superseded -- by a collaborator's version, or by a fast-forward. Keeping it on
that guess would leave a phantom row overriding the DB's own answer for as long
as the document stays open; dropping it costs a fraction of one save, which is
the lesser of the two.

-}
unwrittenStaged : CardData -> StagedRows -> StagedRows
unwrittenStaged cards staged =
    staged
        |> List.filter (\row -> not (List.any (\card -> card.id == row.id) cards))


{-| The newest version row of one card id (ADR-0005 §1).
-}
newestRowOf : String -> CardData -> Maybe (Card UpdatedAt)
newestRowOf cardId data =
    data
        |> List.filter (\card -> card.id == cardId)
        |> UpdatedAt.sortNewestFirst .updatedAt
        |> List.head


{-| The rows that merge one card into another: the joined content for the card
kept, a deletion for the card merged in, and a re-parenting for each of its
children.

`isUp` says which side the merged card sat on, which decides the order its text
and its children are joined in -- never *whether* its children are carried over.
They always are: a merge down that left them behind gave a childless surviving
card no children at all, while the same save deleted their parent (ticket 30).

`visibleCards` is the tree as the user sees it -- newest row per id, staged rows
in place, deleted cards gone. Both the position offsets and the rows this emits
depend on it: a stale row would pull a child that has since moved (or been
deleted) back under the merged card (CODE_REVIEW.md D2), and would leave a child
just moved *into* the card being merged behind, parented to a card this save
deletes (ticket 29).

-}
mergeCards : Bool -> List (Card ()) -> Card () -> Card () -> DBChangeLists
mergeCards isUp visibleCards currCard otherCard =
    let
        modifiedCard =
            { currCard
                | content =
                    [ otherCard.content, currCard.content ]
                        |> (if not isUp then
                                List.reverse

                            else
                                identity
                           )
                        |> String.join "\n\n"
            }

        childrenOfCurrent =
            visibleCards
                |> List.filter (\card -> card.parentId == Just currCard.id)

        childrenOfOther =
            visibleCards
                |> List.filter (\card -> card.parentId == Just otherCard.id)

        positionsCurrent =
            childrenOfCurrent |> List.map .position

        positionsOther =
            childrenOfOther |> List.map .position

        ( firstPosOfOther, lastPosOfOther ) =
            ( List.minimum positionsOther, List.maximum positionsOther )

        ( firstPosOfCurrent, lastPosOfCurrent ) =
            ( List.minimum positionsCurrent, List.maximum positionsCurrent )

        -- Where the children of the merged card land among the surviving
        -- card's own: past its last child when the merged card sat below it (a
        -- merge down), back before its first when it sat above (a merge up) --
        -- the order the two cards' text is joined in.  One offset for all of
        -- them, so the gaps they had between them survive the move (ticket
        -- 11).  Either card being childless leaves nothing to sit clear of, so
        -- the positions stand.
        offset =
            if isUp then
                Maybe.map2 (\lastPos firstPos -> firstPos - lastPos - 1) lastPosOfOther firstPosOfCurrent
                    |> Maybe.withDefault 0

            else
                Maybe.map2 (\lastPos firstPos -> lastPos - firstPos + 1) lastPosOfCurrent firstPosOfOther
                    |> Maybe.withDefault 0

        -- Every child of the merged card, and only those: the same save
        -- deletes their parent, so each of them needs a row naming the
        -- surviving card as its parent, in both directions.  The surviving
        -- card's own children stay where they are.
        modifiedChildren =
            childrenOfOther
                |> List.map
                    (\card -> { card | parentId = Just currCard.id, position = card.position + offset })

        toDelete =
            { otherCard | deleted = True }
    in
    { toAdd = [ modifiedCard ] ++ modifiedChildren, toMarkSynced = [], toMarkDeleted = [ toDelete ], toRemove = [] }


{-| The smallest neighbour gap a card will still be placed inside.

Card order is a fraction between the neighbours: insert between two siblings and
the new card takes the midpoint of their positions. That halves the gap every
time, and a Float midpoint stops being a new number once the gap reaches the
last bit of its neighbours' mantissa -- `ulp x`, which is `x * 2^-52`. Past that
point the "midpoint" *is* one of the neighbours, siblings tie, and the order the
user sees comes down to the order Dexie happened to return the rows in
(CODE_REVIEW.md D8).

`1.0e-6` is that cliff with room to spare: it is above `ulp x` for every
position below 2^32, and positions here start life as sibling indices
(`fromTree` uses `toFloat idx`) and grow only by whole-number merge offsets, so
they stay many orders of magnitude below that. It is also small enough to be
generous: at the unit spacing a rebalance lays down, ~20 inserts fit into one
gap before the next rebalance.

-}
positionGapFloor : Float
positionGapFloor =
    1.0e-6


{-| The gap a rebalance leaves between siblings.

One, so rebalanced siblings land on `0, 1, 2, …` -- the same whole numbers a
freshly imported tree gets, and 10^6 times the floor above. A wider grid would
buy only `log2` more inserts per rebalance (10x the spacing is 3 more inserts),
at the cost of positions that no longer read as the card's index.

-}
positionSpacing : Float
positionSpacing =
    1.0


{-| Where a card goes, and which of its siblings have to move to make room.

`movedSiblings` is empty in the ordinary case. It is non-empty when the slot the
card was asked for has no room left: rather than mint a degenerate midpoint, the
whole sibling list is renumbered onto the whole-number grid with the slot left
free. Those rows are ordinary unsynced version rows -- they go out in the same
save and reach the server as `mov` ops like any other move.

-}
type alias Placement =
    { position : Float
    , movedSiblings : List (Card ())
    }


placeCard : String -> Maybe String -> Int -> StagedRows -> CardData -> Placement
placeCard cardId parId idx staged data =
    let
        siblings =
            visibleWithStaged staged data
                |> List.filter (\card -> card.parentId == parId && card.id /= cardId)
                -- By position, then by id: a total order, so two siblings that
                -- do tie (rows written by another client, say) still come out
                -- in the same order every time.
                |> List.sortBy (\card -> ( card.position, card.id ))

        -- `idx` indexes the sibling list as the caller sees it -- the working
        -- tree in `Page.Doc`, which is a save ahead of the rows here whenever
        -- one is in flight.  Out of range means "past the end", i.e. append;
        -- it used to fall through to the no-siblings case and mint position 0,
        -- which is a straight collision with the first sibling.  `999999`, the
        -- caller's "append" sentinel, clamps to the same place.
        slot =
            clamp 0 (List.length siblings) idx
    in
    case ( ListExtra.getAt (slot - 1) siblings, ListExtra.getAt slot siblings ) of
        ( Just sibLeft, Just sibRight ) ->
            if sibRight.position - sibLeft.position >= positionGapFloor then
                { position = (sibLeft.position + sibRight.position) / 2, movedSiblings = [] }

            else
                rebalance slot siblings

        ( Just sibLeft, Nothing ) ->
            { position = sibLeft.position + positionSpacing, movedSiblings = [] }

        ( Nothing, Just sibRight ) ->
            { position = sibRight.position - positionSpacing, movedSiblings = [] }

        ( Nothing, Nothing ) ->
            { position = 0, movedSiblings = [] }


{-| Renumber `siblings` onto the whole-number grid, leaving `slot` free.

Only the siblings that actually move get a row: a sibling already sitting on its
new number has nothing to say, and staging it anyway would write an unsynced row
whose delta carries no ops (CODE_REVIEW.md D9).

-}
rebalance : Int -> List (Card ()) -> Placement
rebalance slot siblings =
    let
        gridPosition index =
            if index < slot then
                toFloat index * positionSpacing

            else
                toFloat (index + 1) * positionSpacing
    in
    { position = toFloat slot * positionSpacing
    , movedSiblings =
        siblings
            |> List.indexedMap Tuple.pair
            |> List.filterMap
                (\( index, card ) ->
                    let
                        target =
                            gridPosition index
                    in
                    if card.position == target then
                        Nothing

                    else
                        Just { card | position = target }
                )
    }


{-| The cards the user can see, as a save must see them: the newest row per id
with the deleted dropped (ADR-0005 §1), overridden by any row already staged for
that card.

`Doc.Data`'s card rows are refreshed only by the Dexie liveQuery, one round trip
*after* the save that changed them, so two saves inside that window both see the
document as it was before the first of them. Both place their new card against
the same siblings and mint the same position (the second half of CODE_REVIEW.md
D8); a subtree walk misses a card just moved in and collects one just moved out
(ticket 29). The staged rows are what closes that window.

-}
visibleWithStaged : StagedRows -> CardData -> List (Card ())
visibleWithStaged staged data =
    let
        stagedIds =
            staged |> List.map .id

        notStaged card =
            not (List.member card.id stagedIds)
    in
    ((data |> newestPerId |> List.map asUnsynced |> List.filter notStaged) ++ staged)
        |> List.filter (not << .deleted)


fromTree : String -> Int -> Maybe String -> Time.Posix -> Int -> Tree -> List (Card UpdatedAt)
fromTree treeId depth parId ts idx tree =
    if tree.id == "0" then
        case tree.children of
            Children children ->
                children
                    |> List.indexedMap (fromTree treeId depth Nothing ts)
                    |> List.concat

    else
        let
            tsInt =
                Time.posixToMillis ts
        in
        { id = tree.id, treeId = treeId, content = tree.content, parentId = parId, position = toFloat idx, deleted = False, synced = False, updatedAt = UpdatedAt.fromParts tsInt depth (hash tsInt tree.id) }
            :: (case tree.children of
                    Children children ->
                        children
                            |> List.indexedMap (fromTree treeId (depth + 1) (Just tree.id) ts)
                            |> List.concat
               )


prefixIds : String -> List (Card a) -> List (Card a)
prefixIds prefix cards =
    List.map (\card -> { card | id = prefix ++ ":" ++ card.id, parentId = card.parentId |> Maybe.map (\pid -> prefix ++ ":" ++ pid) }) cards


toTree : List (Card UpdatedAt) -> Tree
toTree allCards =
    Tree "0" "" (Children (toTrees allCards))


toTrees : List (Card UpdatedAt) -> List Tree
toTrees allCards =
    treeHelper (newestVisible allCards) Nothing


{-| The newest version row of each card id.

The version log is append-mostly (Dexie's `cards` primary key is `updatedAt`),
so rows a card has outgrown -- an old parent, an old position, an undeleted
row of a deleted card -- stay in the table until push + fast-forward. Per
ADR-0005 §1, newest-row-per-id is the only legal view of that log: every scan
of the rows reduces to it first.

-}
newestPerId : List (Card UpdatedAt) -> List (Card UpdatedAt)
newestPerId allCards =
    allCards
        |> UpdatedAt.sortNewestFirst .updatedAt
        |> ListExtra.uniqueBy .id


{-| The cards the user can see: newest row per id, minus the cards whose
newest row marks them deleted. Note the order -- dropping deleted rows before
deduping would resurrect a deleted card from one of its older rows.
-}
newestVisible : List (Card UpdatedAt) -> List (Card UpdatedAt)
newestVisible allCards =
    allCards
        |> newestPerId
        |> List.filter (not << .deleted)


treeHelper : List (Card UpdatedAt) -> Maybe String -> List Tree
treeHelper allCards parentId =
    let
        cards =
            allCards
                |> List.filter (\card -> card.parentId == parentId)
                -- By position, then by id.  Local saves can no longer mint two
                -- siblings with the same position (CODE_REVIEW.md D8), but rows
                -- written by another client still can, and sorting on position
                -- alone would then leave the order the user sees up to the
                -- order Dexie returned the rows in.
                |> List.sortBy (\card -> ( card.position, card.id ))
    in
    List.map (\card -> { id = card.id, content = card.content, children = Children (treeHelper allCards (Just card.id)) }) cards


{-| The card and every card below it, as the user sees the tree.

The caller passes the cards as the user sees them (`visibleWithStaged`): walking
the raw rows would collect a card whose *stale* row still names `id` as its
parent, so deleting a card would delete a card that had been moved out of it
(CODE_REVIEW.md D1) and miss one just moved into it (ticket 29). Cards already
deleted are left out too: they are not in the subtree on screen, and re-marking
them adds a redundant unsynced deletion row per pass.

-}
descendantsOf : String -> List (Card a) -> List String
descendantsOf id visibleCards =
    case visibleCards |> ListExtra.find (\card -> card.id == id) of
        Nothing ->
            []

        Just card ->
            card.id
                :: (visibleCards
                        |> List.filter (\c -> c.parentId == Just id)
                        |> List.map .id
                        |> List.concatMap (\i -> descendantsOf i visibleCards)
                   )


type alias Versions =
    { original : List (Card UpdatedAt)
    , ours : List (Card UpdatedAt)
    , theirs : List (Card UpdatedAt)
    }


type SyncState
    = Synced
    | Unsynced
    | CanFastForward (List UpdatedAt)
    | Conflicted Versions
    | Errored


getCardById : List (Card UpdatedAt) -> String -> Maybe (Card UpdatedAt)
getCardById db id =
    db
        |> List.filter (\card -> card.id == id)
        |> UpdatedAt.sortNewestFirst .updatedAt
        |> List.head


getSyncState : List (Card UpdatedAt) -> SyncState
getSyncState db =
    let
        shouldSyncEmptyCards =
            List.length db == 1

        cardSyncStates =
            db
                |> ListExtra.gatherWith (\a b -> a.id == b.id)
                |> List.map (\( a, rest ) -> a :: rest)
                |> List.map
                    (\c ->
                        let
                            cardSyncState =
                                getCardSyncState shouldSyncEmptyCards c

                            cardId =
                                c
                                    |> List.head
                                    |> Maybe.map .id
                                    |> Maybe.withDefault ""
                        in
                        ( cardId, cardSyncState )
                    )
    in
    if
        List.any
            (\( _, s ) ->
                case s of
                    Conflicted _ ->
                        True

                    _ ->
                        False
            )
            cardSyncStates
    then
        let
            versions =
                cardSyncStates
                    |> List.filterMap
                        (\( _, s ) ->
                            case s of
                                Conflicted v ->
                                    Just v

                                _ ->
                                    Nothing
                        )

            allOrig =
                versions |> List.concatMap .original

            allOurs =
                versions |> List.concatMap .ours

            allTheirs =
                versions |> List.concatMap .theirs
        in
        Conflicted { original = allOrig, ours = allOurs, theirs = allTheirs }

    else if List.any (\( _, s ) -> s == Unsynced) cardSyncStates then
        Unsynced

    else if List.all (\( _, s ) -> s == Synced) cardSyncStates then
        Synced

    else if
        List.any
            (\( _, s ) ->
                case s of
                    CanFastForward _ ->
                        True

                    _ ->
                        False
            )
            cardSyncStates
    then
        let
            allFFids =
                cardSyncStates
                    |> List.filterMap
                        (\( _, s ) ->
                            case s of
                                CanFastForward ids ->
                                    Just ids

                                _ ->
                                    Nothing
                        )
                    |> List.concat
        in
        CanFastForward allFFids

    else
        Errored


getCardSyncState : Bool -> List (Card UpdatedAt) -> SyncState
getCardSyncState shouldSyncEmpty cardVersions =
    let
        ( syncedVersions, unsyncedVersions ) =
            cardVersions
                |> List.partition .synced
                |> Tuple.mapBoth List.length List.length

        versions =
            { original = getOriginals cardVersions
            , ours = getOurs cardVersions
            , theirs = getTheirs cardVersions
            }
    in
    if unsyncedVersions == 1 && syncedVersions == 0 && (List.map .content versions.ours == [ "" ]) then
        if shouldSyncEmpty then
            Unsynced

        else
            -- Brand new card with empty content shouldn't be pushed, so we mark it as "Synced" to prevent that.
            Synced

    else if unsyncedVersions > 0 && syncedVersions <= historyLimit then
        Unsynced

    else if unsyncedVersions > 0 && syncedVersions > historyLimit then
        Conflicted versions

    else if unsyncedVersions == 0 && syncedVersions > 0 && syncedVersions <= historyLimit then
        Synced

    else if unsyncedVersions == 0 && syncedVersions > historyLimit then
        let
            ids =
                cardVersions
                    |> List.map .updatedAt
                    |> UpdatedAt.sortNewestFirst identity
                    |> List.drop historyLimit
        in
        CanFastForward ids

    else
        Errored


getOriginals : List (Card UpdatedAt) -> List (Card UpdatedAt)
getOriginals db =
    db
        |> List.filter .synced
        |> UpdatedAt.sortOldestFirst .updatedAt
        |> List.head
        |> Maybe.map List.singleton
        |> Maybe.withDefault []


getOurs : List (Card UpdatedAt) -> List (Card UpdatedAt)
getOurs db =
    db
        |> List.filter (not << .synced)
        |> UpdatedAt.sortNewestFirst .updatedAt
        |> List.head
        |> Maybe.map List.singleton
        |> Maybe.withDefault []


getTheirs : List (Card UpdatedAt) -> List (Card UpdatedAt)
getTheirs db =
    db
        |> List.filter .synced
        |> UpdatedAt.sortNewestFirst .updatedAt
        |> (\l ->
                if List.length l > historyLimit then
                    [ List.head l ]

                else
                    [ Nothing ]
           )
        |> List.filterMap identity


resolveDeleteConflicts : List (Card UpdatedAt) -> Versions -> DBChangeLists
resolveDeleteConflicts allCards versions =
    let
        idsOfConflicts =
            (versions.original ++ versions.ours ++ versions.theirs)
                |> List.map .id
                |> ListExtra.unique

        conflictPerCard : String -> { original : Maybe (Card UpdatedAt), ours : Maybe (Card UpdatedAt), theirs : Maybe (Card UpdatedAt) }
        conflictPerCard cardId =
            { original = ListExtra.find (\c -> c.id == cardId) versions.original
            , ours = ListExtra.find (\c -> c.id == cardId) versions.ours
            , theirs = ListExtra.find (\c -> c.id == cardId) versions.theirs
            }

        ( ourDeletionHashes, theirDeletionHashes ) =
            idsOfConflicts
                |> List.map conflictPerCard
                |> List.concatMap
                    (\v ->
                        case ( v.original, v.ours, v.theirs ) of
                            ( Just _, Just ours, Just thr ) ->
                                if ours.deleted && not thr.deleted then
                                    [ ( True, ours.updatedAt ) ]

                                else if not ours.deleted && thr.deleted then
                                    [ ( False, thr.updatedAt ) ]

                                else
                                    []

                            _ ->
                                []
                    )
                |> List.map (\( ot, ua ) -> ( ot, UpdatedAt.getHash ua ))
                |> List.partition Tuple.first
                |> Tuple.mapBoth (List.map Tuple.second) (List.map Tuple.second)

        ourDeletionTimestamps =
            -- If the delete conflict is because we deleted it on 'Our' side, then we need to undo those deletions
            -- by removing our unsynced deletions from the DB
            allCards
                |> List.filter
                    (\c ->
                        c.updatedAt
                            |> UpdatedAt.getHash
                            |> (\h -> List.member h ourDeletionHashes)
                    )
                |> List.map .updatedAt
                |> UpdatedAt.unique

        theirDeletionIds =
            allCards
                |> List.filter
                    (\c ->
                        c.updatedAt
                            |> UpdatedAt.getHash
                            |> (\h -> List.member h theirDeletionHashes)
                    )
                |> List.map .id
                |> ListExtra.unique

        theirDeletionCards =
            allCards
                |> List.filter
                    (\c ->
                        List.member c.id theirDeletionIds
                            && c.synced
                            && not
                                (theirDeletionHashes |> List.member (c.updatedAt |> UpdatedAt.getHash))
                    )

        theirDeletionsToRemove =
            -- If the delete conflict is because they deleted it on 'Their' side, then we need to undo those deletions
            -- by removing the pre-deletion synced version from the DB.  That
            -- leaves their deletion as the only synced row and our edit as the
            -- only unsynced one, which is exactly the pair `cardDelta` turns
            -- into an undelete + our content (edits beat deletions).
            --
            -- Nothing is added here.  The limb that claimed to add "new
            -- unsynced undeleted versions so we can create deltas based off
            -- them" filtered ids out of the set they came from, so it was
            -- always empty (CODE_REVIEW.md D10) -- and it built those versions
            -- from the *pre-deletion* content.  The port layer stamps a staged
            -- row as it writes it, so such a row would outrank our edit and
            -- become the one pushed, silently reverting the very edit this
            -- resolution exists to keep.
            theirDeletionCards
                |> List.map .updatedAt
                |> UpdatedAt.unique
    in
    { toAdd = [], toMarkSynced = [], toMarkDeleted = [], toRemove = ourDeletionTimestamps ++ theirDeletionsToRemove |> UpdatedAt.unique }


pushOkHandler : String -> List String -> Model -> Maybe Outgoing.Msg
pushOkHandler treeId chkValStrings model =
    case model of
        CardBased data _ _ _ ->
            let
                chkValsAsUpdatedAt =
                    chkValStrings
                        |> List.map (\cv -> UpdatedAt.fromString cv)
                        |> Result.Extra.combine
            in
            case chkValsAsUpdatedAt of
                Ok chkVals ->
                    let
                        cardIdsFromUpdatedAt : UpdatedAt -> List String
                        cardIdsFromUpdatedAt chkVal =
                            data
                                |> List.filter (\card -> UpdatedAt.areEqual card.updatedAt chkVal)
                                |> List.map .id

                        markVersionSynced : UpdatedAt -> List (Card UpdatedAt)
                        markVersionSynced chkVal =
                            data
                                |> List.filter
                                    (\card ->
                                        card.synced
                                            == False
                                            && List.member card.id (cardIdsFromUpdatedAt chkVal)
                                            && UpdatedAt.isLTE card.updatedAt chkVal
                                    )
                                |> List.map (\card -> { card | synced = True })

                        versionsToMarkSynced : List (Card UpdatedAt)
                        versionsToMarkSynced =
                            List.concatMap markVersionSynced chkVals
                    in
                    Just <|
                        SaveCardBased <|
                            toSave treeId { toAdd = [], toMarkSynced = versionsToMarkSynced, toMarkDeleted = [], toRemove = [] }

                Err err ->
                    Nothing



-- Deltas


type alias Delta =
    { id : String, treeId : String, ts : UpdatedAt, ops : List CardOp }


type CardOp
    = InsOp { id : String, content : String, parentId : Maybe String, position : Float }
    | UpdOp { content : String, expectedVersion : UpdatedAt }
    | MovOp { parentId : Maybe String, position : Float }
    | DelOp { expectedVersion : UpdatedAt }
    | UndelOp


{-| The push message for everything unsynced in the document -- or no message
at all, when nothing is left to say.

`toDelta` drops the cards that ask for no ops, so a document can classify as
`Unsynced` and still have nothing to push. An empty `dlts` is not how to say
that: the server reads `dlts[dlts.length - 1].ts` before it looks at the list
(gingko/server `src/index.ts`).

-}
pushDeltas : String -> List (Card UpdatedAt) -> List Outgoing.Msg
pushDeltas treeId db =
    case toDelta treeId db of
        [] ->
            []

        deltas ->
            let
                checkpoint =
                    db
                        |> List.filter .synced
                        |> List.map .updatedAt
                        |> UpdatedAt.maximum
                        |> Maybe.withDefault UpdatedAt.zero
            in
            [ PushDeltas
                (Enc.object
                    [ ( "dlts", Enc.list encodeDelta deltas )
                    , ( "tr", Enc.string treeId )
                    , ( "chk", UpdatedAt.encode checkpoint )
                    ]
                )
            ]


{-| Every card's delta, oldest first.

Cards with nothing to say are dropped. A card whose newest unsynced row matches
the row it is diffed against in every field produces no ops, and an op-less
delta is not a no-op on the wire: the server reads it as "set this card's
version to this stamp", writing a change nobody made and telling every
collaborator to pull it (CODE_REVIEW.md D9). The filter sits here, over the
whole list, because this is the one function every push and every test goes
through, while `cardDelta` can emit an op-less delta from either of two limbs.

-}
toDelta : String -> List (Card UpdatedAt) -> List Delta
toDelta treeId cards =
    cards
        |> List.map .id
        |> ListExtra.unique
        |> List.concatMap (cardDelta treeId cards)
        |> List.filter (not << List.isEmpty << .ops)
        |> UpdatedAt.sortOldestFirst .ts


cardDelta : String -> List (Card UpdatedAt) -> String -> List Delta
cardDelta treeId allCards cardId =
    let
        cardVersions =
            allCards
                |> List.filter (\c -> c.id == cardId)
                |> UpdatedAt.sortNewestFirst .updatedAt

        unsyncedCards =
            cardVersions
                |> List.filter (not << .synced)

        syncedCard_ =
            cardVersions
                |> List.filter .synced
                |> List.head
    in
    case ( unsyncedCards, syncedCard_ ) of
        ( [], Just _ ) ->
            []

        ( unsyncedCard :: _, Just syncedCard ) ->
            let
                updateOps =
                    if unsyncedCard.content /= syncedCard.content then
                        [ UpdOp { content = unsyncedCard.content, expectedVersion = syncedCard.updatedAt } ]

                    else
                        []

                moveOps =
                    if (unsyncedCard.parentId /= syncedCard.parentId) || (unsyncedCard.position /= syncedCard.position) then
                        [ MovOp { parentId = unsyncedCard.parentId, position = unsyncedCard.position } ]

                    else
                        []

                ( deleteOps, undeleteOps ) =
                    if unsyncedCard.deleted && not syncedCard.deleted then
                        ( [ DelOp { expectedVersion = syncedCard.updatedAt } ], [] )

                    else if not unsyncedCard.deleted && syncedCard.deleted then
                        ( [], [ UndelOp ] )

                    else
                        ( [], [] )
            in
            [ Delta cardId treeId unsyncedCard.updatedAt (undeleteOps ++ deleteOps ++ moveOps ++ updateOps) ]

        ( [], Nothing ) ->
            []

        ( unsyncedCard :: [], Nothing ) ->
            [ Delta cardId
                treeId
                unsyncedCard.updatedAt
                [ InsOp { id = unsyncedCard.id, content = unsyncedCard.content, parentId = unsyncedCard.parentId, position = unsyncedCard.position } ]
            ]

        ( multipleNeverSynced, Nothing ) ->
            case ( multipleNeverSynced, List.reverse multipleNeverSynced ) of
                ( [], [] ) ->
                    []

                ( onlyUnsynced :: [], _ :: [] ) ->
                    [ Delta cardId
                        treeId
                        onlyUnsynced.updatedAt
                        [ InsOp { id = onlyUnsynced.id, content = onlyUnsynced.content, parentId = onlyUnsynced.parentId, position = onlyUnsynced.position } ]
                    ]

                ( newestUnsynced :: _, oldestUnsynced :: _ ) ->
                    let
                        updateOps =
                            if newestUnsynced.content /= oldestUnsynced.content then
                                [ UpdOp { content = newestUnsynced.content, expectedVersion = oldestUnsynced.updatedAt } ]

                            else
                                []

                        moveOps =
                            if (newestUnsynced.parentId /= oldestUnsynced.parentId) || (newestUnsynced.position /= oldestUnsynced.position) then
                                [ MovOp { parentId = newestUnsynced.parentId, position = newestUnsynced.position } ]

                            else
                                []

                        ( deleteOps, undeleteOps ) =
                            if newestUnsynced.deleted && not oldestUnsynced.deleted then
                                ( [ DelOp { expectedVersion = oldestUnsynced.updatedAt } ], [] )

                            else if not newestUnsynced.deleted && oldestUnsynced.deleted then
                                ( [], [ UndelOp ] )

                            else
                                ( [], [] )
                    in
                    [ Delta cardId
                        treeId
                        oldestUnsynced.updatedAt
                        [ InsOp { id = oldestUnsynced.id, content = oldestUnsynced.content, parentId = oldestUnsynced.parentId, position = oldestUnsynced.position } ]
                    , Delta cardId
                        treeId
                        newestUnsynced.updatedAt
                        (undeleteOps ++ deleteOps ++ moveOps ++ updateOps)
                    ]

                _ ->
                    []


encodeDelta : Delta -> Enc.Value
encodeDelta delta =
    Enc.object
        [ ( "id", Enc.string delta.id )
        , ( "ts", UpdatedAt.encode delta.ts )
        , ( "ops", Enc.list opEncoder delta.ops )
        ]


opEncoder : CardOp -> Enc.Value
opEncoder op =
    case op of
        InsOp insOp ->
            Enc.object
                [ ( "t", Enc.string "i" )
                , ( "c", Enc.string insOp.content )
                , ( "p", encodeMaybe insOp.parentId )
                , ( "pos", Enc.float insOp.position )
                ]

        UpdOp updOp ->
            Enc.object
                [ ( "t", Enc.string "u" )
                , ( "c", Enc.string updOp.content )
                , ( "e", UpdatedAt.encode updOp.expectedVersion )
                ]

        MovOp movOp ->
            Enc.object
                [ ( "t", Enc.string "m" )
                , ( "p", encodeMaybe movOp.parentId )
                , ( "pos", Enc.float movOp.position )
                ]

        DelOp delOp ->
            Enc.object
                [ ( "t", Enc.string "d" )
                , ( "e", UpdatedAt.encode delOp.expectedVersion )
                ]

        UndelOp ->
            Enc.object
                [ ( "t", Enc.string "ud" )
                ]



-- HISTORY


historyReceived : Dec.Value -> Model -> Model
historyReceived json model =
    case model of
        CardBased data staged oldHistory conflicts_ ->
            case Dec.decodeValue decodeHistory json of
                Ok history ->
                    let
                        oldHistoryDict : Dict String ( Time.Posix, WebData CardData )
                        oldHistoryDict =
                            oldHistory
                                |> List.map (\( id, ts, cardData ) -> ( id, ( ts, cardData ) ))
                                |> Dict.fromList

                        newHistoryDict : Dict String ( Time.Posix, WebData CardData )
                        newHistoryDict =
                            history
                                |> List.map (\( id, ts, cardData_ ) -> ( id, ( ts, RemoteData.fromMaybe (BadBody "Couldn't load history data") cardData_ ) ))
                                |> Dict.fromList

                        inBoth : String -> ( Time.Posix, WebData CardData ) -> ( Time.Posix, WebData CardData ) -> List ( String, Time.Posix, WebData CardData ) -> List ( String, Time.Posix, WebData CardData )
                        inBoth id ( tsL, cardDataL ) ( tsR, cardDataR ) acc =
                            case ( cardDataL, cardDataR ) of
                                ( RemoteData.Success _, _ ) ->
                                    ( id, tsL, cardDataL ) :: acc

                                ( _, RemoteData.Success _ ) ->
                                    ( id, tsR, cardDataR ) :: acc

                                _ ->
                                    ( id, tsL, cardDataL ) :: acc

                        newHistory : List ( String, Time.Posix, WebData CardData )
                        newHistory =
                            Dict.merge
                                (\id ( ts, cd ) -> List.append [ ( id, ts, cd ) ])
                                inBoth
                                (\id ( ts, cd ) -> List.append [ ( id, ts, cd ) ])
                                oldHistoryDict
                                newHistoryDict
                                []
                    in
                    CardBased data staged newHistory conflicts_

                Err err ->
                    model

decodeHistory : Dec.Decoder (List ( String, Time.Posix, Maybe (List (Card UpdatedAt)) ))
decodeHistory =
    Dec.list <|
        Dec.map3 (\id ts cards -> ( id, ts, cards ))
            (Dec.field "snapshot" Dec.string)
            (Dec.field "ts" (Dec.map Time.millisToPosix Dec.int))
            (Dec.field "data" (Dec.maybe decodeCards))


getHistoryList : Model -> List ( String, Time.Posix, Maybe Tree )
getHistoryList model =
    case model of
        CardBased _ _ history _ ->
            history
                |> List.map (\( id, ts, cardData_ ) -> ( id, ts, cardData_ |> RemoteData.toMaybe |> Maybe.map toTree ))
                |> List.reverse



-- HELPERS


intToBool : Dec.Decoder Bool
intToBool =
    Dec.map (\i -> i == 1) Dec.int


encodeMaybe : Maybe String -> Enc.Value
encodeMaybe maybe =
    case maybe of
        Just str ->
            Enc.string str

        Nothing ->
            Enc.null


boolToInt : Bool -> Int
boolToInt b =
    if b then
        1

    else
        0



-- TESTS


type alias Card_tests_only t =
    { id : String
    , treeId : String
    , content : String
    , parentId : Maybe String
    , position : Float
    , deleted : Bool
    , synced : Bool
    , updatedAt : t
    }


type SaveError_tests_only
    = CardDoesNotExist_tests_only { id : String, src : String }


model_tests_only : CardData -> Maybe CardDataConflicts -> Model
model_tests_only cards conflicts_ =
    CardBased cards [] [] conflicts_


toSave_tests_only : String -> DBChangeLists -> Enc.Value
toSave_tests_only =
    toSave


saveErrors_tests_only : List SaveError_tests_only -> Enc.Value
saveErrors_tests_only errs =
    List.map saveErrorConvert errs
        |> saveErrors


saveErrorConvert : SaveError_tests_only -> SaveError
saveErrorConvert err =
    case err of
        CardDoesNotExist_tests_only errInfo ->
            CardDoesNotExist errInfo



-- delta tests


type CardOp_tests_only
    = InsOp_t { id : String, content : String, parentId : Maybe String, position : Float }
    | UpdOp_t { content : String, expectedVersion : UpdatedAt }
    | MovOp_t { parentId : Maybe String, position : Float }
    | DelOp_t { expectedVersion : UpdatedAt }
    | UndelOp_t


type alias Delta_tests_only =
    { id : String, treeId : String, ts : UpdatedAt, ops : List CardOp }


cardOpConvert : CardOp_tests_only -> CardOp
cardOpConvert cOp =
    case cOp of
        InsOp_t insOp ->
            InsOp insOp

        UpdOp_t updOp ->
            UpdOp updOp

        MovOp_t movOp ->
            MovOp movOp

        DelOp_t delOp ->
            DelOp delOp

        UndelOp_t ->
            UndelOp


toDelta_tests_only : String -> List (Card UpdatedAt) -> List Delta
toDelta_tests_only treeId db =
    toDelta treeId db
