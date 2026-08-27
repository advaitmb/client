module Route exposing
    ( GuestPage(..)
    , Landing
    , LoggedInPage(..)
    , Route(..)
    , UrlChange(..)
    , guestLanding
    , loggedInLanding
    , pushUrl
    , replaceUrl
    , toString
    )

{-| The app's URLs, in both directions: `toString` builds them, and
`loggedInLanding`/`guestLanding` decide what a URL the browser hands back
means.

There is no `Url.Parser` here on purpose -- the paths are shallow enough to
pattern match on, which is what `AppUrl` is for -- but the decision is kept a
pure function of (session, path) so it can be tested: `Main`'s own pages all
carry a `Nav.Key`, which no test can make (ADR-0001 seam 8).

Every path lands on a page. A URL nobody planned for still gets a deliberate
destination whose init commands then run, because the alternative is what E4
was: a cold-loaded URL sitting on a spinner forever, waiting for a page that
was never initialized.

-}

import AppUrl
import Browser.Navigation as Nav
import Import.Template as Template exposing (Template)


type Route
    = Root
    | Signup
    | Login
    | DocNew
    | DocUntitled String
    | Doc String String
    | Import Template
    | NotFound String


{-| Where a URL sends the app: the page to show, and the correction to make to
the address bar (a URL the app would never have built itself, or one that
names a page this session cannot have).
-}
type alias Landing page =
    { page : page
    , urlChange : Maybe UrlChange
    }


type UrlChange
    = Push Route
    | Replace Route


{-| The pages a logged-in session can be on.
-}
type LoggedInPage
    = Home
    | Document { dbName : String, isNew : Bool }
    | DocumentNotFound
    | NewDocument
    | ImportTemplate Template


{-| `fromNewDocument` says the id in the URL was just minted by `/new`, so the
document is to be created rather than loaded. It is a property of the page the
app is coming from, which is why it is passed in rather than read off the URL.
-}
loggedInLanding : { fromNewDocument : Bool } -> AppUrl.AppUrl -> Landing LoggedInPage
loggedInLanding { fromNewDocument } appUrl =
    let
        openDoc dbName =
            page (Document { dbName = dbName, isNew = fromNewDocument })
    in
    case appUrl.path of
        [] ->
            page Home

        [ "new" ] ->
            page NewDocument

        [ "import", templateName ] ->
            case Template.fromString templateName of
                Just template ->
                    page (ImportTemplate template)

                Nothing ->
                    page Home

        [ "login" ] ->
            -- Already logged in: there is nothing on these two pages for this
            -- session. Correct the URL rather than pushing a new entry, or
            -- Back would land on them again.
            redirect Home Root

        [ "signup" ] ->
            redirect Home Root

        [ dbName ] ->
            openDoc dbName

        -- Order matters: `/<dbName>/404-not-found` (what `NotFound` builds, and
        -- where a failed load sends the user) is a document URL otherwise.
        [ _, "404-not-found" ] ->
            page DocumentNotFound

        [ dbName, _ ] ->
            -- `/<dbName>/<title>`, what `Doc` builds: the second segment is
            -- the document's name, along for readability only.
            openDoc dbName

        _ ->
            -- No such shape. Say so on the page the user can act on, listing
            -- their documents, instead of leaving them on a spinner (E4).
            page DocumentNotFound


{-| The pages a session without a user can be on. Every other URL is a page
this session cannot have, so it lands here too -- an address bar left pointing
at a document nobody is signed in to open is how E4 looked from the guest side.
-}
type GuestPage
    = LoginForm
    | SignupForm


guestLanding : AppUrl.AppUrl -> Landing GuestPage
guestLanding appUrl =
    case appUrl.path of
        [] ->
            redirect SignupForm Signup

        [ "login" ] ->
            page LoginForm

        [ "signup" ] ->
            page SignupForm

        _ ->
            redirect LoginForm Login


page : page -> Landing page
page p =
    { page = p, urlChange = Nothing }


redirect : page -> Route -> Landing page
redirect p route =
    { page = p, urlChange = Just (Replace route) }


toString : Route -> String
toString route =
    case route of
        Root ->
            "/"

        Signup ->
            "/signup"

        Login ->
            "/login"

        DocNew ->
            "/new"

        DocUntitled dbName ->
            "/" ++ dbName

        Doc dbName docName ->
            "/" ++ dbName ++ "/" ++ docName

        Import template ->
            "/import/" ++ Template.toString template

        NotFound dbName ->
            "/" ++ dbName ++ "/404-not-found"


replaceUrl : Nav.Key -> Route -> Cmd msg
replaceUrl navKey route =
    Nav.replaceUrl navKey (toString route)


pushUrl : Nav.Key -> Route -> Cmd msg
pushUrl navKey route =
    Nav.pushUrl navKey (toString route)
