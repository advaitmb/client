module Types exposing (CardTreeOp(..), Children(..), CollabStateMode(..), Collaborator, Column, ConflictSelection(..), CursorPosition(..), DragExternalModel, DropId(..), Group, OutsideData, SortBy(..), TextCursorInfo, Toast, ToastPersistence(..), ToastRole(..), TooltipPosition(..), Tree, ViewMode(..), ViewState)

import Json.Encode as Enc


type alias Tree =
    { id : String
    , content : String
    , children : Children
    }


type Children
    = Children (List Tree)


type alias Group =
    List Tree


type alias Column =
    List (List Tree)



-- Tree Ops for Card Based


type CardTreeOp
    = CTIns String String (Maybe String) Int
    | CTUpd String String
    | CTRmv String
    | CTMov String (Maybe String) Int
    | CTMrg String String Bool
    | CTBlk Tree (Maybe String) Int



-- Conflict Version Selection


type ConflictSelection
    = Ours
    | Theirs
    | Original



-- JS Interop


type alias OutsideData =
    { tag : String, data : Enc.Value }



-- Drag and Drop


type DropId
    = Above String
    | Below String
    | Into String


type alias DragExternalModel =
    { dropId : Maybe DropId, isDragging : Bool }


-- Toasts


type alias Toast =
    { role : ToastRole
    , message : String
    }


type ToastRole
    = Info
    | Warning
    | Error
    | SuccessToast


type ToastPersistence
    = Persistent
    | Temporary



-- Transient View States


type ViewMode
    = Normal String
    | Editing { cardId : String, field : String }
    | FullscreenEditing { cardId : String, field : String }


type SortBy
    = Alphabetical
    | ModifiedAt
    | CreatedAt


type TooltipPosition
    = RightTooltip
    | LeftTooltip
    | AboveTooltip
    | BelowTooltip
    | BelowLeftTooltip


type alias Collaborator =
    { uid : String
    , name : String
    , mode : CollabStateMode
    , int : Int
    }


type CollabStateMode
    = CollabActive String
    | CollabEditing String


type alias ViewState =
    { activePast : List String
    , descendants : List String
    , ancestors : List String
    , viewMode : ViewMode
    , searchField : Maybe String
    , dragModel : DragExternalModel
    , collaborators : List Collaborator
    }


type alias TextCursorInfo =
    { selected : Bool, position : CursorPosition, text : ( String, String ) }


type CursorPosition
    = Start
    | End
    | Empty
    | Other
