module Doc.TreeStructure exposing (Model, Msg(..), Placement, apply, conflictToMsg, defaultModel, defaultTree, dropPlacement, labelTree, opToMsg, renameNodes, setTree, setTreeWithConflicts, update)

import Diff exposing (..)
import Diff3 exposing (diff3Merge)
import Doc.Data.Conflict as Conflict exposing (Conflict, Op(..), Selection(..))
import Doc.TreeUtils exposing (getChildren, getColumns, getIndex, getParent, getTree, sha1)
import List.Extra as ListExtra
import Regex
import Types exposing (Children(..), Column, DropId(..), Tree)



-- MODEL


type alias Model =
    { tree : Tree
    , columns : List Column
    }


defaultModel : Model
defaultModel =
    { tree = defaultTree
    , columns = [ [ [ defaultTree ] ], [ getChildren defaultTree ] ]
    }


defaultTree : Tree
defaultTree =
    { id = "0"
    , content = ""
    , children = Children []
    }



-- UPDATE


type Msg
    = Nope
    | Ins String String String Int
    | Upd String String
    | Mov Tree String Int
    | Rmv String
    | Mrg Tree Tree Bool
    | Paste Tree String Int


update : Msg -> Model -> Model
update msg model =
    setTree (updateTree msg model.tree) model


updateTree : Msg -> Tree -> Tree
updateTree msg tree =
    case msg of
        Ins newId newContent parentId idx ->
            insertSubtree (Tree newId newContent (Children [])) parentId idx tree

        Upd id str ->
            modifyTree id (\t -> { t | content = str }) tree

        Mov newTree parentId idx ->
            tree
                |> pruneSubtree newTree.id
                |> insertSubtree newTree parentId idx

        Rmv id ->
            pruneSubtree id tree

        Mrg fromTree toTree isReversed ->
            let
                maybeReverse =
                    if isReversed then
                        List.reverse

                    else
                        identity

                mergedContent =
                    [ fromTree.content, toTree.content ]
                        |> maybeReverse
                        |> String.join "\n\n"

                mergedChildren =
                    Children
                        ([ getChildren fromTree, getChildren toTree ]
                            |> maybeReverse
                            |> List.concat
                        )
            in
            tree
                |> pruneSubtree toTree.id
                |> modifyTree fromTree.id (\t -> { t | content = mergedContent, children = mergedChildren })

        Paste newTree parentId idx ->
            tree
                |> insertSubtree newTree parentId idx

        Nope ->
            tree


setTree : Tree -> Model -> Model
setTree newTree model =
    let
        newColumns =
            if newTree /= model.tree then
                getColumns [ [ [ newTree ] ] ]

            else
                model.columns
    in
    { model
        | tree = newTree
        , columns = newColumns
    }


setTreeWithConflicts : List Conflict -> Tree -> Model -> Model
setTreeWithConflicts conflicts originalTree model =
    let
        newTree =
            originalTree
                |> apply (List.map (conflictToMsg originalTree) conflicts)

        newColumns =
            if newTree /= model.tree then
                getColumns [ [ [ newTree ] ] ]

            else
                model.columns
    in
    { model
        | tree = newTree
        , columns = newColumns
    }


conflictToMsg : Tree -> Conflict -> Msg
conflictToMsg tree { id, opA, opB, selection, resolved } =
    case ( selection, resolved ) of
        ( Original, False ) ->
            case ( opA, opB ) of
                ( Mod tid pars strA orig, Mod _ _ _ _ ) ->
                    opToMsg tree (Mod tid pars orig strA)

                _ ->
                    Nope

        ( Ours, False ) ->
            opToMsg tree opA

        ( Theirs, False ) ->
            opToMsg tree opB

        ( Manual, False ) ->
            case ( opA, opB ) of
                ( Mod tid _ strA orig, Mod _ _ strB _ ) ->
                    let
                        tokenize s =
                            Regex.split (Regex.fromString "(\\s+|\\b)" |> Maybe.withDefault Regex.never) s

                        -- List String
                        changeMerge d ds =
                            case ( d, ds ) of
                                ( NoChange a, (NoChange b) :: tail ) ->
                                    NoChange (a ++ b) :: tail

                                ( Added a, (Added b) :: tail ) ->
                                    Added (a ++ b) :: tail

                                ( Removed a, (Removed b) :: tail ) ->
                                    Removed (a ++ b) :: tail

                                ( ch, list ) ->
                                    ch :: list

                        diffWords l r =
                            diff (tokenize l) (tokenize r)
                                |> List.foldr changeMerge []
                                |> List.map
                                    (\c ->
                                        case c of
                                            NoChange s ->
                                                s

                                            Added s ->
                                                "{++" ++ s ++ "++}"

                                            Removed s ->
                                                "{--" ++ s ++ "--}"
                                    )
                                |> String.join ""

                        diffLinesString l r =
                            diffLines l r
                                |> List.map
                                    (\c ->
                                        case c of
                                            NoChange s ->
                                                s

                                            Added s ->
                                                "{++" ++ s ++ "++}"

                                            Removed s ->
                                                "{--" ++ s ++ "--}"
                                    )
                                |> String.join "\n"

                        mergedString : String
                        mergedString =
                            diff3Merge (String.lines strA) (String.lines orig) (String.lines strB)
                                |> List.map
                                    (\c ->
                                        case c of
                                            Diff3.DiffOk strings ->
                                                String.join "\n" strings

                                            Diff3.DiffConflict ( strAs, strOs, strBs ) ->
                                                "\n`>>>>>>>`\n"
                                                    ++ String.join "\n" strAs
                                                    ++ "\n`=======`\n"
                                                    ++ String.join "\n" strBs
                                                    ++ "\n`<<<<<<<`\n"
                                    )
                                |> String.join "\n"

                        manualString =
                            "`Your version:`\n"
                                ++ diffLinesString orig strA
                                ++ "\n\n--------\n`Their version:`\n"
                                ++ diffLinesString orig strB
                    in
                    Upd tid mergedString

                _ ->
                    Nope

        _ ->
            Nope


