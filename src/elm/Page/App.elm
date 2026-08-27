port module Page.App exposing (Model, Msg, getTitle, init, isDirty, navKey, notFound, subscriptions, toGlobalData, toSession, update, updateSession, view)

import Ant.Icons.Svg as AntIcons
import Browser.Dom exposing (Element)
import Browser.Navigation as Nav
import Bytes exposing (Bytes)
import Coders exposing (sortByEncoder)
import Doc.Data as Data
import Doc.History as History
import Doc.List as DocList exposing (Model(..))
import Doc.Metadata as Metadata exposing (Metadata)
import Doc.Switcher
import Doc.TreeStructure as TreeStructure exposing (defaultTree)
import Doc.UI as UI
import Feature
import Features exposing (Feature(..))
import File exposing (File)
import File.Download as Download
import File.Select as Select
import GlobalData exposing (GlobalData)
import Html exposing (Html, br, button, div, fieldset, h2, h3, input, label, li, node, p, small, strong, ul)
import Html.Attributes exposing (attribute, checked, class, classList, height, id, style, type_, width)
import Html.Events exposing (on, onClick, onInput)
import Html.Extra exposing (viewIf)
import Html.Lazy exposing (lazy5)
import Http
import Import.Incoming
import Import.Single
import Json.Decode as Json exposing (decodeValue, errorToString)
import Json.Encode as Enc
import Outgoing exposing (Msg(..), send)
import Page.Doc exposing (Msg(..), MsgToParent(..))
import Page.Doc.Export as Export exposing (ExportFormat(..), ExportSelection(..), exportView, exportViewError)
import Page.Doc.Incoming as Incoming exposing (Msg(..))
import Page.Doc.Theme exposing (Theme(..), applyTheme)
import Page.DocMessage
import RandomId
import Route
import Session exposing (LoggedIn, PaymentStatus(..), Session(..))
import SharedUI exposing (ctrlOrCmdText)
import Svg.Attributes
import Task
import Time
import Toast
import Translation exposing (TranslationId(..), tr)
import Types exposing (CardTreeOp(..), ConflictSelection(..), OutsideData, SortBy(..), Toast, ToastPersistence(..), ToastRole(..), TooltipPosition, Tree, ViewMode(..))
import UI.Header exposing (HeaderMenuState(..), viewHeader)
import UI.Sidebar exposing (SidebarMenuState(..), SidebarState(..), viewSidebar)
import Upgrade exposing (Msg(..))
import Utils exposing (delay, ternary)



-- MODEL


type alias Model =
    { loading : Bool
    , documentState : DocumentState
    , conflictViewerState : ConflictViewerState
    , sidebarState : SidebarState
    , sidebarMenuState : SidebarMenuState
    , headerMenu : HeaderMenuState
    , exportSettings : ( ExportSelection, ExportFormat )
    , modalState : ModalState
    , tray : Toast.Tray Toast
    , errorState : Bool
    , tooltip : Maybe ( Element, TooltipPosition, TranslationId )
    , fileSearchField : String -- TODO: not needed if switcher isn't open
    , theme : Theme
    , navKey : Nav.Key
    }


type DocumentState
    = Empty GlobalData LoggedIn
    | Doc DocState
    | DocNotFound GlobalData LoggedIn


type alias DocState =
    { session : LoggedIn
    , docId : String
    , docModel : Page.Doc.Model
    , data : Data.Model
    , lastRemoteSave : Maybe Time.Posix
    , lastLocalSave : Maybe Time.Posix
    , titleField : Maybe String
    }


type ConflictViewerState
    = NoConflict
    | Conflict ConflictSelection


type alias DbData =
    { dbName : String, isNew : Bool }


type ModalState
    = NoModal
    | FileSwitcher Doc.Switcher.Model
    | SidebarContextMenu String ( Float, Float )
    | TemplateSelector
    | HelpScreen
    | Wordcount Page.Doc.Model
    | UpgradeModal


defaultModel : Nav.Key -> LoggedIn -> DocumentState -> Model
defaultModel nKey session newDocState =
    { loading = True
    , documentState = newDocState
    , sidebarState =
        if Session.fileMenuOpen session then
            File

        else
            SidebarClosed
    , conflictViewerState = NoConflict
    , sidebarMenuState = NoSidebarMenu
    , headerMenu = NoHeaderMenu
    , exportSettings = ( ExportEverything, DOCX )
    , modalState = NoModal
    , tray = Toast.tray
    , errorState = False
    , tooltip = Nothing
    , fileSearchField = ""
    , theme = Default
    , navKey = nKey
    }


init : Nav.Key -> GlobalData -> LoggedIn -> Maybe DbData -> ( Model, Cmd Msg )
init nKey globalData session dbData_ =
    case dbData_ of
        Just dbData ->
            if dbData.isNew then
                ( defaultModel nKey
                    session
                    (Doc
                        { session = session
                        , docId = dbData.dbName
                        , docModel = Page.Doc.init True globalData
                        , data = Data.emptyCardBased
                        , lastRemoteSave = Nothing
                        , lastLocalSave = Just (GlobalData.currentTime globalData)
                        , titleField = Session.getDocName session dbData.dbName
                        }
                    )
                , Cmd.batch
                    [ send <| InitDocument dbData.dbName
                    , Task.attempt (always NoOp) (Browser.Dom.focus "card-edit-1")
                    ]
                )
                    |> setBlock Nothing

            else
                ( defaultModel nKey
                    session
                    (Doc
                        { session = session
                        , docId = dbData.dbName
                        , docModel = Page.Doc.init False globalData
                        , data = Data.emptyCardBased
                        , lastRemoteSave = Nothing
                        , lastLocalSave = Nothing
                        , titleField = Session.getDocName session dbData.dbName
                        }
                    )
                , send <| LoadDocument dbData.dbName
                )
                    |> setBlock Nothing

        Nothing ->
            case Session.lastDocId session of
                Just docId ->
                    ( defaultModel nKey session (Empty globalData session), Route.replaceUrl nKey (Route.DocUntitled docId) )

                Nothing ->
                    let
                        ( isLoading, maybeGetDocs ) =
                            case Session.documents session of
                                Success [] ->
                                    ( False, Cmd.none )

                                Success _ ->
                                    ( True, Cmd.none )

                                _ ->
                                    ( True, send <| GetDocumentList )

                        newModel =
                            defaultModel nKey session (Empty globalData session)
                                |> (\m -> { m | loading = isLoading })
                    in
                    ( newModel, maybeGetDocs )


notFound : Nav.Key -> GlobalData -> LoggedIn -> ( Model, Cmd Msg )
notFound nKey globalData session =
    ( defaultModel nKey session (DocNotFound globalData session), Cmd.none )


isDirty : Model -> Bool
isDirty model =
    case model.documentState of
        Doc { docModel } ->
            Page.Doc.isDirty docModel

        Empty _ _ ->
            False

        DocNotFound _ _ ->
            False


getTitle : Model -> Maybe String
getTitle model =
    case model.documentState of
        Doc { session, docId } ->
            Session.getDocName session docId

        Empty _ _ ->
            Nothing

        DocNotFound _ _ ->
            Nothing


