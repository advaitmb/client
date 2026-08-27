module Main exposing (main)

import AppUrl
import Browser exposing (Document)
import Browser.Navigation as Nav
import Dict
import Doc.UI as UI
import GlobalData exposing (GlobalData)
import Html
import Import.Template as Template
import Json.Decode as Dec exposing (Value)
import Outgoing exposing (Msg(..), send)
import Page.App
import Page.DocNew
import Page.Import
import Page.Login
import Page.Signup
import Route
import Session exposing (LoggedIn, Session(..))
import SharedUI
import Url exposing (Url)



-- MODEL


type alias WebSessionData =
    { globalData : GlobalData
    , session : LoggedIn
    , navKey : Nav.Key
    }


type Model
    = -- Logged Out Pages:
      Signup Page.Signup.Model
    | Login Page.Login.Model
      -- Logged In Pages:
    | Import Page.Import.Model
    | DocNew Page.DocNew.Model
    | App Page.App.Model
      -- Public Pages:


init : Value -> Url -> Nav.Key -> ( Model, Cmd Msg )
init json url navKey =
    let
        session =
            Session.decode json

        globalData =
            GlobalData.decode json

        ( initModel, _ ) =
            case session of
                LoggedInSession loggedInSession ->
                    Page.App.init navKey globalData loggedInSession Nothing |> updateWith App GotAppMsg

                GuestSession guestSession ->
                    Page.Login.init navKey globalData guestSession |> updateWith Login GotLoginMsg
    in
    handleUrlChange url initModel


replaceUrl : String -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
replaceUrl path ( model, cmd ) =
    ( model, Cmd.batch [ cmd, Nav.replaceUrl (getNavKey model) path ] )


handleUrlChange : Url -> Model -> ( Model, Cmd Msg )
handleUrlChange url model =
    let
        navKey =
            getNavKey model

        globalData =
            toGlobalData model

        appUrl =
            AppUrl.fromUrl url
    in
    case toSession model of
        LoggedInSession session ->
            case appUrl.path of
                [] ->
                    if loginInProgress model == Nothing then
                        Page.App.init navKey globalData session Nothing |> updateWith App GotAppMsg

                    else
                        ( model, Cmd.none )

                [ "new" ] ->
                    Page.DocNew.init navKey globalData session |> updateWith DocNew GotDocNewMsg

                [ "import", templateName ] ->
                    case Template.fromString templateName of
                        Just template ->
                            Page.Import.init navKey globalData session template
                                |> updateWith Import GotImportMsg

                        Nothing ->
                            Page.App.init navKey globalData session Nothing
                                |> updateWith App GotAppMsg

                [ "login" ] ->
                    ( model, Route.pushUrl navKey Route.Root )

                [ "signup" ] ->
                    ( model, Route.pushUrl navKey Route.Root )

                [ dbName ] ->
                    let
                        isNew =
                            case model of
                                DocNew _ ->
                                    True

                                _ ->
                                    False
                    in
                    Page.App.init navKey globalData session (Just { dbName = dbName, isNew = isNew })
                        |> updateWith App GotAppMsg

                [ dbName, "404-not-found" ] ->
                    Page.App.notFound navKey globalData session |> updateWith App GotAppMsg

                [ dbName, _ ] ->
                    ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        GuestSession guestSession ->
            case appUrl.path of
                [] ->
                    case loginInProgress model of
                        Just loggingIn ->
                            Page.App.init navKey globalData loggingIn Nothing |> updateWith App GotAppMsg

                        Nothing ->
                            Page.Signup.init navKey globalData guestSession
                                |> updateWith Signup GotSignupMsg
                                |> replaceUrl "signup"

                [ "login" ] ->
                    Page.Login.init navKey globalData guestSession |> updateWith Login GotLoginMsg

                [ "signup" ] ->
                    Page.Signup.init navKey globalData guestSession |> updateWith Signup GotSignupMsg

                [ "import", templateName ] ->
                    case loginInProgress model of
                        Just loggingIn ->
                            case Template.fromString templateName of
                                Just template ->
                                    Page.Import.init navKey globalData loggingIn template
                                        |> updateWith Import GotImportMsg

                                Nothing ->
                                    Page.App.init navKey globalData loggingIn Nothing
                                        |> updateWith App GotAppMsg

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )


loginInProgress : Model -> Maybe LoggedIn
loginInProgress model =
    case model of
        Signup signup ->
            Page.Signup.transition signup

        Login login ->
            Page.Login.transition login

        _ ->
            Nothing


toSession : Model -> Session
toSession model =
    case model of
        Signup signup ->
            Page.Signup.toSession signup

        Login login ->
            Page.Login.toSession login

        Import importModel ->
            Page.Import.toSession importModel

        DocNew docNew ->
            Page.DocNew.toSession docNew

        App appModel ->
            Page.App.toSession appModel

