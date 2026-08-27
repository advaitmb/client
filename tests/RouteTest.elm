module RouteTest exposing (coldDocUrl, guestUrls, loggedInUrls, urlsTheAppBuilds)

{-| Tests at the ADR-0001 seam 8: which page a URL names.

`Main` itself cannot be tested -- every page `Model` carries a `Nav.Key`, which
no test can make -- so the decision lives in `Route` as a pure function of
(session kind, path), and `Main` only carries it out.

What these pin: a URL nobody planned for still lands on a page, and that page
is reached by the same code path (and so runs the same init commands) as one
the app linked to itself. Cold-loading `/<dbName>/<title>` used to land on a
spinner that never resolved (E4).

-}

import AppUrl
import Expect
import Import.Template as Template
import Route
import Test exposing (Test, describe, test)
import Url


{-| The landing a logged-in user gets for a URL, cold: nothing is on screen
yet, so no document was just minted by `/new`.
-}
loggedIn : String -> Route.Landing Route.LoggedInPage
loggedIn path =
    Route.loggedInLanding { fromNewDocument = False } (appUrl path)


{-| A URL as the browser hands it to `Browser.application`.
-}
appUrl : String -> AppUrl.AppUrl
appUrl path =
    Url.fromString ("http://localhost" ++ path)
        |> Maybe.map AppUrl.fromUrl
        -- Every URL below parses; this keeps a typo in one loud rather than
        -- letting it route somewhere plausible.
        |> Maybe.withDefault (AppUrl.fromPath [ "unparseable-test-url" ])


coldDocUrl : Test
coldDocUrl =
    describe "A URL naming a document and its title"
        [ test "opens the document the URL names" <|
            \_ ->
                (loggedIn "/abc123/my-document-title").page
                    |> Expect.equal (Route.Document { dbName = "abc123", isNew = False })
        , test "loads it rather than creating it: a document with a title exists" <|
            \_ ->
                Route.loggedInLanding { fromNewDocument = True } (appUrl "/abc123/my-document-title")
                    |> .page
                    |> Expect.equal (Route.Document { dbName = "abc123", isNew = False })
        , test "leaves the address bar alone: the title segment is the document's" <|
            \_ ->
                (loggedIn "/abc123/my-document-title").urlCorrection
                    |> Expect.equal Nothing
        , test "a trailing slash still names the document" <|
            \_ ->
                (loggedIn "/abc123/").page
                    |> Expect.equal (Route.Document { dbName = "abc123", isNew = False })
        , test "query parameters do not change which document opens" <|
            \_ ->
                (loggedIn "/abc123?ref=email").page
                    |> Expect.equal (Route.Document { dbName = "abc123", isNew = False })
        ]


loggedInUrls : Test
loggedInUrls =
    describe "With a session"
        [ test "the root opens the app itself" <|
            \_ ->
                loggedIn "/"
                    |> Expect.equal { page = Route.Home, urlCorrection = Nothing }
        , test "/new mints a document" <|
            \_ ->
                (loggedIn "/new").page
                    |> Expect.equal Route.NewDocument
        , test "a document id opens that document" <|
            \_ ->
                (loggedIn "/abc123").page
                    |> Expect.equal (Route.Document { dbName = "abc123", isNew = False })
        , test "the id /new just minted is a document to create, not to load" <|
            \_ ->
                Route.loggedInLanding { fromNewDocument = True } (appUrl "/abc123")
                    |> .page
                    |> Expect.equal (Route.Document { dbName = "abc123", isNew = True })
        , test "an import template imports it" <|
            \_ ->
                (loggedIn "/import/welcome").page
                    |> Expect.equal (Route.ImportTemplate Template.WelcomeTree)
        , test "a template nobody has falls back to the app" <|
            \_ ->
                (loggedIn "/import/no-such-template").page
                    |> Expect.equal Route.Home
        , test "the not-found segment is a screen, not a document title" <|
            \_ ->
                (loggedIn "/abc123/404-not-found").page
                    |> Expect.equal Route.DocumentNotFound
        , test "the login page is corrected to the app, with no history entry to go Back to" <|
            \_ ->
                loggedIn "/login"
                    |> Expect.equal
                        { page = Route.Home
                        , urlCorrection = Just Route.Root
                        }
        , test "so is the signup page" <|
            \_ ->
                loggedIn "/signup"
                    |> Expect.equal
                        { page = Route.Home
                        , urlCorrection = Just Route.Root
                        }
        , test "a path this app has no shape for says so, on a page with the sidebar" <|
            \_ ->
                (loggedIn "/abc123/deeper/still").page
                    |> Expect.equal Route.DocumentNotFound
        ]


