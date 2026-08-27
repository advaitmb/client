/** @type {import('tailwindcss').Config} */
module.exports = {
  corePlugins: {
    preflight: false,
  },
  content: ["./src/elm/**/*.elm", "./src/ui/**/*.ts"],
  theme: {
    extend: {},
  },
  plugins: [],
}