toGlobalData : Model -> GlobalData
toGlobalData model =
    case model of
        Signup signup ->
            Page.Signup.globalData signup

        Login login ->
            Page.Login.globalData login

        Import importModel ->
            importModel.globalData

        DocNew docNew ->
            docNew.globalData

        App appModel ->
            Page.App.toGlobalData appModel

getNavKey : Model -> Nav.Key
getNavKey model =
    case model of
        Signup signup ->
            Page.Signup.navKey signup

        Login login ->
            Page.Login.navKey login

        Import importModel ->
            importModel.navKey

        DocNew docNew ->
            docNew.navKey

        App appModel ->
            Page.App.navKey appModel

-- UPDATE


type Msg
    = ChangedUrl Url
    | ClickedLink Browser.UrlRequest
    | SettingsChanged Dec.Value
    | GotSignupMsg Page.Signup.Msg
    | GotLoginMsg Page.Login.Msg
    | GotImportMsg Page.Import.Msg
    | GotDocNewMsg Page.DocNew.Msg
    | GotAppMsg Page.App.Msg
    | UserLoggedOut


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        navKey =
            getNavKey model

        globalData =
            toGlobalData model
    in
    case ( msg, model ) of
        ( ChangedUrl url, _ ) ->
            handleUrlChange url model

        ( ClickedLink urlRequest, App appModel ) ->
            case urlRequest of
                Browser.Internal url ->
                    if Page.App.isDirty appModel then
                        ( model, send <| Alert (SharedUI.unsavedChangesAlert (GlobalData.isMac globalData)) )

                    else
                        ( model, Nav.pushUrl navKey (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        ( ClickedLink urlRequest, _ ) ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl navKey (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        ( GotSignupMsg signupMsg, Signup signupModel ) ->
            Page.Signup.update signupMsg signupModel
                |> updateWith Signup GotSignupMsg

        ( GotLoginMsg loginMsg, Login loginModel ) ->
            Page.Login.update loginMsg loginModel
                |> updateWith Login GotLoginMsg

        ( GotImportMsg homeMsg, Import homeModel ) ->
            Page.Import.update homeMsg homeModel
                |> updateWith Import GotImportMsg

        ( GotDocNewMsg docNewMsg, DocNew docNewModel ) ->
            Page.DocNew.update docNewMsg docNewModel
                |> updateWith DocNew GotDocNewMsg

        ( GotAppMsg appMsg, App appModel ) ->
            Page.App.update appMsg appModel
                |> updateWith App GotAppMsg

        ( UserLoggedOut, _ ) ->
            case toSession model of
                LoggedInSession session ->
                    Page.Login.init navKey globalData (Session.toGuest session)
                        |> updateWith Login GotLoginMsg
                        |> replaceUrl "/login"

                _ ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


updateWith : (subModel -> Model) -> (subMsg -> Msg) -> ( subModel, Cmd subMsg ) -> ( Model, Cmd Msg )
updateWith toModel toMsg ( subModel, subCmd ) =
    ( toModel subModel
    , Cmd.map toMsg subCmd
    )



-- VIEW


view : Model -> Document Msg
view model =
    case model of
        Signup signup ->
            { title = "Gingko Writer - Signup", body = [ Html.map GotSignupMsg (Page.Signup.view signup) ] }

        Login login ->
            { title = "Gingko Writer - Login", body = [ Html.map GotLoginMsg (Page.Login.view login) ] }

        Import importModel ->
            { title = "Importing...", body = [ UI.viewAppLoadingSpinner (Session.fileMenuOpen importModel.session) ] }

        DocNew _ ->
            { title = "Gingko Writer - New", body = [ Html.div [] [ Html.text "LOADING..." ] ] }

        App app ->
            let
                title =
                    case Page.App.getTitle app of
                        Just docTitle ->
                            docTitle ++ " - Gingko Writer"

                        Nothing ->
                            "Gingko Writer"
            in
            { title = title, body = [ Html.map GotAppMsg (Page.App.view app) ] }

-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    case model of
        Signup pageModel ->
            Sub.map GotSignupMsg (Page.Signup.subscriptions pageModel)

        Login pageModel ->
            Sub.map GotLoginMsg (Page.Login.subscriptions pageModel)

        Import pageModel ->
            Sub.map GotImportMsg (Page.Import.subscriptions pageModel)

        DocNew _ ->
            Sub.none

        App appModel ->
            Sub.map GotAppMsg (Page.App.subscriptions appModel)

globalSubscriptions : Model -> Sub Msg
globalSubscriptions model =
    Sub.batch
        [ subscriptions model
        , Session.userLoggedOut UserLoggedOut
        ]



-- MAIN


main : Program Value Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = globalSubscriptions
        , onUrlRequest = ClickedLink
        , onUrlChange = ChangedUrl
        }
