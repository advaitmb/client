module Main exposing (main)

import AppUrl
import Browser exposing (Document)
import Browser.Navigation as Nav
import Dict
import Doc.UI as UI
import GlobalData exposing (GlobalData)
import Html
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


{-| Boot: the URL the app was opened at decides the first page, and that page's
commands are the app's first commands. Anything less is E4 -- `init` used to
build a page from the session alone, throw its `Cmd` away, and hand the model
to `handleUrlChange`, which for half the URL shapes had nothing to add.
-}
init : Value -> Url -> Nav.Key -> ( Model, Cmd Msg )
init json url navKey =
    routeUrl
        { navKey = navKey
        , globalData = GlobalData.decode json
        , session = Session.decode json
        , fromNewDocument = False
        }
        url


handleUrlChange : Url -> Model -> ( Model, Cmd Msg )
handleUrlChange url model =
    routeUrl
        { navKey = getNavKey model
        , globalData = toGlobalData model
        , session =
            case ( toSession model, loginInProgress model ) of
                -- A login or signup that has just completed routes as the user
                -- it signed in: the auth page's own session is still a guest
                -- one until the redirect it triggered lands here.
                ( GuestSession _, Just loggingIn ) ->
                    LoggedInSession loggingIn

                ( session, _ ) ->
                    session
        , fromNewDocument =
            case model of
                DocNew _ ->
                    True

                _ ->
                    False
        }
        url


{-| Everything the routing decision needs that a URL does not carry.
-}
type alias Routing =
    { navKey : Nav.Key
    , globalData : GlobalData
    , session : Session
    , fromNewDocument : Bool
    }


{-| Carry out `Route`'s decision: initialize the page the URL names -- with its
commands -- and correct the address bar if the URL was not one this session can
be on.
-}
routeUrl : Routing -> Url -> ( Model, Cmd Msg )
routeUrl routing url =
    let
        appUrl =
            AppUrl.fromUrl url
    in
    case routing.session of
        LoggedInSession session ->
            Route.loggedInLanding { fromNewDocument = routing.fromNewDocument } appUrl
                |> applyLanding routing.navKey (loggedInPage routing session)

        GuestSession guestSession ->
            Route.guestLanding appUrl
                |> applyLanding routing.navKey (guestPage routing guestSession)


applyLanding : Nav.Key -> (page -> ( Model, Cmd Msg )) -> Route.Landing page -> ( Model, Cmd Msg )
applyLanding navKey toPage landing =
    case landing.urlCorrection of
        Just route ->
            toPage landing.page |> correctUrlTo navKey route

        Nothing ->
            toPage landing.page


correctUrlTo : Nav.Key -> Route.Route -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
correctUrlTo navKey route ( model, cmd ) =
    ( model, Cmd.batch [ cmd, Route.replaceUrl navKey route ] )


loggedInPage : Routing -> LoggedIn -> Route.LoggedInPage -> ( Model, Cmd Msg )
loggedInPage { navKey, globalData } session page =
    case page of
        Route.Home ->
            Page.App.init navKey globalData session Nothing |> updateWith App GotAppMsg

        Route.Document dbData ->
            Page.App.init navKey globalData session (Just dbData) |> updateWith App GotAppMsg

        Route.DocumentNotFound ->
            Page.App.notFound navKey globalData session |> updateWith App GotAppMsg

        Route.NewDocument ->
            Page.DocNew.init navKey globalData session |> updateWith DocNew GotDocNewMsg

        Route.ImportTemplate template ->
            Page.Import.init navKey globalData session template |> updateWith Import GotImportMsg


guestPage : Routing -> Session.Guest -> Route.GuestPage -> ( Model, Cmd Msg )
guestPage { navKey, globalData } guestSession page =
    case page of
        Route.LoginForm ->
            Page.Login.init navKey globalData guestSession |> updateWith Login GotLoginMsg

        Route.SignupForm ->
            Page.Signup.init navKey globalData guestSession |> updateWith Signup GotSignupMsg


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
                        |> correctUrlTo navKey Route.Login

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
