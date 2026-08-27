/**
 * The interface layer.
 *
 * Surfaces are being moved out of Elm one at a time. Each becomes a custom
 * element: Elm renders the tag and passes state down as attributes, the
 * element owns everything inside it, and it reports back with a bubbling
 * CustomEvent that Elm listens for with Html.Events.on.
 *
 * That boundary is the web platform's own, which is why it was chosen over
 * ports: attributes and events need no encoder/decoder pair per message, and
 * a surface can be moved (or moved back) without touching anything else.
 *
 * Moved so far:
 *   gw-help-modal   Doc/HelpScreen.elm
 *
 * Still in Elm: the card tree, the header and sidebar, the document list,
 * and the remaining modals.
 */

import "./help-modal";