toLoggedInSession : Model -> LoggedIn
toLoggedInSession { documentState } =
    case documentState of
        Doc { session } ->
            session

        Empty _ session ->
            session

        DocNotFound _ session ->
            session


toSession : Model -> Session
toSession { documentState } =
    case documentState of
        Doc { session } ->
            session |> LoggedInSession

        Empty _ session ->
            session |> LoggedInSession

        DocNotFound _ session ->
            session |> LoggedInSession


navKey : Model -> Nav.Key
navKey model =
    model.navKey


toGlobalData : Model -> GlobalData
toGlobalData { documentState } =
    case documentState of
        Doc { docModel } ->
            Page.Doc.getGlobalData docModel

        Empty gData _ ->
            gData

        DocNotFound gData _ ->
            gData


updateSession : LoggedIn -> Model -> Model
updateSession newSession ({ documentState } as model) =
    case documentState of
        Doc docState ->
            { model | documentState = Doc { docState | session = newSession } }

        Empty globalData _ ->
            { model | documentState = Empty globalData newSession }

        DocNotFound globalData _ ->
            { model | documentState = DocNotFound globalData newSession }


updateGlobalData : GlobalData -> Model -> Model
updateGlobalData newGlobalData ({ documentState } as model) =
    case documentState of
        Doc ({ docModel } as docState) ->
            { model | documentState = Doc { docState | docModel = Page.Doc.setGlobalData newGlobalData docModel } }

        Empty _ session ->
            { model | documentState = Empty newGlobalData session }

        DocNotFound _ session ->
            { model | documentState = DocNotFound newGlobalData session }



-- UPDATE


