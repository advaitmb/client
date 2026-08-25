// Browser globals this app attaches at runtime. Declared so `tsc --checkJs`
// can verify the rest of the file instead of drowning in "does not exist on
// type 'Window'".
declare global {
  interface Window {
    elmMessages: Array<{ tag: string; data: unknown }>;
    checkboxClicked: (cardId: string, checkboxNumber: number) => void;
  }
}
export {};
