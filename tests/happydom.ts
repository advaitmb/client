// bun test preload (see bunfig.toml): registers happy-dom's window,
// document, customElements, etc. as globals so custom elements can be
// exercised through real DOM APIs (ADR-0001 seam 3).
import { GlobalRegistrator } from "@happy-dom/global-registrator";

GlobalRegistrator.register();