guestUrls : Test
guestUrls =
    describe "Without a session"
        [ test "the root offers to create an account, at its own address" <|
            \_ ->
                Route.guestLanding (appUrl "/")
                    |> Expect.equal
                        { page = Route.SignupForm
                        , urlCorrection = Just Route.Signup
                        }
        , test "the login page is the login page" <|
            \_ ->
                Route.guestLanding (appUrl "/login")
                    |> Expect.equal { page = Route.LoginForm, urlCorrection = Nothing }
        , test "the signup page is the signup page" <|
            \_ ->
                Route.guestLanding (appUrl "/signup")
                    |> Expect.equal { page = Route.SignupForm, urlCorrection = Nothing }
        , test "a document URL offers the login form, at its own address" <|
            \_ ->
                Route.guestLanding (appUrl "/abc123/my-document-title")
                    |> Expect.equal
                        { page = Route.LoginForm
                        , urlCorrection = Just Route.Login
                        }
        , test "so does a URL only a signed-in user has a page for" <|
            \_ ->
                [ "/new", "/abc123", "/import/welcome", "/abc123/404-not-found" ]
                    |> List.map (appUrl >> Route.guestLanding)
                    |> Expect.equal
                        (List.repeat 4
                            { page = Route.LoginForm
                            , urlCorrection = Just Route.Login
                            }
                        )
        ]


{-| The other direction: every URL the app builds for itself has to parse back
to the page it was built for. `toString` and the patterns above are the two
halves of one mapping, written out separately -- this is what stops them
drifting apart (the `404-not-found` segment is spelled out in both).
-}
urlsTheAppBuilds : Test
urlsTheAppBuilds =
    let
        parsedBack route =
            (loggedIn (Route.toString route)).page
    in
    describe "Every URL the app builds"
        [ test "Root, DocNew, DocUntitled, Doc, NotFound" <|
            \_ ->
                [ Route.Root
                , Route.DocNew
                , Route.DocUntitled "abc123"
                , Route.Doc "abc123" "my-document-title"
                , Route.NotFound "abc123"
                ]
                    |> List.map parsedBack
                    |> Expect.equal
                        [ Route.Home
                        , Route.NewDocument
                        , Route.Document { dbName = "abc123", isNew = False }
                        , Route.Document { dbName = "abc123", isNew = False }
                        , Route.DocumentNotFound
                        ]
        , test "an Import URL for each template" <|
            \_ ->
                [ Template.WelcomeTree
                , Template.Timeline
                , Template.AcademicPaper
                , Template.ProjectBrainstorming
                , Template.HerosJourney
                ]
                    |> List.map (Route.Import >> parsedBack)
                    |> Expect.equal
                        [ Route.ImportTemplate Template.WelcomeTree
                        , Route.ImportTemplate Template.Timeline
                        , Route.ImportTemplate Template.AcademicPaper
                        , Route.ImportTemplate Template.ProjectBrainstorming
                        , Route.ImportTemplate Template.HerosJourney
                        ]
        , test "Login and Signup, for the session that has them" <|
            \_ ->
                [ Route.Login, Route.Signup ]
                    |> List.map (Route.toString >> appUrl >> Route.guestLanding >> .page)
                    |> Expect.equal [ Route.LoginForm, Route.SignupForm ]
        ]