opToMsg : Tree -> Op -> Msg
opToMsg origTree op =
    case op of
        Mod tid _ str _ ->
            Upd tid str

        Del tid _ ->
            Rmv tid

        Conflict.Ins id str pids idx ->
            case ListExtra.last pids of
                Just pid ->
                    Ins id str pid idx

                Nothing ->
                    Nope

        Conflict.Mov tid _ _ npids nidx ->
            case ( getTree tid origTree, ListExtra.last npids ) of
                ( Just tree, Just pid ) ->
                    Mov tree pid nidx

                _ ->
                    Nope


{-| The parent a dragged card lands under, and its index among that parent's
children.
-}
type alias Placement =
    { parentId : String, index : Int }


{-| The index that means "past the last child", i.e. append.

`Doc.Data.placeCard` clamps an out-of-range index to an append, so this survives
the trip through the port even though the row it lands among may be a save
ahead of the tree it was read from.

-}
appendIndex : Int
appendIndex =
    999999


{-| Where a card dropped on `dropId` lands: the `Mov` arguments for the drop, or
`Nothing` if the drop names no place the card can go.

Read on the tree the dragged card has already been pruned out of, because that
is what `Mov` inserts into (`updateTree` above prunes first) and what
`Doc.Data.placeCard` positions among (its sibling list excludes the card being
moved). On the tree as it appears on screen the dragged card still counts, so a
drop below the next sibling landed one slot too far -- past it and past the one
after (CODE_REVIEW.md E7).

Pruning also answers the drops that cannot happen: a card cannot land inside its
own subtree, and on the pruned tree that subtree is simply not there, so the
target has no parent and no index and there is no move to make. The card stays
where it is. Left to go through, `insertSubtree` would look for a parent that
had just been pruned away, find nothing, and drop the dragged card and every
card under it on the floor.

-}
dropPlacement : String -> DropId -> Tree -> Maybe Placement
dropPlacement draggedId dropId tree =
    let
        pruned =
            pruneSubtree draggedId tree

        siblingPlacement targetId offset =
            Maybe.map2
                (\parent index -> { parentId = parent.id, index = index + offset })
                (getParent targetId pruned)
                (getIndex targetId pruned)
    in
    case dropId of
        Above targetId ->
            siblingPlacement targetId 0

        Below targetId ->
            siblingPlacement targetId 1

        Into targetId ->
            getTree targetId pruned
                |> Maybe.map (\target -> { parentId = target.id, index = appendIndex })



-- TREE TRANSFORMATIONS


apply : List Msg -> Tree -> Tree
apply msgs tree =
    List.foldl (\m t -> updateTree m t) tree msgs


insertSubtree : Tree -> String -> Int -> Tree -> Tree
insertSubtree subtree parentId idx tree =
    let
        fn =
            \c -> List.take idx c ++ [ subtree ] ++ List.drop idx c
    in
    modifyChildren parentId fn tree


pruneSubtree : String -> Tree -> Tree
pruneSubtree id tree =
    modifySiblings id (\c -> List.filter (\x -> x.id /= id) c) tree


modifyTree : String -> (Tree -> Tree) -> Tree -> Tree
modifyTree id upd tree =
    if tree.id == id then
        upd tree

    else
        { tree
            | children =
                getChildren tree
                    |> List.map (modifyTree id upd)
                    |> Children
        }


modifyChildren : String -> (List Tree -> List Tree) -> Tree -> Tree
modifyChildren pid upd tree =
    if tree.id == pid then
        { tree
            | children =
                getChildren tree
                    |> upd
                    |> Children
        }

    else
        { tree
            | children =
                getChildren tree
                    |> List.map (modifyChildren pid upd)
                    |> Children
        }


modifySiblings : String -> (List Tree -> List Tree) -> Tree -> Tree
modifySiblings id upd tree =
    case getParent id tree of
        Nothing ->
            tree

        Just parentTree ->
            modifyChildren parentTree.id upd tree


renameNodes : String -> Tree -> Tree
renameNodes salt tree =
    let
        newId =
            sha1 (salt ++ tree.id)
    in
    { tree
        | id = newId
        , children =
            getChildren tree
                |> List.map (renameNodes salt)
                |> Children
    }


labelTree : Int -> String -> Tree -> Tree
labelTree idx pid ult =
    let
        newId =
            pid ++ "." ++ String.fromInt idx
    in
    case ult.children of
        Children [] ->
            Tree newId ult.content (Children [])

        Children childs ->
            Tree
                newId
                ult.content
                (Children
                    (childs
                        |> List.indexedMap (\i ut -> labelTree i newId ut)
                    )
                )