type Msg
    = NoOp
    | GotDocMsg Page.Doc.Msg
    | TimeUpdate Time.Posix
    | SettingsChanged Json.Value
    | LogoutRequested
    | IncomingAppMsg IncomingAppMsg
    | IncomingDocMsg Incoming.Msg
    | LogErr String
      -- Conflicts
    | ConflictVersionSelected ConflictSelection
    | ConflictResolved
      -- Sidebar
    | TemplateSelectorOpened
    | SortByChanged SortBy
    | SidebarStateChanged SidebarState
    | SidebarContextClicked String ( Float, Float )
    | DeleteDoc String
    | ReceivedDocuments DocList.Model
    | SwitcherOpened
    | SwitcherClosed
      -- HEADER: Title
    | TitleFocused
    | TitleFieldChanged String
    | TitleEdited
    | TitleEditCanceled
      -- Collab
      -- HEADER: Settings
    | DocSettingsToggled Bool
    | ThemeChanged Theme
      -- HEADER: History
    | HistoryToggled Bool
    | CheckoutVersion String
    | Restore
    | CancelHistory
      -- HEADER: Export & Print
    | ExportPreviewToggled Bool
    | ExportSelectionChanged ExportSelection
    | ExportFormatChanged ExportFormat
    | Export
    | Exported String (Result Http.Error Bytes)
    | PrintRequested
      -- HELP Modal
    | ToggledHelpMenu
    | ClickedShowVideos
    | CopyEmailClicked Bool
      -- Account menu
    | ToggledAccountMenu Bool
      -- Import
    | ImportJSONLoaded String String
    | ImportJSONIdGenerated Tree String String
    | ImportSingleCompleted String
      -- Misc UI
    | ToastMsg Toast.Msg
    | AddToast ToastPersistence Toast
    | CloseEmailConfirmBanner
    | ToggledUpgradeModal Bool
    | UpgradeModalMsg Upgrade.Msg
    | ToggledShortcutTray
    | WordcountModalOpened
    | FileSearchChanged String
    | TooltipRequested String TooltipPosition TranslationId
    | TooltipReceived Element TooltipPosition TranslationId
    | TooltipClosed
    | EmptyMessage
    | ModalClosed


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        session =
            toLoggedInSession model

        globalData =
            toGlobalData model
    in
    case msg of
        NoOp ->
            ( model, Cmd.none )

        GotDocMsg docMsg ->
            case model.documentState of
                Doc ({ docModel } as docState) ->
                    let
                        ( newDocModel, newCmd, parentMsgs ) =
                            Page.Doc.opaqueUpdate docMsg docModel
                                |> (\( m, c, p ) -> ( m, Cmd.map GotDocMsg c, p ))
                    in
                    ( { model | documentState = Doc { docState | docModel = newDocModel } }, newCmd )
                        |> applyParentMsgs parentMsgs

                Empty _ _ ->
                    ( model, Cmd.none )

                DocNotFound _ _ ->
                    ( model, Cmd.none )

        TimeUpdate time ->
            ( model |> updateGlobalData (GlobalData.updateTime time globalData)
            , Cmd.none
            )

        SettingsChanged json ->
            ( model |> updateSession (Session.sync json (GlobalData.currentTime globalData) session), Cmd.none )
                |> setBlock Nothing

        LogoutRequested ->
            ( model, Session.logout )

        IncomingAppMsg appMsg ->
            case appMsg of
                MetadataUpdate metadata ->
                    case model.documentState of
                        Doc docState ->
                            if Metadata.getDocId metadata == docState.docId then
                                ( { model | documentState = Doc { docState | titleField = Metadata.getDocName metadata } }, Cmd.none )

                            else
                                ( model, Cmd.none )

                        Empty _ _ ->
                            ( model, Cmd.none )

                        DocNotFound _ _ ->
                            ( model, Cmd.none )

                CardDataReceived json ->
                    cardDataReceived json model

                HistoryDataReceived json ->
                    historyReceived json model

                PushOk chkStrings ->
                    case model.documentState of
                        Doc { data } ->
                            let
                                pushOkMsgs =
                                    Data.pushOkHandler chkStrings data
                                        |> Maybe.map send
                                        |> Maybe.withDefault Cmd.none

                                ( newToastTray, newToastCmd ) =
                                    if model.errorState then
                                        model.tray
                                            |> Toast.filter
                                                (\toast ->
                                                    case toast.role of
                                                        Error ->
                                                            False

                                                        _ ->
                                                            True
                                                )
                                            |> (\newTray ->
                                                    ( newTray
                                                    , delay 0
                                                        (AddToast Temporary
                                                            (Toast SuccessToast "Sync successful")
                                                        )
                                                    )
                                               )

                                    else
                                        ( model.tray
                                        , Cmd.none
                                        )
                            in
                            ( { model | tray = newToastTray, errorState = False }
                            , Cmd.batch [ pushOkMsgs, newToastCmd ]
                            )

                        Empty _ _ ->
                            ( model, Cmd.none )

                        DocNotFound _ _ ->
                            ( model, Cmd.none )

                PushError ->
                    case model.documentState of
                        Doc { data, docId } ->
                            let
                                maybePush =
                                    Data.triggeredPush data docId
                            in
                            ( model, List.map send maybePush |> Cmd.batch )

                        Empty _ _ ->
                            ( model, Cmd.none )

                        DocNotFound _ _ ->
                            ( model, Cmd.none )


                SocketConnected ->
                    case model.documentState of
                        Doc { data, docId } ->
                            let
                                maybePush =
                                    Data.triggeredPush data docId
                            in
                            ( model
                            , List.map send maybePush |> Cmd.batch
                            )

                        Empty _ _ ->
                            ( model, Cmd.none )

                        DocNotFound _ _ ->
                            ( model, Cmd.none )

                SavedRemotely saveTime ->
                    case model.documentState of
                        Doc docState ->
                            ( { model | documentState = Doc { docState | lastRemoteSave = Just saveTime } }, Cmd.none )

                        Empty _ _ ->
                            ( model, Cmd.none )

                        DocNotFound _ _ ->
                            ( model, Cmd.none )

                ErrorAlert alertMsg ->
                    ( { model | errorState = True }, delay 0 (AddToast Persistent (Toast Error alertMsg)) )

                NotFound dbName ->
                    ( model, Route.pushUrl model.navKey (Route.NotFound dbName) )

        IncomingDocMsg incomingMsg ->
            let
                doNothing =
                    ( model, Cmd.none )

                passThroughTo docState =
                    Page.Doc.opaqueIncoming incomingMsg docState.docModel
                        |> (\( d, c, p ) ->
                                ( { model | documentState = Doc { docState | docModel = d } }, Cmd.map GotDocMsg c )
                                    |> applyParentMsgs p
                           )
            in
            case ( incomingMsg, model.documentState ) of
                ( Keyboard shortcut, Doc ({ docId, docModel } as docState) ) ->
                    case model.modalState of
                        FileSwitcher switcherModel ->
                            case shortcut of
                                "enter" ->
                                    case switcherModel.selectedDocument of
                                        Just selectedDocId ->
                                            ( model, Route.pushUrl model.navKey (Route.DocUntitled selectedDocId) )

                                        Nothing ->
                                            ( model, Cmd.none )

                                "down" ->
                                    ( { model | modalState = FileSwitcher (Doc.Switcher.down switcherModel) }, Cmd.none )

                                "up" ->
                                    ( { model | modalState = FileSwitcher (Doc.Switcher.up switcherModel) }, Cmd.none )

                                "mod+o" ->
                                    ( { model | modalState = NoModal }, Cmd.none )

                                "esc" ->
                                    ( { model | fileSearchField = "", modalState = NoModal }, Cmd.none )

                                _ ->
                                    ( model, Cmd.none )

                        Wordcount _ ->
                            case shortcut of
                                "w" ->
                                    ( { model | modalState = NoModal }, Cmd.none )

                                "mod+o" ->
                                    normalMode docModel
                                        (model |> openSwitcher docId)
                                        (passThroughTo docState)

                                "esc" ->
                                    ( { model | modalState = NoModal }, Cmd.none )

                                _ ->
                                    ( model, Cmd.none )

                        HelpScreen ->
                            case shortcut of
                                "?" ->
                                    ( { model | modalState = NoModal }, Cmd.none )

                                "mod+o" ->
                                    normalMode docModel
                                        (model |> openSwitcher docId)
                                        (passThroughTo docState)

                                "esc" ->
                                    ( { model | modalState = NoModal }, Cmd.none )

                                _ ->
                                    ( model, Cmd.none )

                        NoModal ->
                            case shortcut of
                                "w" ->
                                    normalMode docModel
                                        ( { model | modalState = Wordcount docModel }, Cmd.none )
                                        (passThroughTo docState)

                                "?" ->
                                    normalMode docModel
                                        ( { model | modalState = HelpScreen }, Cmd.none )
                                        (passThroughTo docState)

                                "mod+o" ->
                                    normalMode docModel
                                        (model |> openSwitcher docId)
                                        (passThroughTo docState)

                                "mod+z" ->
                                    normalMode docModel
                                        (toggleHistory True -1 model)
                                        (passThroughTo docState)

                                "mod+shift+z" ->
                                    normalMode docModel
                                        (toggleHistory True 1 model)
                                        (passThroughTo docState)

                                _ ->
                                    passThroughTo docState

                        _ ->
                            case shortcut of
                                "esc" ->
                                    ( { model | modalState = NoModal }, Cmd.none )

                                "mod+o" ->
                                    normalMode docModel
                                        (model |> openSwitcher docId)
                                        (passThroughTo docState)

                                _ ->
                                    passThroughTo docState

                ( WillPrint, Doc _ ) ->
                    ( { model | headerMenu = ExportPreview }, Cmd.none )

                ( _, Doc docState ) ->
                    passThroughTo docState

                _ ->
                    doNothing

        LogErr err ->
            ( model
            , send (ConsoleLogRequested err)
            )

        -- Conflicts
        ConflictVersionSelected newSel ->
            case model.documentState of
                Doc ({ docModel, data } as docState) ->
                    case Data.conflictToTree data newSel of
                        Just newTree ->
                            let
                                oldWorkingTree =
                                    Page.Doc.getWorkingTree docModel

                                newWorkingTree =
                                    TreeStructure.setTree newTree oldWorkingTree

                                newDocModel =
                                    Page.Doc.setWorkingTree newWorkingTree docModel
                            in
                            ( { model | documentState = Doc { docState | docModel = newDocModel }, conflictViewerState = Conflict newSel }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Empty _ _ ->
                    ( model, Cmd.none )

                DocNotFound _ _ ->
                    ( model, Cmd.none )

        ConflictResolved ->
            case ( model.documentState, model.conflictViewerState ) of
                ( Doc { data }, Conflict selectedVersion ) ->
                    let
                        outMsg_ =
                            Data.resolveConflicts selectedVersion data
                    in
                    ( model
                    , Maybe.map send outMsg_ |> Maybe.withDefault Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        -- Sidebar
        TemplateSelectorOpened ->
            ( { model | modalState = TemplateSelector }, Cmd.none )

        SortByChanged newSort ->
            let
                newSession =
                    Session.setSortBy newSort session
            in
            ( model |> updateSession newSession, send <| SaveUserSetting ( "sortBy", sortByEncoder newSort ) )

        SidebarStateChanged newSidebarState ->
            let
                ( newSessionData, maybeSaveSidebarState ) =
                    case newSidebarState of
                        File ->
                            ( Session.setFileOpen True session, send <| SetSidebarState True )

                        _ ->
                            ( Session.setFileOpen True session, send <| SetSidebarState False )

                newDropdownState =
                    case ( newSidebarState, model.sidebarMenuState ) of
                        ( File, Account _ ) ->
                            NoSidebarMenu

                        _ ->
                            model.sidebarMenuState
            in
            ( { model
                | sidebarState = newSidebarState
                , tooltip = Nothing
                , sidebarMenuState = newDropdownState
              }
                |> updateSession newSessionData
            , maybeSaveSidebarState
            )

        SidebarContextClicked docId ( x, y ) ->
            ( { model | modalState = SidebarContextMenu docId ( x, y ) }, Cmd.none )

        DeleteDoc docId ->
            let
                docName_ =
                    Session.getDocName session docId
            in
            ( { model | modalState = NoModal }, send <| RequestDelete docId docName_ )

        ReceivedDocuments newListState ->
            let
                newSession =
                    Session.updateDocuments newListState session

                ( routeCmd, isLoading ) =
                    case ( model.documentState, Session.documents newSession ) of
                        ( Doc { docId }, Success docList ) ->
                            ( docList
                                |> List.map (\d -> Metadata.getDocId d == docId)
                                |> List.any identity
                                |> (\docStillExists ->
                                        if docStillExists then
                                            Cmd.none

                                        else
                                            Route.replaceUrl model.navKey Route.Root
                                   )
                            , True
                            )

                        ( Empty _ _, Success [] ) ->
                            ( Cmd.none, False )

                        ( Empty _ _, Success docList ) ->
                            ( DocList.getLastUpdated (Success docList)
                                |> Maybe.map (\s -> Route.replaceUrl model.navKey (Route.DocUntitled s))
                                |> Maybe.withDefault Cmd.none
                            , True
                            )

                        _ ->
                            ( Cmd.none, True )

                maybeUpdateTitleField m =
                    case m.documentState of
                        Doc ({ docId } as docState) ->
                            case Session.getDocName session docId of
                                Just docName ->
                                    ( { m | documentState = Doc { docState | titleField = Just docName } }, Cmd.none )

                                Nothing ->
                                    ( m, Cmd.none )

                        _ ->
                            ( m, Cmd.none )
            in
            ( { model | loading = isLoading } |> updateSession newSession, routeCmd )
                |> andThen maybeUpdateTitleField

        SwitcherOpened ->
            case model.documentState of
                Doc { docId } ->
                    openSwitcher docId model

                Empty _ _ ->
                    ( model, Cmd.none )

                DocNotFound _ _ ->
                    ( model, Cmd.none )

        SwitcherClosed ->
            closeSwitcher model

        -- Header
        TitleFocused ->
            case model.documentState of
                Doc { titleField } ->
                    case titleField of
                        Nothing ->
                            ( model, send <| SelectAll "title-rename" )

                        Just _ ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        TitleFieldChanged newTitle ->
            case model.documentState of
                Doc docState ->
                    ( { model | documentState = Doc { docState | titleField = Just newTitle } }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        TitleEdited ->
            case model.documentState of
                Doc { titleField, docId } ->
                    case titleField of
                        Just editedTitle ->
                            if String.trim editedTitle == "" then
                                ( model
                                , Cmd.batch
                                    [ delay 0
                                        (AddToast Temporary
                                            { message = "Title cannot be blank"
                                            , role = Info
                                            }
                                        )
                                    , Task.attempt (always NoOp) (Browser.Dom.focus "title-rename")
                                    ]
                                )

                            else if Just editedTitle /= Session.getDocName session docId then
                                ( model, Cmd.batch [ send <| RenameDocument editedTitle, Task.attempt (always NoOp) (Browser.Dom.blur "title-rename") ] )

                            else
                                ( model, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        TitleEditCanceled ->
            case model.documentState of
                Doc ({ docId } as docState) ->
                    ( { model | documentState = Doc { docState | titleField = Session.getDocName session docId } }
                    , Task.attempt (always NoOp) (Browser.Dom.blur "title-rename")
                    )

                _ ->
                    ( model, Cmd.none )

        HistoryToggled shouldOpen ->
            model |> toggleHistory shouldOpen 0

        CheckoutVersion versionId ->
            case ( model.headerMenu, model.documentState ) of
                ( HistoryView history, Doc docState ) ->
                    let
                        version_ =
                            History.checkoutVersion versionId history
                    in
                    case version_ of
                        Just ( newHistory, newTree ) ->
                            let
                                ( newDocModel, newDocCmd ) =
                                    Page.Doc.setTree newTree docState.docModel
                                        |> (\( m, _, _ ) -> m)
                                        |> Page.Doc.maybeActivate
                            in
                            ( { model
                                | headerMenu = HistoryView newHistory
                                , documentState =
                                    Doc
                                        { docState
                                            | docModel = newDocModel
                                        }
                              }
                            , Cmd.map GotDocMsg newDocCmd
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Restore ->
            case ( model.headerMenu, model.documentState ) of
                ( HistoryView history, Doc docState ) ->
                    let
                        outMsgs =
                            History.getCurrentVersionId history
                                |> Maybe.map (Data.restore docState.data)
                                |> Maybe.withDefault []

                    in
                    if List.length outMsgs > 0 then
                        model
                            |> toggleHistory False 0
                            |> (\( m, c ) -> ( m, Cmd.batch <| c :: List.map send outMsgs ))

                    else
                        model
                            |> toggleHistory False 0

                _ ->
                    ( model, Cmd.none )

        CancelHistory ->
            case ( model.headerMenu, model.documentState ) of
                ( HistoryView historyState, Doc docState ) ->
                    let
                        revertTree_ =
                            History.revert historyState
                    in
                    case revertTree_ of
                        Just revertTree ->
                            let
                                ( newDocModel, docCmds, _ ) =
                                    Page.Doc.setTree revertTree docState.docModel
                            in
                            ( { model
                                | documentState = Doc { docState | docModel = newDocModel }
                                , headerMenu = NoHeaderMenu
                              }
                            , Cmd.map GotDocMsg docCmds
                            )
                                |> setBlock Nothing

                        Nothing ->
                            ( { model | headerMenu = NoHeaderMenu }
                            , Cmd.none
                            )
                                |> setBlock Nothing

                _ ->
                    ( model
                    , Cmd.none
                    )

        Export ->
            case model.documentState of
                Doc { docId, docModel } ->
                    let
                        workingTree =
                            Page.Doc.getWorkingTree docModel

                        activeTree =
                            Page.Doc.getActiveTree docModel
                                |> Maybe.withDefault workingTree.tree
                    in
                    ( model
                    , Export.command
                        Exported
                        docId
                        (Session.getDocName session docId |> Maybe.withDefault "Untitled")
                        model.exportSettings
                        activeTree
                        workingTree.tree
                    )

                _ ->
                    ( model, Cmd.none )

        Exported docName (Ok bytes) ->
            let
                mime =
                    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

                filename =
                    docName ++ ".docx"
            in
            ( model, Download.bytes filename mime bytes )

        Exported _ (Err _) ->
            ( model, Cmd.none )

        PrintRequested ->
            ( model, send <| Print )

        DocSettingsToggled isOpen ->
            ( { model
                | headerMenu =
                    if isOpen then
                        Settings

                    else
                        NoHeaderMenu
              }
            , Cmd.none
            )

        ThemeChanged newTheme ->
            ( { model | theme = newTheme }, send <| SaveThemeSetting newTheme )

        ExportPreviewToggled previewEnabled ->
            ( { model
                | headerMenu =
                    if previewEnabled then
                        ExportPreview

                    else
                        NoHeaderMenu
              }
            , Cmd.none
            )

        -- TODO: |> activate vs.active True
        ExportSelectionChanged expSel ->
            ( { model | exportSettings = Tuple.mapFirst (always expSel) model.exportSettings }, Cmd.none )

        ExportFormatChanged expFormat ->
            ( { model | exportSettings = Tuple.mapSecond (always expFormat) model.exportSettings }, Cmd.none )

        -- HELP Modal
        ToggledHelpMenu ->
            ( { model | modalState = HelpScreen }, Cmd.none )

        ClickedShowVideos ->
            ( model, Cmd.none )

        CopyEmailClicked isUrgent ->
            if isUrgent then
                ( model, send <| CopyToClipboard "{%SUPPORT_URGENT_EMAIL%}" "#email-copy-btn" )

            else
                ( model, send <| CopyToClipboard "{%SUPPORT_EMAIL%}" "#email-copy-btn" )

        -- Account menu TODO
        ToggledAccountMenu isOpen ->
            let
                ( newDropdownState, newSidebarState ) =
                    if isOpen then
                        ( Account Nothing, SidebarClosed )

                    else
                        ( NoSidebarMenu, model.sidebarState )
            in
            ( { model
                | sidebarMenuState = newDropdownState
                , sidebarState = newSidebarState
                , tooltip = Nothing
              }
            , Cmd.none
            )

        -- Import
        ImportJSONLoaded fileName jsonString ->
            let
                ( importTreeDecoder, newSeed ) =
                    Import.Single.decoder (GlobalData.seed globalData)

                newGlobalData =
                    GlobalData.setSeed newSeed globalData

                copyName =
                    fileName
                        |> Session.copyNaming session
            in
            case Json.decodeString importTreeDecoder jsonString of
                Ok tree ->
                    ( { model | loading = True } |> updateGlobalData newGlobalData
                    , RandomId.generate (ImportJSONIdGenerated tree copyName)
                    )

                Err _ ->
                    ( model |> updateGlobalData newGlobalData, Cmd.none )

        ImportJSONIdGenerated tree fileName docId ->
            let
                cardData =
                    Data.importTree docId tree
            in
            ( model
            , Cmd.batch
                [ send <| SaveCardBased cardData
                , send <| SaveImportedTree ( docId, fileName )
                ]
            )

        ImportSingleCompleted docId ->
            ( model, Route.pushUrl model.navKey (Route.DocUntitled docId) )

        -- Misc UI
        ToastMsg toastMsg ->
            let
                ( newToast, newCmd ) =
                    Toast.update toastMsg model.tray
            in
            ( { model | tray = newToast }, Cmd.map ToastMsg newCmd )

        AddToast persistence toast ->
            let
                ( toastUpdater, toastAdder ) =
                    case persistence of
                        Temporary ->
                            ( Toast.expireIn 3000
                            , Toast.add model.tray
                            )

                        Persistent ->
                            ( Toast.persistent
                            , Toast.addUnique model.tray
                            )
            in
            toastUpdater toast
                |> Toast.withExitTransition 900
                |> toastAdder
                |> Toast.tuple ToastMsg model

        CloseEmailConfirmBanner ->
            ( model |> updateSession (Session.confirmEmail (GlobalData.currentTime globalData) session), Cmd.none )

        ToggledUpgradeModal isOpen ->
            ( { model
                | modalState =
                    if isOpen then
                        UpgradeModal

                    else
                        NoModal
                , sidebarMenuState = NoSidebarMenu
              }
            , Cmd.none
            )

        UpgradeModalMsg upgradeModalMsg ->
            case upgradeModalMsg of
                UpgradeModalClosed ->
                    ( { model | modalState = NoModal }, Cmd.none )

                CheckoutClicked checkoutData ->
                    let
                        data =
                            Upgrade.toValue (Session.name session) checkoutData
                    in
                    ( model, send <| CheckoutButtonClicked data )

                _ ->
                    let
                        newSession =
                            Session.updateUpgrade upgradeModalMsg session

                        maybeFlash =
                            case upgradeModalMsg of
                                PlanChanged _ ->
                                    send <| FlashPrice

                                _ ->
                                    Cmd.none
                    in
                    ( model |> updateSession newSession, maybeFlash )

        ToggledShortcutTray ->
            let
                newIsOpen =
                    not <| Session.shortcutTrayOpen session

                newSession =
                    Session.setShortcutTrayOpen newIsOpen session
            in
            ( { model
                | headerMenu =
                    if model.headerMenu == ExportPreview && newIsOpen then
                        NoHeaderMenu

                    else
                        model.headerMenu
                , tooltip = Nothing
              }
                |> updateSession newSession
            , send <| SaveUserSetting ( "shortcutTrayOpen", Enc.bool newIsOpen )
            )

        WordcountModalOpened ->
            case model.documentState of
                Doc { docModel } ->
                    ( { model
                        | modalState = Wordcount docModel
                        , headerMenu = NoHeaderMenu
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        FileSearchChanged term ->
            let
                updatedModal =
                    case model.modalState of
                        FileSwitcher switcherModel ->
                            FileSwitcher (Doc.Switcher.search term switcherModel)

                        _ ->
                            model.modalState
            in
            ( { model | fileSearchField = term, modalState = updatedModal }, Cmd.none )

        TooltipRequested elId tipPos content ->
            ( model
            , Browser.Dom.getElement elId
                |> Task.attempt
                    (\result ->
                        case result of
                            Ok el ->
                                TooltipReceived el tipPos content

                            Err _ ->
                                NoOp
                    )
            )

        TooltipReceived el tipPos content ->
            ( { model | tooltip = Just ( el, tipPos, content ) }, Cmd.none )

        TooltipClosed ->
            ( { model | tooltip = Nothing }, Cmd.none )

        EmptyMessage ->
            ( model, send <| EmptyMessageShown )

        ModalClosed ->
            case model.modalState of
                _ ->
                    ( { model | modalState = NoModal }, Cmd.none )


andThen : (Model -> ( Model, Cmd Msg )) -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
andThen f ( model, prevCmd ) =
    let
        ( newModel, newCmd ) =
            f model
    in
    ( newModel, Cmd.batch [ prevCmd, newCmd ] )


cardDataReceived : Json.Value -> Model -> ( Model, Cmd Msg )
cardDataReceived dataIn model =
    case model.documentState of
        Doc ({ docModel, docId } as docState) ->
            let
                workingTree =
                    Page.Doc.getWorkingTree docModel

                tree =
                    workingTree.tree

                lastActives =
                    Json.decodeValue (Json.at [ "localStore", "last-actives" ] (Json.list Json.string)) dataIn
            in
            case Data.cardDataReceived dataIn ( docState.data, tree, docId ) of
                Just { newData, newTree, outMsg } ->
                    let
                        newWorkingTree =
                            TreeStructure.setTree newTree workingTree

                        ( newDocModel, newCmds ) =
                            docModel
                                |> Page.Doc.setWorkingTree newWorkingTree
                                |> Page.Doc.setLoading False
                                |> Page.Doc.setDirty False
                                |> Page.Doc.lastActives lastActives
                    in
                    ( { model
                        | documentState =
                            Doc
                                { docState
                                    | data = newData
                                    , docModel = newDocModel
                                    , lastLocalSave = Data.lastSavedTime newData |> Maybe.map Time.millisToPosix
                                    , lastRemoteSave = Data.lastSyncedTime newData |> Maybe.map Time.millisToPosix
                                }
                        , conflictViewerState =
                            if Data.hasConflicts newData then
                                Conflict Ours

                            else
                                NoConflict
                      }
                    , List.map send outMsg
                        ++ [ Cmd.map GotDocMsg newCmds ]
                        |> Cmd.batch
                    )

                Nothing ->
                    ( model, Cmd.none )

        Empty _ _ ->
            ( model, Cmd.none )

        DocNotFound _ _ ->
            ( model, Cmd.none )


historyReceived : Json.Value -> Model -> ( Model, Cmd Msg )
historyReceived dataIn model =
    case model.documentState of
        Doc ({ docModel } as docState) ->
            let
                newData =
                    Data.historyReceived dataIn docState.data
            in
            ( { model
                | documentState =
                    Doc
                        { docState
                            | data = newData
                        }
                , headerMenu =
                    case model.headerMenu of
                        HistoryView currentHistory ->
                            HistoryView (History.update newData currentHistory)

                        _ ->
                            model.headerMenu
              }
            , Cmd.none
            )

        Empty _ _ ->
            ( model, Cmd.none )

        DocNotFound _ _ ->
            ( model, Cmd.none )


applyParentMsgs : List MsgToParent -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
applyParentMsgs parentMsgs ( prevModel, prevCmd ) =
    List.foldl applyParentMsg ( prevModel, prevCmd ) parentMsgs


applyParentMsg : MsgToParent -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
applyParentMsg parentMsg ( prevModel, prevCmd ) =
    case parentMsg of
        ParentAddToast persistence toast ->
            ( prevModel, Cmd.batch [ delay 0 (AddToast persistence toast), prevCmd ] )

        CloseTooltip ->
            ( { prevModel | tooltip = Nothing }, prevCmd )

        LocalSave op ->
            ( prevModel, prevCmd )
                |> andThen (localSave op)



localSave : CardTreeOp -> Model -> ( Model, Cmd Msg )
localSave op model =
    case model.documentState of
        Doc { data, docId } ->
            let
                dbChangeList =
                    Data.localSave docId op data
            in
            ( model, send <| SaveCardBased dbChangeList )

        Empty _ _ ->
            ( model, Cmd.none )

        DocNotFound _ _ ->
            ( model, Cmd.none )


normalMode : Page.Doc.Model -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
normalMode docModel modified noOp =
    if Page.Doc.isNormalMode docModel then
        modified

    else
        noOp


openSwitcher : String -> Model -> ( Model, Cmd Msg )
openSwitcher docId model =
    let
        metadata_ =
            Session.getMetadata (toLoggedInSession model) docId
    in
    case metadata_ of
        Just currentMetadata ->
            ( { model
                | modalState =
                    FileSwitcher
                        { currentDocument = currentMetadata
                        , selectedDocument = Just docId
                        , searchField = ""
                        , docList = Session.documents (toLoggedInSession model)
                        }
              }
            , Task.attempt (\_ -> NoOp) (Browser.Dom.focus "switcher-input")
            )

        Nothing ->
            ( model, Cmd.none )


closeSwitcher : Model -> ( Model, Cmd Msg )
closeSwitcher model =
    ( { model | modalState = NoModal }, Cmd.none )


toggleHistory : Bool -> Int -> Model -> ( Model, Cmd Msg )
toggleHistory shouldOpen delta model =
    case ( shouldOpen, model.documentState ) of
        ( True, Doc ({ data, docModel } as docState) ) ->
            let
                ( newDocModel, newDocCmds ) =
                    Page.Doc.maybeActivate docModel
            in
            case model.headerMenu of
                HistoryView currentHistory ->
                    -- If we're already viewing history, just update the history
                    ( model, send <| HistorySlider False delta )

                _ ->
                    -- Otherwise, open the history
                    ( { model
                        | headerMenu = HistoryView (History.init (Page.Doc.getWorkingTree docModel).tree data)
                        , documentState = Doc { docState | docModel = newDocModel }
                      }
                    , Cmd.batch
                        [ send <| HistorySlider True delta
                        , Cmd.map GotDocMsg newDocCmds
                        ]
                    )
                        |> setBlock (Just "Cannot edit while viewing history.")

        ( False, _ ) ->
            ( { model | headerMenu = NoHeaderMenu }, Cmd.none ) |> setBlock Nothing

        _ ->
            ( { model | headerMenu = NoHeaderMenu }, Cmd.none )


setBlock : Maybe String -> ( Model, Cmd msg ) -> ( Model, Cmd msg )
setBlock block ( model, cmd ) =
    case model.documentState of
        Doc ({ docModel } as docState) ->
            case block of
                Just _ ->
                    ( { model
                        | documentState = Doc { docState | docModel = Page.Doc.setBlock block docModel }
                      }
                    , cmd
                    )

                Nothing ->
                    -- Reset to previous block state, depending on trial expiry
                    let
                        globalData =
                            toGlobalData model

                        currTime =
                            GlobalData.currentTime globalData

                        daysLeft =
                            Session.daysLeft currTime (toLoggedInSession model)
                                -- "Nothing" means "Customer", confusingly
                                |> Maybe.withDefault 9999

                        maybeBlock =
                            if daysLeft <= 0 then
                                Just (tr TrialExpired)

                            else
                                Nothing
                    in
                    ( { model
                        | documentState = Doc { docState | docModel = Page.Doc.setBlock maybeBlock docModel }
                      }
                    , cmd
                    )

        Empty _ _ ->
            ( model, cmd )

        DocNotFound _ _ ->
            ( model, cmd )



-- Translation Helper Function


text : TranslationId -> Html msg
text tid =
    Html.text <| tr tid


textNoTr : String -> Html msg
textNoTr str =
    Html.text str


emptyText : Html msg
emptyText =
    Html.text ""



-- VIEW


view : Model -> Html Msg
view ({ documentState } as model) =
    let
        session =
            toLoggedInSession model

        email =
            Session.name session

        viewTooltip =
            case model.tooltip of
                Just tooltip ->
                    UI.viewTooltip tooltip

                Nothing ->
                    emptyText

        sidebarMsgs =
            { sidebarStateChanged = SidebarStateChanged
            , noOp = NoOp
            , clickedNew = TemplateSelectorOpened
            , tooltipRequested = TooltipRequested
            , tooltipClosed = TooltipClosed
            , clickedSwitcher = SwitcherOpened
            , clickedHelp = ToggledHelpMenu
            , logout = LogoutRequested
            , fileSearchChanged = FileSearchChanged
            , changeSortBy = SortByChanged
            , contextMenuOpened = SidebarContextClicked
            }
    in
    case documentState of
        Doc { docModel, data, lastRemoteSave, lastLocalSave, titleField, docId } ->
            let
                workingTree =
                    Page.Doc.getWorkingTree docModel

                collaborators =
                    Page.Doc.getCollaborators docModel

                dirty =
                    Page.Doc.isDirty docModel

                isFullscreen =
                    Page.Doc.isFullscreen docModel

                globalData =
                    Page.Doc.getGlobalData docModel

                isOwner =
                    Session.isOwner session docId
            in
            if isFullscreen then
                div [ id "app-root", classList [ ( "loading", model.loading ) ], applyTheme model.theme ]
                    (Page.Doc.view
                        { docMsg = GotDocMsg
                        , keyboard = \s -> IncomingDocMsg (Keyboard s)
                        , tooltipRequested = TooltipRequested
                        , tooltipClosed = TooltipClosed
                        }
                        lastLocalSave
                        lastRemoteSave
                        docModel
                    )

            else
                let
                    activeTree_ =
                        Page.Doc.getActiveTree docModel

                    exportViewOk =
                        lazy5 exportView
                            { export = Export
                            , printRequested = PrintRequested
                            , tooltipRequested = TooltipRequested
                            , tooltipClosed = TooltipClosed
                            }
                            (Session.getDocName session docId |> Maybe.withDefault "Untitled")
                            model.exportSettings

                    maybeExportView =
                        case ( model.headerMenu, activeTree_, model.exportSettings ) of
                            ( ExportPreview, Just activeTree, _ ) ->
                                exportViewOk activeTree workingTree.tree

                            ( ExportPreview, Nothing, ( ExportEverything, _ ) ) ->
                                exportViewOk defaultTree workingTree.tree

                            ( ExportPreview, Nothing, _ ) ->
                                exportViewError "No card selected, cannot preview document"

                            _ ->
                                textNoTr ""
                in
                div [ id "app-root", classList [ ( "loading", model.loading ) ], applyTheme model.theme ]
                    (Page.Doc.view
                        { docMsg = GotDocMsg
                        , keyboard = \s -> IncomingDocMsg (Keyboard s)
                        , tooltipRequested = TooltipRequested
                        , tooltipClosed = TooltipClosed
                        }
                        lastLocalSave
                        lastRemoteSave
                        docModel
                        ++ [ UI.renderToast ToastMsg model.tray
                           , viewHeader
                                { noOp = NoOp
                                , titleFocused = TitleFocused
                                , titleFieldChanged = TitleFieldChanged
                                , titleEdited = TitleEdited
                                , titleEditCanceled = TitleEditCanceled
                                , tooltipRequested = TooltipRequested
                                , tooltipClosed = TooltipClosed
                                , toggledHistory = HistoryToggled
                                , checkoutTree = CheckoutVersion
                                , restore = Restore
                                , cancelHistory = CancelHistory
                                , toggledDocSettings = DocSettingsToggled (not <| model.headerMenu == Settings)
                                , wordCountClicked = WordcountModalOpened
                                , themeChanged = ThemeChanged
                                , toggledExport = ExportPreviewToggled (not <| model.headerMenu == ExportPreview)
                                , exportSelectionChanged = ExportSelectionChanged
                                , exportFormatChanged = ExportFormatChanged
                                , export = Export
                                , printRequested = PrintRequested
                                , toggledUpgradeModal = ToggledUpgradeModal
                                }
                                { session = session
                                , title_ = Session.getDocName session docId
                                , titleField_ = titleField
                                , headerMenu = model.headerMenu
                                , collaborators = collaborators
                                , isOwner = isOwner
                                , exportSettings = model.exportSettings
                                , data = data
                                , dirty = dirty
                                , lastLocalSave = lastLocalSave
                                , lastRemoteSave = lastRemoteSave
                                , globalData = globalData
                                }
                           , viewConflictSelector model.conflictViewerState
                           , maybeExportView
                           , viewSidebar globalData
                                session
                                sidebarMsgs
                                docId
                                (Session.sortBy session)
                                model.fileSearchField
                                (Session.documents session)
                                (Session.name session)
                                Nothing
                                model.sidebarMenuState
                                model.sidebarState
                           , viewIf (Session.isNotConfirmed session) (viewConfirmBanner CloseEmailConfirmBanner email)
                           , viewTooltip
                           ]
                        ++ UI.viewShortcuts
                            { toggledShortcutTray = ToggledShortcutTray
                            , tooltipRequested = TooltipRequested
                            , tooltipClosed = TooltipClosed
                            }
                            { isOpen = Session.shortcutTrayOpen session
                            , isMac = GlobalData.isMac globalData
                            , children = workingTree.tree.children
                            , textCursorInfo = Page.Doc.getTextCursorInfo docModel
                            , viewMode = Page.Doc.getViewMode docModel
                            }
                        ++ viewModal globalData session model.modalState
                    )

        Empty globalData _ ->
            if model.loading then
                UI.viewAppLoadingSpinner (Session.fileMenuOpen session)

            else
                div [ id "app-root", classList [ ( "loading", model.loading ) ] ]
                    (Page.DocMessage.viewEmpty { newClicked = TemplateSelectorOpened, emptyMessage = EmptyMessage }
                        ++ [ viewSidebar globalData
                                session
                                sidebarMsgs
                                ""
                                ModifiedAt
                                ""
                                (Session.documents session)
                                (Session.name session)
                                Nothing
                                model.sidebarMenuState
                                model.sidebarState
                           , viewIf (Session.isNotConfirmed session) (viewConfirmBanner CloseEmailConfirmBanner email)
                           , viewTooltip
                           ]
                        ++ viewModal globalData session model.modalState
                    )

        DocNotFound globalData _ ->
            div [ id "app-root" ]
                (Page.DocMessage.viewNotFound
                    ++ [ viewSidebar globalData
                            session
                            sidebarMsgs
                            ""
                            ModifiedAt
                            ""
                            (Session.documents session)
                            (Session.name session)
                            Nothing
                            model.sidebarMenuState
                            model.sidebarState
                       , viewIf (Session.isNotConfirmed session) (viewConfirmBanner CloseEmailConfirmBanner email)
                       , viewTooltip
                       ]
                    ++ viewModal globalData session model.modalState
                )


viewModal : GlobalData -> LoggedIn -> ModalState -> List (Html Msg)
viewModal globalData session modalState =
    let
        ctrlOrCmd =
            ctrlOrCmdText (GlobalData.isMac globalData)
    in
    case modalState of
        NoModal ->
            []

        FileSwitcher switcherModel ->
            -- Filtering, sorting and the up/down selection stay in
            -- Doc.Switcher; src/ui/switcher-modal.ts renders the result.
            [ node "gw-switcher-modal"
                [ attribute "docs" (Doc.Switcher.encodeDocs switcherModel |> Enc.encode 0)
                , attribute "current" (Doc.Switcher.currentId switcherModel)
                , attribute "selected" (Doc.Switcher.selectedId switcherModel)
                , on "gw-search" (Json.map FileSearchChanged (Json.at [ "detail" ] Json.string))
                , on "gw-close" (Json.succeed SwitcherClosed)
                ]
                []
            ]

        SidebarContextMenu docId ( x, y ) ->
            let
                isOwner =
                    Session.isOwner session docId
            in
            [ div [ onClick ModalClosed, id "sidebar-context-overlay" ] []
            , div
                [ id "sidebar-context-menu"
                , style "top" (String.fromFloat y ++ "px")
                , style "left" (String.fromFloat x ++ "px")
                ]
                -- "Duplicate" is gone with Page/Copy: it copied a legacy
                -- CouchDB database, so it hung on "Duplicating..." forever.
                [ if isOwner then
                    div [ onClick (DeleteDoc docId), class "context-menu-item" ]
                        [ AntIcons.deleteOutlined [ Svg.Attributes.class "icon" ], text DeleteDocument ]

                  else
                    textNoTr ""
                ]
            ]

        TemplateSelector ->
            -- Pure presentation: src/ui/template-modal.ts. Every tile is a
            -- link to a route Elm already owns, bar the JSON import action.
            [ node "gw-template-modal"
                [ on "gw-close" (Json.succeed ModalClosed)
                , on "gw-import-json"
                    (Json.map2 ImportJSONLoaded
                        (Json.at [ "detail", "name" ] Json.string)
                        (Json.at [ "detail", "text" ] Json.string)
                    )
                ]
                []
            ]

        HelpScreen ->
            -- Rendered by src/ui/help-modal.ts. Elm decides when it is on
            -- screen and passes the platform down; the element owns the rest
            -- and reports back with a bubbling "gw-close".
            [ node "gw-help-modal"
                [ attribute "platform" (ternary (GlobalData.isMac globalData) "mac" "other")
                , on "gw-close" (Json.succeed ModalClosed)
                ]
                []
            ]

        Wordcount docModel ->
            -- Counting stays in Elm (Doc.UI.getStats walks the tree); the table
            -- is rendered by src/ui/wordcount-modal.ts.
            [ node "gw-wordcount-modal"
                [ attribute "stats"
                    (UI.encodeStats
                        { activeCardId = Page.Doc.getActiveId docModel
                        , workingTree = Page.Doc.getWorkingTree docModel
                        , startingWordcount = 0
                        }
                        |> Enc.encode 0
                    )
                , on "gw-close" (Json.succeed ModalClosed)
                ]
                []
            ]

        UpgradeModal ->
            let
                daysLeft_ =
                    Session.daysLeft (GlobalData.currentTime globalData) session
            in
            Upgrade.view daysLeft_ (Session.upgradeModel session)
                |> List.map (Html.map UpgradeModalMsg)


viewConflictSelector : ConflictViewerState -> Html Msg
viewConflictSelector cstate =
    case cstate of
        NoConflict ->
            emptyText

        Conflict confSel ->
            div [ class "container mx-auto fixed flex z-10 justify-center top-7 drop-shadow-lg" ]
                [ div
                    [ class "bg-orange-400"
                    , style "z-index" "1000"
                    , style "color" "white"
                    , style "padding" "10px"
                    , style "border-radius" "5px"
                    ]
                    [ textNoTr "Conflicts detected. Choose a version to resolve the conflict."
                    , fieldset [ style "border" "none", style "display" "flex", style "flex-direction" "column" ]
                        [ radio "Local" (confSel == Ours) (ConflictVersionSelected Ours)
                        , radio "Cloud" (confSel == Theirs) (ConflictVersionSelected Theirs)
                        , radio "Original" (confSel == Original) (ConflictVersionSelected Original)
                        ]
                    , button
                        [ class "mt-4 bg-gray-200 text-black px-2 py-0.5 rounded"
                        , onClick ConflictResolved
                        ]
                        [ textNoTr "Choose this Version" ]
                    ]
                ]


radio : String -> Bool -> msg -> Html msg
radio value isChecked msg =
    label []
        [ input [ type_ "radio", onInput (always msg), checked isChecked ] []
        , textNoTr value
        ]


viewConfirmBanner : msg -> String -> Html msg
viewConfirmBanner closeMsg email =
    div [ id "email-confirm-banner", class "top-banner" ]
        [ AntIcons.warningOutlined [ width 16 ]
        , strong [] [ text ConfirmBannerStrong ]
        , textNoTr " "
        , text ConfirmBannerBody
        , textNoTr (email ++ " .")
        , AntIcons.closeCircleOutlined [ width 16, height 16, id "email-confirm-close-btn", onClick closeMsg ]
        ]



-- SUBSCRIPTIONS


type IncomingAppMsg
    = SocketConnected
    | CardDataReceived Enc.Value
    | HistoryDataReceived Enc.Value
    | PushOk (List String)
    | PushError
    | MetadataUpdate Metadata
    | SavedRemotely Time.Posix
    | ErrorAlert String
    | NotFound String


subscribe : (IncomingAppMsg -> msg) -> (String -> msg) -> Sub msg
subscribe tagger onError =
    appMsgs
        (\outsideInfo ->
            case outsideInfo.tag of
                "SocketConnected" ->
                    tagger <| SocketConnected

                "CardDataReceived" ->
                    tagger <| CardDataReceived outsideInfo.data

                "HistoryDataReceived" ->
                    tagger <| HistoryDataReceived outsideInfo.data

                "PushOk" ->
                    case decodeValue (Json.at [ "d" ] (Json.list Json.string)) outsideInfo.data of
                        Ok chks ->
                            tagger <| PushOk chks

                        Err err ->
                            onError (errorToString err)

                "PushError" ->
                    tagger PushError

                "MetadataUpdate" ->
                    case decodeValue Metadata.decoder outsideInfo.data of
                        Ok metadata ->
                            tagger (MetadataUpdate metadata)

                        Err err ->
                            onError (errorToString err)

                "SavedRemotely" ->
                    case decodeValue (Json.map Time.millisToPosix Json.int) outsideInfo.data of
                        Ok posix ->
                            tagger (SavedRemotely posix)

                        Err err ->
                            onError (errorToString err)

                "ErrorAlert" ->
                    case decodeValue Json.string outsideInfo.data of
                        Ok msg ->
                            tagger (ErrorAlert msg)

                        Err err ->
                            onError (errorToString err)

                "NotFound" ->
                    case decodeValue Json.string outsideInfo.data of
                        Ok docId ->
                            tagger (NotFound docId)

                        Err err ->
                            onError (errorToString err)

                _ ->
                    onError <| "Unexpected info from outside: " ++ outsideInfo.tag
        )


port appMsgs : (OutsideData -> msg) -> Sub msg


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ subscribe IncomingAppMsg LogErr
        , Incoming.subscribe IncomingDocMsg LogErr
        , Import.Incoming.importComplete
            (\docId_ ->
                case docId_ of
                    Just docId ->
                        ImportSingleCompleted docId

                    Nothing ->
                        NoOp
            )
        , case model.documentState of
            Doc { docModel } ->
                Page.Doc.subscriptions docModel |> Sub.map GotDocMsg

            _ ->
                Sub.none
        , DocList.subscribe ReceivedDocuments
        , Session.userSettingsChange SettingsChanged
        , case model.modalState of

            _ ->
                Sub.none
        , case model.modalState of

            _ ->
                Sub.none
        , Time.every (9 * 1000) TimeUpdate
        ]
