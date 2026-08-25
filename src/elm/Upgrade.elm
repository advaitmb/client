module Upgrade exposing (Model, Msg(..), init, toValue, update, view)

{-| Self-host stub — no payments on a local instance.

Upstream this module renders the paid-plan checkout modal: currency/billing/plan
pickers, a Stripe Checkout button, and a `climate.stripe.com` badge. None of it
can fire here (the account menu no longer offers an upgrade or manage-billing
entry, and the server has no Stripe routes), and leaving it compiled in shipped
a stripe.com link inside `elm.js`.

The public API is kept identical to upstream — same `Model`, same `Msg`
constructors and payload types, same signatures — so `Session.elm` and
`Page/App.elm` compile untouched. That deliberately keeps the whole removal to
this one file plus the sidebar, instead of unpicking the modal's wiring out of
`App.elm`, which upstream changes often.

The original is kept at `~/gingko/patches/Upgrade.elm.upstream-backup`.

-}

import Html exposing (Html)
import Json.Encode as Enc



-- MODEL


type alias Model =
    {}


type BillingFrequency
    = Monthly
    | Yearly


type Plan
    = Regular
    | Discount
    | Bonus


init : Model
init =
    {}



-- UPDATE


type Msg
    = CurrencySelected String
    | BillingChanged BillingFrequency
    | PlanChanged Plan
    | PWYWToggled Bool
    | CheckoutClicked Model
    | UpgradeModalClosed


update : Msg -> Model -> Model
update _ model =
    model


{-| Upstream this encodes the chosen plan for the Stripe checkout port. Nothing
listens for that message any more, so the payload is inert.
-}
toValue : String -> Model -> Enc.Value
toValue _ _ =
    Enc.null



-- VIEW


view : Maybe Int -> Model -> List (Html Msg)
view _ _ =
    []
